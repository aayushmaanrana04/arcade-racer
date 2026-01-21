class_name ProceduralEngineAudio
extends Node3D
## Procedural engine audio synthesizer - NO AUDIO FILES REQUIRED.
##
## Generates engine sound in real-time using additive synthesis:
## - Base frequency derived from RPM
## - Multiple harmonics for richness
## - Amplitude modulation for "pulse" feel
## - Noise layer for texture
##
## The sound is generated sample-by-sample, giving complete control
## over every aspect of the engine character.

# ─────────────────────────────────────────────
# INPUT PARAMETERS (Set by gameplay code)
# ─────────────────────────────────────────────
var engine_rpm: float = 1000.0
var max_rpm: float = 7000.0
var throttle: float = 0.0
var is_redlining: bool = false

# ─────────────────────────────────────────────
# ENGINE CHARACTER
# ─────────────────────────────────────────────
@export_group("Engine Character")
## Number of cylinders (affects firing frequency)
@export_enum("4 Cylinder", "6 Cylinder", "8 Cylinder") var cylinder_config: int = 1
## Base volume in dB
@export var base_volume_db: float = -6.0
## How "aggressive" the engine sounds (harmonic content)
@export_range(0.0, 1.0) var aggression: float = 0.6

# ─────────────────────────────────────────────
# FREQUENCY TUNING
# ─────────────────────────────────────────────
@export_group("Frequency")
## Base frequency multiplier (higher = higher pitched engine)
@export var frequency_multiplier: float = 1.0
## Minimum frequency at idle (Hz)
@export var min_frequency: float = 35.0
## Maximum frequency at redline (Hz)
@export var max_frequency: float = 180.0

# ─────────────────────────────────────────────
# HARMONICS
# ─────────────────────────────────────────────
@export_group("Harmonics")
## Strength of 2nd harmonic (octave)
@export_range(0.0, 1.0) var harmonic_2: float = 0.5
## Strength of 3rd harmonic
@export_range(0.0, 1.0) var harmonic_3: float = 0.3
## Strength of 4th harmonic
@export_range(0.0, 1.0) var harmonic_4: float = 0.2
## Strength of 5th harmonic
@export_range(0.0, 1.0) var harmonic_5: float = 0.1

# ─────────────────────────────────────────────
# NOISE & TEXTURE
# ─────────────────────────────────────────────
@export_group("Texture")
## Amount of noise mixed in (exhaust rumble)
@export_range(0.0, 1.0) var noise_amount: float = 0.15
## Roughness of the engine (random pitch variation)
@export_range(0.0, 0.1) var roughness: float = 0.02

# ─────────────────────────────────────────────
# AUDIO COMPONENTS
# ─────────────────────────────────────────────
var _player: AudioStreamPlayer3D
var _generator: AudioStreamGenerator
var _playback: AudioStreamGeneratorPlayback

# ─────────────────────────────────────────────
# SYNTHESIS STATE
# ─────────────────────────────────────────────
var _phase: float = 0.0
var _phase_2: float = 0.0
var _phase_3: float = 0.0
var _phase_4: float = 0.0
var _phase_5: float = 0.0
var _noise_phase: float = 0.0
var _pulse_phase: float = 0.0

var _sample_rate: float = 44100.0
var _smooth_rpm: float = 1000.0
var _smooth_throttle: float = 0.0
var _current_frequency: float = 35.0

# Limiter state
var _limiter_phase: float = 0.0
var _limiter_active: bool = false

# Random for noise generation
var _rng: RandomNumberGenerator


func _ready() -> void:
	_rng = RandomNumberGenerator.new()
	_rng.randomize()

	_setup_audio()


func _process(delta: float) -> void:
	# Smooth inputs
	_smooth_rpm = lerpf(_smooth_rpm, engine_rpm, 12.0 * delta)
	_smooth_throttle = lerpf(_smooth_throttle, throttle, 15.0 * delta)

	# Calculate target frequency from RPM
	var rpm_norm := clampf(_smooth_rpm / max_rpm, 0.0, 1.2)
	_current_frequency = lerpf(min_frequency, max_frequency, rpm_norm) * frequency_multiplier

	# Fill audio buffer
	_fill_buffer()


func _setup_audio() -> void:
	# Create AudioStreamPlayer3D
	_player = AudioStreamPlayer3D.new()
	add_child(_player)

	# Create generator stream
	_generator = AudioStreamGenerator.new()
	_generator.mix_rate = _sample_rate
	_generator.buffer_length = 0.1  # 100ms buffer

	_player.stream = _generator
	_player.volume_db = base_volume_db
	_player.play()

	# Get playback interface
	_playback = _player.get_stream_playback() as AudioStreamGeneratorPlayback


func _fill_buffer() -> void:
	if _playback == null:
		return

	# Calculate how many frames we can push
	var frames_available := _playback.get_frames_available()
	if frames_available == 0:
		return

	# Get cylinder count for pulse frequency
	var cylinders := _get_cylinder_count()

	# Calculate pulse frequency (firing rate)
	# For a 4-stroke engine: (RPM / 60) * (cylinders / 2) = fires per second
	var fires_per_second := (_smooth_rpm / 60.0) * (cylinders / 2.0)
	var pulse_freq := fires_per_second

	# Throttle affects volume and harmonic content
	var volume := lerpf(0.3, 1.0, _smooth_throttle)
	var harmonic_boost := lerpf(0.5, 1.0, _smooth_throttle)

	# Generate samples
	for i in range(frames_available):
		var sample := _generate_sample(pulse_freq, volume, harmonic_boost)

		# Apply redline limiter
		if is_redlining:
			sample *= _apply_limiter()

		# Push stereo frame (same for both channels)
		_playback.push_frame(Vector2(sample, sample))


