extends VehicleBody3D
## Car Orchestrator - coordinates all vehicle subsystems.
## This script ONLY orchestrates. It contains NO logic for:
## - Input handling (InputIntent)
## - Torque calculation (Powertrain)
## - Torque distribution (Drivetrain)
## - State derivation (CarState)
## - Drift detection (DriftStateMachine)

# ─────────────────────────────────────────────
# SUBSYSTEMS (Composition over inheritance)
# ─────────────────────────────────────────────
var intent: InputIntent
var powertrain: Powertrain
var drivetrain: Drivetrain
var car_state: CarState
var drift_fsm: DriftStateMachine

# ─────────────────────────────────────────────
# TUNING - EXPOSED FOR EDITOR
# ─────────────────────────────────────────────
@export_group("Engine")
@export var engine_torque: float = 400.0
@export var brake_force: float = 20.0
@export var handbrake_force: float = 80.0

@export_group("Steering")
@export var max_steer_angle: float = 0.8
@export var steer_speed: float = 6.0

@export_group("Drift")
@export var drift_rear_grip: float = 0.9
@export var drift_front_grip: float = 0.95  # Front also loosens slightly to preserve momentum
@export var drift_steer_multiplier: float = 1.3
@export var drift_min_throttle: float = 0.3  # Minimum throttle during drift (keyboard assist)

@export_group("Drivetrain")
@export_enum("RWD", "FWD", "AWD") var drive_type: int = 0
@export_range(0.0, 1.0) var awd_front_bias: float = 0.4

# ─────────────────────────────────────────────
# WHEEL REFERENCES (PHYSICS)
# ─────────────────────────────────────────────
@onready var wheel_fl: VehicleWheel3D = $tyre_fl
@onready var wheel_fr: VehicleWheel3D = $tyre_fr
@onready var wheel_rl: VehicleWheel3D = $tyre_bl
@onready var wheel_rr: VehicleWheel3D = $tyre_br

# ─────────────────────────────────────────────
# WHEEL REFERENCES (VISUALS)
# ─────────────────────────────────────────────
@onready var mesh_fl: Node3D = $visuals/tyre_fl
@onready var mesh_fr: Node3D = $visuals/tyre_fr
@onready var mesh_rl: Node3D = $visuals/tyre_bl
@onready var mesh_rr: Node3D = $visuals/tyre_br

# ─────────────────────────────────────────────
# DRIFT SMOKE (VISUAL)
# ─────────────────────────────────────────────
@onready var smoke_rl: GPUParticles3D = $visuals/driftSmoke_bl
@onready var smoke_rr: GPUParticles3D = $visuals/driftSmoke_br
var smoke_nodes: Array[GPUParticles3D]

# ─────────────────────────────────────────────
# ENGINE AUDIO
# ─────────────────────────────────────────────
@onready var engine_audio: Node3D = $EngineAudio

# ─────────────────────────────────────────────
# INTERNAL STATE
# ─────────────────────────────────────────────
var normal_rear_grip: float = 0.0
var normal_front_grip: float = 0.0
var current_steer: float = 0.0


func _ready() -> void:
	_init_subsystems()
	_cache_base_values()
	_connect_signals()


func _init_subsystems() -> void:
	intent = InputIntent.new()
	powertrain = Powertrain.new()
	drivetrain = Drivetrain.new()
	car_state = CarState.new()
	drift_fsm = DriftStateMachine.new()

	# Configure powertrain
	powertrain.base_engine_torque = engine_torque

	# Configure drivetrain
	match drive_type:
		0: drivetrain.set_rwd()
		1: drivetrain.set_fwd()
		2: drivetrain.set_awd(awd_front_bias)

	# Configure drift
	drift_fsm.drift_grip_multiplier = drift_rear_grip


func _cache_base_values() -> void:
	normal_rear_grip = wheel_rl.wheel_friction_slip
	normal_front_grip = wheel_fl.wheel_friction_slip
	smoke_nodes = [smoke_rl, smoke_rr]
	for smoke in smoke_nodes:
		smoke.emitting = false


func _connect_signals() -> void:
	drift_fsm.drift_started.connect(_on_drift_started)
	drift_fsm.drift_ended.connect(_on_drift_ended)


