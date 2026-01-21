class_name EngineAudioController
extends Node3D
## Continuous, parameter-driven engine audio system.
##
## DESIGN PHILOSOPHY:
## - Audio is ALWAYS playing (started once in _ready, never stopped)
## - No state machines, no stream switching
## - All changes happen through continuous parameter interpolation
## - This eliminates pops, clicks, and state-flicker artifacts
##
## HOW IT WORKS:
## 1. Three audio layers (low/mid/high) play continuously
## 2. RPM determines crossfade weights between layers
## 3. RPM determines pitch (with arcade exaggeration curve)
## 4. Throttle modulates volume and "intensity"
## 5. Redline creates audible limiter stutter
##
## EXTENSION POINTS:
## - Add turbo whoosh layer
## - Add drift stress (higher pitch under slip)
## - Add damage (misfire, roughness)
## - Add exhaust pops on throttle lift

# ─────────────────────────────────────────────
# INPUT PARAMETERS (Set every frame by gameplay)
# ─────────────────────────────────────────────
var engine_rpm: float = 1000.0
var max_rpm: float = 7000.0
var throttle: float = 0.0          # 0.0 - 1.0
var is_redlining: bool = false

# ─────────────────────────────────────────────
# TUNING - PITCH
# ─────────────────────────────────────────────
## Base pitch at idle RPM (prevents unnaturally slow playback)
@export var idle_pitch: float = 0.6
## Maximum pitch at redline
@export var max_pitch: float = 2.2
## Pitch curve exponent (>1 = aggressive high-end, <1 = aggressive low-end)
@export var pitch_curve_exponent: float = 1.4

# ─────────────────────────────────────────────
# TUNING - VOLUME
# ─────────────────────────────────────────────
## Minimum volume (engine never fully silent)
@export var min_volume_db: float = -20.0
## Maximum volume at full throttle + high RPM
@export var max_volume_db: float = 3.0
## How much throttle affects volume (0 = none, 1 = full)
@export var throttle_volume_influence: float = 0.4

# ─────────────────────────────────────────────
# TUNING - CROSSFADE RANGES (normalized RPM)
# ─────────────────────────────────────────────
## Low layer: full at 0, fades out by this point
@export var low_fade_end: float = 0.45
## Mid layer: fades in starting here
@export var mid_fade_start: float = 0.25
## Mid layer: fades out by this point
@export var mid_fade_end: float = 0.8
## High layer: fades in starting here
@export var high_fade_start: float = 0.6

# ─────────────────────────────────────────────
# TUNING - REDLINE LIMITER
# ─────────────────────────────────────────────
## How often limiter "cuts" per second when redlining
@export var limiter_frequency: float = 20.0
## Volume reduction during limiter cut (dB)
@export var limiter_cut_db: float = -12.0

# ─────────────────────────────────────────────
# AUDIO NODES (Assigned in _ready or via export)
# ─────────────────────────────────────────────
@onready var engine_low: AudioStreamPlayer3D = $EngineLow
@onready var engine_mid: AudioStreamPlayer3D = $EngineMid
@onready var engine_high: AudioStreamPlayer3D = $EngineHigh

# ─────────────────────────────────────────────
# INTERNAL STATE
# ─────────────────────────────────────────────
var _limiter_phase: float = 0.0
var _smooth_rpm: float = 1000.0
var _smooth_throttle: float = 0.0

# Smoothing rates (higher = faster response)
const RPM_SMOOTHING: float = 12.0
const THROTTLE_SMOOTHING: float = 15.0


func _ready() -> void:
	# Start all audio loops immediately - they will NEVER be stopped
	_start_all_loops()


func _process(delta: float) -> void:
	# Smooth input parameters to prevent audio jitter
	_smooth_rpm = lerpf(_smooth_rpm, engine_rpm, RPM_SMOOTHING * delta)
	_smooth_throttle = lerpf(_smooth_throttle, throttle, THROTTLE_SMOOTHING * delta)

	# Calculate normalized RPM (allow slight overshoot for redline effect)
	var rpm_norm := clampf(_smooth_rpm / max_rpm, 0.0, 1.2)

	# Update audio parameters
	_update_pitch(rpm_norm)
	_update_crossfade(rpm_norm)
	_update_volume(rpm_norm, delta)


## Start all audio loops once. They play forever.
func _start_all_loops() -> void:
	if engine_low and not engine_low.playing:
		engine_low.play()
	if engine_mid and not engine_mid.playing:
		engine_mid.play()
	if engine_high and not engine_high.playing:
		engine_high.play()


