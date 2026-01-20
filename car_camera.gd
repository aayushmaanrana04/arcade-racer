extends Camera3D

@onready var car := get_parent() as VehicleBody3D

@export var height := 2.0
@export var distance := 6.0
@export var follow_speed := 6.0
@export var look_ahead := 4.0

# FOV tuning (unchanged)
@export var base_fov := 70.0
@export var max_fov := 90.0
@export var fov_speed := 1.0
@export var speed_for_max_fov: float = 40.0

# Internal smoothing
var smooth_forward: Vector3 = Vector3.FORWARD


func _ready():
	fov = base_fov


func _physics_process(delta: float):
	if car == null:
		return

	# --------------------------------------------------
	# SPEED
	# --------------------------------------------------
	var speed: float = car.linear_velocity.length()

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
	var target_pos := car.global_position
	target_pos -= smooth_forward * distance
	target_pos.y += height

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
	# FOV SCALING (UNCHANGED)
	# --------------------------------------------------
	var speed_ratio: float = clamp(speed / speed_for_max_fov, 0.0, 1.0)
	var target_fov: float = lerp(base_fov, max_fov, speed_ratio)

	fov = lerp(fov, target_fov, fov_speed * delta)
