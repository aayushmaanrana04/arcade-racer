extends VehicleBody3D

# ─────────────────────────────────────────────
# DRIFT STATE
# ─────────────────────────────────────────────
enum DriftState {
	GRIP,
	DRIFT
}

var drift_state: DriftState = DriftState.GRIP

# Confidence timer (THIS FIXES FLICKER)
var drift_confidence: float = 0.0
@export var drift_enter_time := 0.15   # seconds required to ENTER drift
@export var drift_exit_time  := 0.25   # seconds required to EXIT drift

@export var drift_rear_grip: float = 0.9
var normal_rear_grip: float = 0.0


# ─────────────────────────────────────────────
# DRIFT SMOKE (VISUAL)
# ─────────────────────────────────────────────
@onready var smoke_rl: GPUParticles3D = $visuals/driftSmoke_bl
@onready var smoke_rr: GPUParticles3D = $visuals/driftSmoke_br
var smoke_nodes: Array[GPUParticles3D]


# ─────────────────────────────────────────────
# DRIVING TUNING
# ─────────────────────────────────────────────
@export var engine_force_max := 5000.0
@export var brake_force := 20.0
@export var max_steer_angle := 0.8
@export var steer_speed := 6.0

var steer_target := 0.0


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
# READY
# ─────────────────────────────────────────────
func _ready():
	normal_rear_grip = wheel_rl.wheel_friction_slip

	smoke_nodes = [smoke_rl, smoke_rr]
	for smoke in smoke_nodes:
		smoke.emitting = false


# ─────────────────────────────────────────────
# PHYSICS LOOP
# ─────────────────────────────────────────────
func _physics_process(delta: float):
	_handle_input(delta)
	update_drift_state(delta)
	apply_yaw_assist()
	_sync_wheels(delta)
	update_drift_smoke()

	# Debug (remove later)
	print(
		"conf:", snapped(drift_confidence, 0.01),
		" slip:", snapped(rad_to_deg(get_filtered_slip_angle()), 0.1),
		" lat:", snapped(get_lateral_speed(), 0.1),
		" state:", drift_state
	)


# ─────────────────────────────────────────────
# INPUT / VEHICLE CONTROL
# ─────────────────────────────────────────────
func _handle_input(delta: float):
	var throttle := 0.0
	var brake := 0.0
	var steer_input := 0.0

	if Input.is_action_pressed("accelerate"):
		throttle = engine_force_max
	elif Input.is_action_pressed("brake"):
		brake = brake_force

	if Input.is_action_pressed("steer_left"):
		steer_input = 1.0
	elif Input.is_action_pressed("steer_right"):
		steer_input = -1.0

	steer_target = steer_input * max_steer_angle
	var steer_multiplier := 1.3 if drift_state == DriftState.DRIFT else 1.0

	steering = lerp(
		steering,
		steer_target * steer_multiplier,
		steer_speed * delta
	)

	engine_force = throttle
	self.brake = brake


# ─────────────────────────────────────────────
# SLIP & LATERAL MOTION
# ─────────────────────────────────────────────
func get_slip_angle() -> float:
	if linear_velocity.length() < 1.0:
		return 0.0

	var forward := -global_transform.basis.z
	var vel_dir := linear_velocity.normalized()
	return forward.signed_angle_to(vel_dir, Vector3.UP)


func get_filtered_slip_angle() -> float:
	var slip := get_slip_angle()
	if abs(slip) < deg_to_rad(4.0):
		return 0.0
	return slip


func get_lateral_speed() -> float:
	var local_velocity := global_transform.basis.inverse() * linear_velocity
	return abs(local_velocity.x)


# ─────────────────────────────────────────────
# DRIFT INTENT (PURE SIGNAL)
# ─────────────────────────────────────────────
func has_drift_intent() -> bool:
	if linear_velocity.length() < 7.0:
		return false

	return (
		abs(get_filtered_slip_angle()) > deg_to_rad(8.0)
		and get_lateral_speed() > 0.6
		and Input.is_action_pressed("accelerate")
	)


# ─────────────────────────────────────────────
# DRIFT STATE MACHINE (STABLE)
# ─────────────────────────────────────────────
func update_drift_state(delta: float):
	if has_drift_intent():
		drift_confidence += delta
	else:
		drift_confidence -= delta

	drift_confidence = clamp(drift_confidence, 0.0, drift_exit_time)

	if drift_state == DriftState.GRIP:
		if drift_confidence >= drift_enter_time:
			enter_drift()

	elif drift_state == DriftState.DRIFT:
		if drift_confidence <= 0.0:
			exit_drift()


func enter_drift():
	drift_state = DriftState.DRIFT
	wheel_rl.wheel_friction_slip = drift_rear_grip
	wheel_rr.wheel_friction_slip = drift_rear_grip


func exit_drift():
	drift_state = DriftState.GRIP
	wheel_rl.wheel_friction_slip = normal_rear_grip
	wheel_rr.wheel_friction_slip = normal_rear_grip


# ─────────────────────────────────────────────
# YAW ASSIST
# ─────────────────────────────────────────────
func apply_yaw_assist():
	if drift_state != DriftState.DRIFT:
		return

	var slip := get_filtered_slip_angle()
	apply_torque(Vector3.UP * -slip * 0.7)


# ─────────────────────────────────────────────
# WHEEL VISUAL SYNC
# ─────────────────────────────────────────────
func _sync_wheels(delta: float):
	_sync_wheel(wheel_fl, mesh_fl, delta)
	_sync_wheel(wheel_fr, mesh_fr, delta)
	_sync_wheel(wheel_rl, mesh_rl, delta)
	_sync_wheel(wheel_rr, mesh_rr, delta)


func _sync_wheel(wheel: VehicleWheel3D, mesh: Node3D, delta: float):
	mesh.global_position = wheel.global_position

	if wheel.use_as_steering:
		mesh.rotation = Vector3.ZERO
		mesh.rotate_object_local(Vector3.UP, wheel.steering)

	var roll_amount := wheel.get_rpm() * TAU * delta / 60.0
	mesh.rotate_object_local(Vector3.RIGHT, roll_amount)


# ─────────────────────────────────────────────
# DRIFT SMOKE
# ─────────────────────────────────────────────
func update_drift_smoke():
	var enable := drift_state == DriftState.DRIFT

	for smoke in smoke_nodes:
		smoke.emitting = enable

	smoke_rl.global_position = mesh_rl.global_position
	smoke_rr.global_position = mesh_rr.global_position