func _generate_sample(pulse_freq: float, volume: float, harmonic_boost: float) -> float:
	var dt := 1.0 / _sample_rate
	var sample := 0.0

	# Add roughness (slight random frequency variation)
	var freq_jitter := 1.0 + (_rng.randf() - 0.5) * roughness
	var freq := _current_frequency * freq_jitter

	# ─────────────────────────────────────────
	# FUNDAMENTAL + HARMONICS (Additive synthesis)
	# ─────────────────────────────────────────

	# Fundamental
	_phase += freq * dt
	if _phase > 1.0:
		_phase -= 1.0
	sample += _oscillator(_phase) * 1.0

	# 2nd Harmonic (octave)
	_phase_2 += freq * 2.0 * dt
	if _phase_2 > 1.0:
		_phase_2 -= 1.0
	sample += _oscillator(_phase_2) * harmonic_2 * harmonic_boost

	# 3rd Harmonic
	_phase_3 += freq * 3.0 * dt
	if _phase_3 > 1.0:
		_phase_3 -= 1.0
	sample += _oscillator(_phase_3) * harmonic_3 * harmonic_boost

	# 4th Harmonic
	_phase_4 += freq * 4.0 * dt
	if _phase_4 > 1.0:
		_phase_4 -= 1.0
	sample += _oscillator(_phase_4) * harmonic_4 * harmonic_boost

	# 5th Harmonic
	_phase_5 += freq * 5.0 * dt
	if _phase_5 > 1.0:
		_phase_5 -= 1.0
	sample += _oscillator(_phase_5) * harmonic_5 * harmonic_boost

	# ─────────────────────────────────────────
	# PULSE MODULATION (Engine firing)
	# ─────────────────────────────────────────
	_pulse_phase += pulse_freq * dt
	if _pulse_phase > 1.0:
		_pulse_phase -= 1.0

	# Pulse envelope - creates the "chug" feel
	var pulse := 0.5 + 0.5 * sin(_pulse_phase * TAU)
	pulse = lerpf(1.0, pulse, aggression * 0.6)
	sample *= pulse

	# ─────────────────────────────────────────
	# NOISE LAYER (Exhaust texture)
	# ─────────────────────────────────────────
	if noise_amount > 0.0:
		var noise := (_rng.randf() * 2.0 - 1.0)
		# Filter the noise to make it more "rumbly"
		_noise_phase = _noise_phase * 0.95 + noise * 0.05
		sample += _noise_phase * noise_amount * volume

	# ─────────────────────────────────────────
	# FINAL MIX
	# ─────────────────────────────────────────

	# Normalize (we have multiple oscillators)
	sample /= (1.0 + harmonic_2 + harmonic_3 + harmonic_4 + harmonic_5)

	# Apply volume
	sample *= volume

	# Soft clip to prevent harsh distortion
	sample = _soft_clip(sample)

	return sample


## Basic oscillator - mix of sine and shaped wave for character
func _oscillator(phase: float) -> float:
	# Sine wave base
	var sine := sin(phase * TAU)

	# Add some "edge" with a shaped component
	var shaped: float = signf(sine) * pow(absf(sine), 0.7)

	# Mix based on aggression
	return lerpf(sine, shaped, aggression * 0.5)


## Soft clipper to prevent harsh distortion
func _soft_clip(x: float) -> float:
	# Attempt tanh saturation for warm limiting
	if x > 1.0:
		return 1.0 - exp(-x + 1.0) * 0.5
	elif x < -1.0:
		return -1.0 + exp(x + 1.0) * 0.5
	return x


## Redline limiter effect
func _apply_limiter() -> float:
	_limiter_phase += 20.0 / _sample_rate  # 20 Hz limiter
	if _limiter_phase > 1.0:
		_limiter_phase -= 1.0

	# Harsh cut pattern
	if _limiter_phase < 0.3:
		return 0.3  # Cut
	return 1.0  # Pass


func _get_cylinder_count() -> int:
	match cylinder_config:
		0: return 4
		1: return 6
		2: return 8
	return 6


# ─────────────────────────────────────────────
# PUBLIC API
# ─────────────────────────────────────────────

## Update all parameters at once
func set_engine_state(rpm: float, max_rpm_val: float, throttle_val: float, redlining: bool) -> void:
	engine_rpm = rpm
	max_rpm = max_rpm_val
	throttle = throttle_val
	is_redlining = redlining


## Set engine character preset
func set_preset_sporty() -> void:
	cylinder_config = 1  # 6 cylinder
	aggression = 0.7
	harmonic_2 = 0.6
	harmonic_3 = 0.4
	harmonic_4 = 0.25
	harmonic_5 = 0.15
	noise_amount = 0.12


func set_preset_muscle() -> void:
	cylinder_config = 2  # 8 cylinder
	aggression = 0.8
	harmonic_2 = 0.7
	harmonic_3 = 0.5
	harmonic_4 = 0.3
	harmonic_5 = 0.2
	noise_amount = 0.2


func set_preset_tuner() -> void:
	cylinder_config = 0  # 4 cylinder
	aggression = 0.6
	harmonic_2 = 0.5
	harmonic_3 = 0.35
	harmonic_4 = 0.2
	harmonic_5 = 0.1
	noise_amount = 0.1
	frequency_multiplier = 1.2  # Higher pitched
