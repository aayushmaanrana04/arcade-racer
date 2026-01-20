class_name Powertrain
extends RefCounted
## Engine and transmission simulation.
## Computes requested torque from throttle intent.
## NEVER applies forces - only calculates values.

# ─────────────────────────────────────────────
# ENGINE CONFIG (Tier 1 - Tunable)
# ─────────────────────────────────────────────
var base_engine_torque: float = 400.0
var engine_response: float = 25.0  # Faster RPM response
var idle_rpm: float = 1000.0
var redline_rpm: float = 7000.0
var peak_torque_rpm: float = 4500.0

# Arcade mode - direct torque without gear multiplication
var arcade_mode: bool = true

# ─────────────────────────────────────────────
# TRANSMISSION CONFIG
# ─────────────────────────────────────────────
var gear_ratios: Array[float] = [3.2, 2.1, 1.6, 1.3, 1.0, 0.85]
var final_drive: float = 3.5
var reverse_ratio: float = -3.0

# ─────────────────────────────────────────────
# DERIVED STATE (Read-Only)
# ─────────────────────────────────────────────
var current_rpm: float = 1000.0
var current_gear: int = 1  # 0 = reverse, 1-6 = forward gears
var is_revving: bool = false


## Compute requested torque from throttle (0-1)
func compute_requested_torque(throttle: float, speed: float = 0.0) -> float:
	if arcade_mode:
		# Arcade: torque boost at low speeds (simulates lower gear)
		# At 0 speed: 2x torque, at 100 km/h+: 1x torque
		var speed_kmh := speed * 3.6
		var low_speed_boost := lerpf(2.0, 1.0, clampf(speed_kmh / 80.0, 0.0, 1.0))
		return base_engine_torque * throttle * low_speed_boost
	else:
		# Sim: full gear/RPM calculation
		var rpm_factor := _torque_curve(current_rpm)
		var gear_ratio := _get_current_gear_ratio()
		return base_engine_torque * throttle * rpm_factor * gear_ratio * final_drive


## Update RPM based on target (from wheel speed feedback)
func update_rpm(delta: float, wheel_rpm: float, throttle: float) -> void:
	# Throttle wants to push RPM up, load (wheel connection) pulls it down
	var throttle_rpm := idle_rpm + (redline_rpm - idle_rpm) * throttle

	# Blend between throttle desire and wheel-driven RPM
	# More throttle = more free revving, less wheel influence
	var load_factor := clampf(1.0 - throttle * 0.6, 0.3, 1.0)
	var target_rpm := lerpf(throttle_rpm, wheel_rpm, load_factor)

	# Clamp to valid range
	target_rpm = clampf(target_rpm, idle_rpm, redline_rpm)

	# RPM rises fast on throttle, falls slower (engine inertia)
	var rise_rate := 8.0   # How fast RPM climbs
	var fall_rate := 4.0   # How fast RPM drops
	var rate := rise_rate if target_rpm > current_rpm else fall_rate

	current_rpm = move_toward(current_rpm, target_rpm, rate * 1000.0 * delta)

	# Idle settling
	if throttle < 0.1 and current_rpm < idle_rpm * 1.5:
		current_rpm = move_toward(current_rpm, idle_rpm, 2000.0 * delta)

	is_revving = current_rpm > redline_rpm * 0.9


## Normalized torque curve (0-1 based on RPM)
func _torque_curve(rpm: float) -> float:
	# Simple curve: peaks at peak_torque_rpm, falls off at extremes
	var normalized := rpm / redline_rpm
	# Bell curve centered around peak torque point
	var peak_point := peak_torque_rpm / redline_rpm
	var falloff := 1.0 - absf(normalized - peak_point) * 1.5
	return clampf(falloff, 0.3, 1.0)


func _get_current_gear_ratio() -> float:
	if current_gear == 0:
		return reverse_ratio
	var idx := clampi(current_gear - 1, 0, gear_ratios.size() - 1)
	return gear_ratios[idx]


## Auto-shift logic (simple RPM-based)
func auto_shift() -> void:
	if current_gear == 0:
		return  # Don't auto-shift in reverse

	# Upshift near redline
	if current_rpm > redline_rpm * 0.9 and current_gear < gear_ratios.size():
		current_gear += 1
	# Downshift when RPM drops too low
	elif current_rpm < idle_rpm * 2.0 and current_gear > 1:
		current_gear -= 1


## Estimate wheel RPM from vehicle speed
func estimate_wheel_rpm(wheel_radius: float, speed: float) -> float:
	if wheel_radius <= 0.0:
		return idle_rpm
	# Convert speed to wheel angular velocity, then to engine RPM via gear ratios
	var wheel_angular := speed / wheel_radius
	var wheel_rpm := wheel_angular * 60.0 / TAU
	var gear_ratio := _get_current_gear_ratio()
	if absf(gear_ratio) < 0.01:
		return idle_rpm
	return absf(wheel_rpm * gear_ratio * final_drive)


## Manual gear control
func shift_up() -> void:
	if current_gear < gear_ratios.size():
		current_gear += 1


func shift_down() -> void:
	if current_gear > 0:
		current_gear -= 1


func set_reverse() -> void:
	current_gear = 0


func set_neutral() -> void:
	current_gear = 1
