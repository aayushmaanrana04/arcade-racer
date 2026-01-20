class_name CarState
extends RefCounted
## Derived vehicle state - READ ONLY.
## Computed from physics, consumed by other systems.
## NEVER writes back to physics.

# ─────────────────────────────────────────────
# SPEED & VELOCITY
# ─────────────────────────────────────────────
var speed: float = 0.0                    # Magnitude of velocity (m/s)
var speed_kmh: float = 0.0                # Speed in km/h
var forward_speed: float = 0.0            # Signed speed along car's forward axis
var lateral_speed: float = 0.0            # Absolute lateral velocity
var velocity: Vector3 = Vector3.ZERO      # World-space velocity
var local_velocity: Vector3 = Vector3.ZERO  # Car-local velocity

# ─────────────────────────────────────────────
# ORIENTATION & SLIP
# ─────────────────────────────────────────────
var slip_angle: float = 0.0               # Radians - angle between heading and velocity
var slip_angle_deg: float = 0.0           # Degrees
var is_sliding: bool = false              # Significant lateral motion detected
var heading: Vector3 = Vector3.FORWARD    # Car's forward direction (world space)

# ─────────────────────────────────────────────
# GROUND CONTACT
# ─────────────────────────────────────────────
var is_grounded: bool = true
var wheels_on_ground: int = 4

# ─────────────────────────────────────────────
# THRESHOLDS
# ─────────────────────────────────────────────
const MIN_SPEED_FOR_SLIP: float = 1.0
const SLIP_ANGLE_DEADZONE: float = 4.0    # Degrees
const SLIDING_THRESHOLD: float = 0.6      # m/s lateral


## Update all derived state from VehicleBody3D
func update(car: VehicleBody3D) -> void:
	_update_velocity(car)
	_update_slip(car)
	_update_ground_contact(car)


func _update_velocity(car: VehicleBody3D) -> void:
	velocity = car.linear_velocity
	speed = velocity.length()
	speed_kmh = speed * 3.6

	heading = -car.global_transform.basis.z
	local_velocity = car.global_transform.basis.inverse() * velocity

	forward_speed = -local_velocity.z  # Negative Z is forward in Godot
	lateral_speed = absf(local_velocity.x)


func _update_slip(car: VehicleBody3D) -> void:
	if speed < MIN_SPEED_FOR_SLIP:
		slip_angle = 0.0
		slip_angle_deg = 0.0
		is_sliding = false
		return

	# Angle between heading and velocity direction
	var vel_dir := velocity.normalized()
	slip_angle = heading.signed_angle_to(vel_dir, Vector3.UP)
	slip_angle_deg = rad_to_deg(slip_angle)

	# Apply deadzone
	if absf(slip_angle_deg) < SLIP_ANGLE_DEADZONE:
		slip_angle = 0.0
		slip_angle_deg = 0.0

	is_sliding = lateral_speed > SLIDING_THRESHOLD


func _update_ground_contact(car: VehicleBody3D) -> void:
	# Count wheels touching ground
	wheels_on_ground = 0
	for i in car.get_child_count():
		var child := car.get_child(i)
		if child is VehicleWheel3D:
			if child.is_in_contact():
				wheels_on_ground += 1

	is_grounded = wheels_on_ground >= 2


## Check if car is moving forward (not reversing)
func is_moving_forward() -> bool:
	return forward_speed > 0.5


## Check if car is effectively stopped
func is_stopped() -> bool:
	return speed < 0.5


## Get normalized speed (0-1) based on max expected speed
func get_normalized_speed(max_speed: float = 50.0) -> float:
	return clampf(speed / max_speed, 0.0, 1.0)
