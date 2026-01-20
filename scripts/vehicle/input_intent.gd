class_name InputIntent
extends RefCounted
## Pure input-to-intent layer.
## Reads raw input, writes intent values only.
## NEVER touches wheels, RPM, drift, or physics.

# ─────────────────────────────────────────────
# INTENT VALUES (Tier 1 - Writable)
# ─────────────────────────────────────────────
var throttle: float = 0.0
var brake: float = 0.0
var steer: float = 0.0
var handbrake: float = 0.0

# ─────────────────────────────────────────────
# RAMPING CONFIG (Higher = snappier)
# ─────────────────────────────────────────────
var throttle_ramp_up: float = 20.0
var throttle_ramp_down: float = 6.0   # Slower release for keyboard drifting
var brake_ramp_up: float = 25.0
var brake_ramp_down: float = 15.0
var steer_ramp: float = 0.0  # 0 = instant, let car_v2 handle smoothing


func update(delta: float) -> void:
	_update_throttle(delta)
	_update_brake(delta)
	_update_steer(delta)
	_update_handbrake()


func _update_throttle(delta: float) -> void:
	var target := 1.0 if Input.is_action_pressed("accelerate") else 0.0
	var ramp := throttle_ramp_up if target > throttle else throttle_ramp_down
	throttle = move_toward(throttle, target, ramp * delta)


func _update_brake(delta: float) -> void:
	var target := 1.0 if Input.is_action_pressed("brake") else 0.0
	var ramp := brake_ramp_up if target > brake else brake_ramp_down
	brake = move_toward(brake, target, ramp * delta)


func _update_steer(_delta: float) -> void:
	var target := 0.0
	if Input.is_action_pressed("steer_left"):
		target = 1.0
	elif Input.is_action_pressed("steer_right"):
		target = -1.0
	# Instant steering - let the car script handle smoothing
	steer = target


func _update_handbrake() -> void:
	handbrake = 1.0 if Input.is_action_pressed("handbrake") else 0.0


## Reset all intent values to neutral
func reset() -> void:
	throttle = 0.0
	brake = 0.0
	steer = 0.0
	handbrake = 0.0