## Calculate pitch from RPM with arcade-biased curve.
##
## The curve uses an exponent to create non-linear response:
## - exponent > 1: slower rise at low RPM, aggressive at high RPM
## - This feels more "alive" than linear mapping
func _update_pitch(rpm_norm: float) -> void:
	# Apply non-linear curve for arcade feel
	# pow() with exponent > 1 makes high RPM feel more dramatic
	var curved_rpm := pow(clampf(rpm_norm, 0.0, 1.0), pitch_curve_exponent)

	# Map to pitch range
	var target_pitch := lerpf(idle_pitch, max_pitch, curved_rpm)

	# Apply same pitch to all layers (they're harmonically related)
	if engine_low:
		engine_low.pitch_scale = target_pitch
	if engine_mid:
		engine_mid.pitch_scale = target_pitch
	if engine_high:
		engine_high.pitch_scale = target_pitch


## Crossfade between low/mid/high layers based on RPM.
##
## Each layer has a fade-in and fade-out region.
## Overlapping regions create smooth blends.
func _update_crossfade(rpm_norm: float) -> void:
	# LOW: Full at 0, fades out toward low_fade_end
	var low_weight := 1.0 - smoothstep(0.0, low_fade_end, rpm_norm)

	# MID: Fades in from mid_fade_start, fades out toward mid_fade_end
	var mid_in := smoothstep(mid_fade_start, mid_fade_start + 0.15, rpm_norm)
	var mid_out := 1.0 - smoothstep(mid_fade_end - 0.1, mid_fade_end, rpm_norm)
	var mid_weight := mid_in * mid_out

	# HIGH: Fades in from high_fade_start, stays full above
	var high_weight := smoothstep(high_fade_start, high_fade_start + 0.2, rpm_norm)

	# Apply weights as volume multipliers (convert to dB offset)
	_set_layer_weight(engine_low, low_weight)
	_set_layer_weight(engine_mid, mid_weight)
	_set_layer_weight(engine_high, high_weight)


## Apply crossfade weight to a layer.
## Weight 0 = silent, Weight 1 = full volume (before master volume applied)
func _set_layer_weight(player: AudioStreamPlayer3D, weight: float) -> void:
	if player == null:
		return

	# Convert weight to dB (avoid log(0) by clamping)
	var weight_db: float
	if weight < 0.01:
		weight_db = -80.0  # Effectively silent
	else:
		weight_db = linear_to_db(weight)

	player.volume_db = weight_db


## Update master volume based on throttle and RPM.
## Also applies redline limiter effect.
func _update_volume(rpm_norm: float, delta: float) -> void:
	# Base volume from RPM (engine is louder at high RPM)
	var rpm_volume := lerpf(0.5, 1.0, rpm_norm)

	# Throttle contribution (even zero throttle has some volume)
	var throttle_factor := lerpf(1.0 - throttle_volume_influence, 1.0, _smooth_throttle)

	# Combined volume (0-1 range)
	var volume := rpm_volume * throttle_factor

	# Apply redline limiter effect
	if is_redlining:
		volume *= _calculate_limiter_effect(delta)

	# Convert to dB and apply to all layers as offset
	var volume_db := lerpf(min_volume_db, max_volume_db, volume)

	# Apply as unit_size for 3D falloff, or direct volume adjustment
	# Here we adjust the base volume that crossfade builds upon
	_apply_master_volume(volume_db)


## Calculate limiter stutter effect.
## Returns a multiplier (0.3 - 1.0) that creates audible "cuts"
func _calculate_limiter_effect(delta: float) -> float:
	_limiter_phase += delta * limiter_frequency
	if _limiter_phase > 1.0:
		_limiter_phase -= 1.0

	# Square wave-ish pattern: cuts briefly, recovers
	# Using sine for slightly softer cuts
	var cut := sin(_limiter_phase * TAU)

	# Only cut on positive half of wave
	if cut > 0.3:
		return db_to_linear(limiter_cut_db)
	return 1.0


## Apply master volume to all layers.
## This is added on top of crossfade weights.
func _apply_master_volume(volume_db: float) -> void:
	# Store base volume for external queries if needed
	# The actual layer volumes are set in crossfade, this modulates them
	# For simplicity, we adjust unit_size for 3D attenuation feel
	var unit_size := remap(volume_db, min_volume_db, max_volume_db, 5.0, 15.0)

	if engine_low:
		engine_low.unit_size = unit_size
	if engine_mid:
		engine_mid.unit_size = unit_size
	if engine_high:
		engine_high.unit_size = unit_size


## Attempt to use smoothstep for nice S-curve interpolation.
## Built-in smoothstep clamps, this version allows over/undershoot check.
func smoothstep(edge0: float, edge1: float, x: float) -> float:
	var t := clampf((x - edge0) / (edge1 - edge0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


# ─────────────────────────────────────────────
# PUBLIC API (Called by gameplay code)
# ─────────────────────────────────────────────

## Update all parameters at once (convenience method)
func set_engine_state(rpm: float, max_rpm_val: float, throttle_val: float, redlining: bool) -> void:
	engine_rpm = rpm
	max_rpm = max_rpm_val
	throttle = throttle_val
	is_redlining = redlining


## Get current smoothed RPM (useful for UI sync)
func get_smooth_rpm() -> float:
	return _smooth_rpm