# ─────────────────────────────────────────────
# PHYSICS LOOP - ORCHESTRATION ONLY
# ─────────────────────────────────────────────
func _physics_process(delta: float) -> void:
	# STEP 1: Update intent from input
	intent.update(delta)

	# STEP 2: Update derived state from physics
	car_state.update(self)

	# STEP 3: Update drift state machine
	drift_fsm.update(delta, car_state, intent.throttle > 0.1)

	# STEP 4: Calculate effective throttle (with drift assist for keyboard)
	var effective_throttle := intent.throttle
	if drift_fsm.is_drifting() and intent.throttle < drift_min_throttle:
		# Keyboard assist: maintain minimum throttle during drift
		effective_throttle = drift_min_throttle

	# STEP 5: Calculate engine torque
	var wheel_rpm := powertrain.estimate_wheel_rpm(wheel_rl.wheel_radius, car_state.speed)
	powertrain.update_rpm(delta, wheel_rpm, effective_throttle)
	powertrain.auto_shift()
	var engine_torque_out := powertrain.compute_requested_torque(effective_throttle, car_state.speed)

	# STEP 5: Distribute torque via drivetrain
	var torque_split := drivetrain.distribute_torque(engine_torque_out)
	var brake_split := drivetrain.distribute_brake(brake_force * intent.brake)

	# STEP 6: Apply forces to wheels
	_apply_drive_forces(torque_split, brake_split)

	# STEP 7: Apply steering
	_apply_steering(delta)

	# STEP 8: Apply drift grip modification
	_apply_drift_grip()

	# STEP 9: Apply yaw assist during drift
	_apply_yaw_assist()

	# STEP 10: Sync visuals (non-physics)
	_sync_wheel_visuals(delta)
	_update_drift_smoke()

	# STEP 11: Update engine audio
	_update_engine_audio()

	# Debug output
	_debug_print()


# ─────────────────────────────────────────────
# FORCE APPLICATION (Only place forces are applied)
# ─────────────────────────────────────────────
func _apply_drive_forces(torque_split: Dictionary, brake_split: Dictionary) -> void:
	var handbrake_active := intent.handbrake > 0.5

	# Front axle
	var front_torque: float = torque_split.get("front", 0.0)
	if front_torque > 0.0:
		wheel_fl.engine_force = front_torque * 0.5
		wheel_fr.engine_force = front_torque * 0.5
	else:
		wheel_fl.engine_force = 0.0
		wheel_fr.engine_force = 0.0

	# Rear axle - cut power when handbrake is on
	var rear_torque: float = torque_split.get("rear", 0.0)
	if rear_torque > 0.0 and not handbrake_active:
		wheel_rl.engine_force = rear_torque * 0.5
		wheel_rr.engine_force = rear_torque * 0.5
	else:
		wheel_rl.engine_force = 0.0
		wheel_rr.engine_force = 0.0

	# Brakes (all wheels)
	var front_brake: float = brake_split.get("front", 0.0)
	var rear_brake: float = brake_split.get("rear", 0.0)
	wheel_fl.brake = front_brake * 0.5
	wheel_fr.brake = front_brake * 0.5

	# Handbrake - lock rear wheels
	if handbrake_active:
		wheel_rl.brake = handbrake_force
		wheel_rr.brake = handbrake_force
	else:
		wheel_rl.brake = rear_brake * 0.5
		wheel_rr.brake = rear_brake * 0.5


func _apply_steering(delta: float) -> void:
	var steer_target := intent.steer * max_steer_angle

	# Drift state increases steering sensitivity
	var steer_mult := drift_steer_multiplier if drift_fsm.is_drifting() else 1.0
	var final_target := steer_target * steer_mult

	# Use move_toward for consistent, speed-based steering (not framerate dependent)
	# steer_speed of 8 = full lock in ~0.12s
	current_steer = move_toward(current_steer, final_target, steer_speed * delta)
	steering = current_steer


