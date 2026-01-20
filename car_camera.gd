extends Camera3D

@onready var car := get_parent() as VehicleBody3D

@export var height := 2.0
@export var distance := 6.0
@export var follow_speed := 6.0
@export var look_ahead := 4.0

# FOV tuning
@export var base_fov := 70.0
@export var max_fov := 90.0
@export var fov_speed := 1.0
@export var speed_for_max_fov: float = 40.0

# Cosmetic effects
@export_group("Cosmetic Effects")
@export var drift_fov_boost := 6.0       # Extra FOV during drift
@export var camera_tilt := 3.0           # Degrees of roll during turning
@export var speed_height_drop := 0.4     # How much lower at max speed

# Internal smoothing
var smooth_forward: Vector3 = Vector3.FORWARD
var smooth_tilt: float = 0.0


func _ready():
	fov = base_fov


func _physics_process(delta: float):
	if car == null:
		return

	# --------------------------------------------------
	# SPEED
	# --------------------------------------------------
	var speed: float = car.linear_velocity.length()
	var speed_ratio: float = clamp(speed / speed_for_max_fov, 0.0, 1.0)

	# --------------------------------------------------
	# DRIFT DETECTION (for cosmetic effects)
	# --------------------------------------------------
	var drift_amount := 0.0
	var lateral_vel := 0.0
	if speed > 5.0:
		var car_forward := -car.global_transform.basis.z
		var car_right := car.global_transform.basis.x
		lateral_vel = car_right.dot(car.linear_velocity)
		var vel_dir := car.linear_velocity.normalized()
		var slip := car_forward.signed_angle_to(vel_dir, Vector3.UP)
		drift_amount = clampf(absf(rad_to_deg(slip)) / 30.0, 0.0, 1.0)

	# --------------------------------------------------
	# INTENDED DIRECTION (VELOCITY FIRST)
	# --------------------------------------------------
	var target_forward: Vector3

	if speed > 1.5:
		# Look where the car is actually moving
		target_forward = car.linear_velocity.normalized()
	else:
		# Fallback when almost stopped
		target_forward = -car.global_transform.basis.z

	# Smooth direction (kills jitter completely)
	smooth_forward = smooth_forward.slerp(
		target_forward,
		5.0 * delta
	)

	# --------------------------------------------------
	# CAMERA POSITION (LAGGED)
	# --------------------------------------------------
	var current_height := height - (speed_height_drop * speed_ratio)

	var target_pos := car.global_position
	target_pos -= smooth_forward * distance
	target_pos.y += current_height

	global_position = global_position.lerp(
		target_pos,
		follow_speed * delta
	)

	# --------------------------------------------------
	# LOOK TARGET
	# --------------------------------------------------
	var look_target := car.global_position + smooth_forward * look_ahead
	look_at(look_target, Vector3.UP)

	# --------------------------------------------------
	# CAMERA TILT (Cosmetic roll during turns)
	# --------------------------------------------------
	var target_tilt := 0.0
	if speed > 3.0:
		target_tilt = clampf(lateral_vel / 8.0, -1.0, 1.0) * camera_tilt

	smooth_tilt = lerpf(smooth_tilt, target_tilt, 4.0 * delta)
	rotate_object_local(Vector3.FORWARD, deg_to_rad(smooth_tilt))

	# --------------------------------------------------
	# FOV SCALING (Speed + drift boost)
	# --------------------------------------------------
	var target_fov: float = lerp(base_fov, max_fov, speed_ratio)
	target_fov += drift_fov_boost * drift_amount

	fov = lerp(fov, target_fov, fov_speed * delta)
