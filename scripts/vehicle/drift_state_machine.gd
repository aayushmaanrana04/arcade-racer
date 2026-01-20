class_name DriftStateMachine
extends RefCounted
## Time-stable drift state machine.
## Consumes CarState, modifies grip multipliers.
## NEVER reads input directly - uses CarState only.

signal drift_started
signal drift_ended

enum State {
	GRIP,
	DRIFT
}

# ─────────────────────────────────────────────
# STATE
# ─────────────────────────────────────────────
var current_state: State = State.GRIP
var drift_confidence: float = 0.0

# ─────────────────────────────────────────────
# TIMING (Prevents flicker)
# ─────────────────────────────────────────────
var drift_enter_time: float = 0.15    # Seconds to confirm drift
var drift_exit_time: float = 0.25     # Seconds to confirm grip recovery

# ─────────────────────────────────────────────
# THRESHOLDS
# ─────────────────────────────────────────────
var min_speed: float = 7.0            # Minimum speed for drift
var min_slip_angle: float = 8.0       # Degrees
var min_lateral_speed: float = 0.6    # m/s

# ─────────────────────────────────────────────
# GRIP MODIFIERS (Output)
# ─────────────────────────────────────────────
var rear_grip_multiplier: float = 1.0
var drift_grip_multiplier: float = 0.9  # Applied during drift


## Update drift state machine
## throttle_pressed: whether throttle is held (for intent detection)
func update(delta: float, car_state: CarState, throttle_pressed: bool) -> void:
	var has_intent := _check_drift_intent(car_state, throttle_pressed)

	# Update confidence timer
	if has_intent:
		drift_confidence += delta
	else:
		drift_confidence -= delta

	drift_confidence = clampf(drift_confidence, 0.0, drift_exit_time)

	# State transitions
	match current_state:
		State.GRIP:
			if drift_confidence >= drift_enter_time:
				_enter_drift()
		State.DRIFT:
			if drift_confidence <= 0.0:
				_exit_drift()


## Check if conditions for drift intent are met
func _check_drift_intent(car_state: CarState, throttle_pressed: bool) -> bool:
	if car_state.speed < min_speed:
		return false

	if absf(car_state.slip_angle_deg) < min_slip_angle:
		return false

	if car_state.lateral_speed < min_lateral_speed:
		return false

	if not throttle_pressed:
		return false

	return true


func _enter_drift() -> void:
	current_state = State.DRIFT
	rear_grip_multiplier = drift_grip_multiplier
	drift_started.emit()


func _exit_drift() -> void:
	current_state = State.GRIP
	rear_grip_multiplier = 1.0
	drift_ended.emit()


## Check if currently drifting
func is_drifting() -> bool:
	return current_state == State.DRIFT


## Get current grip multiplier for rear wheels
func get_rear_grip_multiplier() -> float:
	return rear_grip_multiplier


## Get normalized drift confidence (0-1)
func get_drift_confidence() -> float:
	return drift_confidence / drift_exit_time


## Force exit drift state (e.g., on collision)
func force_exit() -> void:
	if current_state == State.DRIFT:
		_exit_drift()
	drift_confidence = 0.0