func _apply_drift_grip() -> void:
	var is_drifting := drift_fsm.is_drifting()
	var handbrake_active := intent.handbrake > 0.5

	# Rear grip - reduces during drift or handbrake
	var rear_mult := 1.0
	if handbrake_active:
		rear_mult = 0.5  # Very low grip for handbrake turns
	elif is_drifting:
		rear_mult = drift_rear_grip
	var rear_grip := normal_rear_grip * rear_mult
	wheel_rl.wheel_friction_slip = rear_grip
	wheel_rr.wheel_friction_slip = rear_grip

	# Front grip - reduces slightly during drift to preserve momentum
	var front_mult := drift_front_grip if is_drifting else 1.0
	var front_grip := normal_front_grip * front_mult
	wheel_fl.wheel_friction_slip = front_grip
	wheel_fr.wheel_friction_slip = front_grip


func _apply_yaw_assist() -> void:
	if not drift_fsm.is_drifting():
		return

	# Counter-rotate to maintain control during drift
	var slip := car_state.slip_angle
	apply_torque(Vector3.UP * -slip * 0.7)


# ─────────────────────────────────────────────
# VISUAL SYNC (Non-physics)
# ─────────────────────────────────────────────
func _sync_wheel_visuals(delta: float) -> void:
	_sync_wheel(wheel_fl, mesh_fl, delta)
	_sync_wheel(wheel_fr, mesh_fr, delta)
	_sync_wheel(wheel_rl, mesh_rl, delta)
	_sync_wheel(wheel_rr, mesh_rr, delta)


func _sync_wheel(wheel: VehicleWheel3D, mesh: Node3D, delta: float) -> void:
	mesh.global_position = wheel.global_position

	if wheel.use_as_steering:
		mesh.rotation = Vector3.ZERO
		mesh.rotate_object_local(Vector3.UP, wheel.steering)

	var roll_amount := wheel.get_rpm() * TAU * delta / 60.0
	mesh.rotate_object_local(Vector3.RIGHT, roll_amount)


func _update_drift_smoke() -> void:
	var enable := drift_fsm.is_drifting()

	for smoke in smoke_nodes:
		smoke.emitting = enable

	smoke_rl.global_position = mesh_rl.global_position
	smoke_rr.global_position = mesh_rr.global_position


func _update_engine_audio() -> void:
	if engine_audio == null:
		return

	# Feed powertrain state to audio controller
	engine_audio.set_engine_state(
		powertrain.current_rpm,
		powertrain.redline_rpm,
		intent.throttle,
		powertrain.is_revving
	)


# ─────────────────────────────────────────────
# SIGNAL HANDLERS
# ─────────────────────────────────────────────
func _on_drift_started() -> void:
	# Hook for audio, particles, etc.
	pass


func _on_drift_ended() -> void:
	# Hook for audio, particles, etc.
	pass


# ─────────────────────────────────────────────
# DEBUG
# ─────────────────────────────────────────────
func _debug_print() -> void:
	print(
		"RPM:", snapped(powertrain.current_rpm, 1),
		" Gear:", powertrain.current_gear,
		" Slip:", snapped(car_state.slip_angle_deg, 0.1),
		" Lat:", snapped(car_state.lateral_speed, 0.1),
		" Drift:", drift_fsm.current_state
	)


# ─────────────────────────────────────────────
# PUBLIC API (For upgrades, tuning, etc.)
# ─────────────────────────────────────────────

## Get current speed in km/h
func get_speed_kmh() -> float:
	return car_state.speed_kmh


## Check if currently drifting
func is_drifting() -> bool:
	return drift_fsm.is_drifting()


## Get current gear (0 = reverse, 1+ = forward)
func get_current_gear() -> int:
	return powertrain.current_gear


## Get current RPM
func get_current_rpm() -> float:
	return powertrain.current_rpm


## Apply upgrade multiplier to engine torque
func apply_engine_upgrade(multiplier: float) -> void:
	powertrain.base_engine_torque = engine_torque * multiplier


## Switch drive type at runtime
func set_drive_type(type: Drivetrain.DriveType, front_bias: float = 0.4) -> void:
	match type:
		Drivetrain.DriveType.RWD:
			drivetrain.set_rwd()
		Drivetrain.DriveType.FWD:
			drivetrain.set_fwd()
		Drivetrain.DriveType.AWD:
			drivetrain.set_awd(front_bias)
