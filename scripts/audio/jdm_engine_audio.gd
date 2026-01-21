class_name JDMEngineAudio
extends Node3D
## Comprehensive JDM engine audio synthesizer.
##
## Acoustically accurate synthesis based on:
## - Combustion harmonics (firing order, cylinder count)
## - Turbo system (spool, blow-off, flutter)
## - Intake induction noise
## - Exhaust character (pops, crackle, burble)
##
## Each component is synthesized separately and mixed for full control.

# ─────────────────────────────────────────────
# INPUT PARAMETERS (Set by gameplay code)
# ─────────────────────────────────────────────
var engine_rpm: float = 1000.0
var max_rpm: float = 8000.0
var throttle: float = 0.0
var is_redlining: bool = false
var boost_psi: float = 0.0           ## Turbo boost pressure (0 = no boost)
var throttle_just_lifted: bool = false  ## For blow-off trigger

# ─────────────────────────────────────────────
# ENGINE CHARACTER
# ─────────────────────────────────────────────
@export_group("Engine Type")
@export_enum("Inline 4", "Inline 6", "V6", "V8", "Boxer 4", "Rotary 2-Rotor") var engine_type: int = 0
@export var has_turbo: bool = true
@export var has_vtec: bool = false
@export var vtec_engagement_rpm: float = 5500.0

@export_group("Volume")
@export var master_volume_db: float = -6.0
@export_range(0.0, 1.0) var exhaust_mix: float = 0.7    ## Exhaust vs engine
@export_range(0.0, 1.0) var intake_mix: float = 0.3     ## Intake induction

@export_group("Character")
@export_range(0.0, 1.0) var aggression: float = 0.6     ## Harmonic richness
@export_range(0.0, 1.0) var roughness: float = 0.02     ## Random variations
@export_range(0.0, 1.0) var exhaust_crackle: float = 0.5 ## Overrun pops

@export_group("Turbo")
@export var max_boost_psi: float = 18.0
@export_range(0.0, 1.0) var turbo_volume: float = 0.4
@export_range(0.0, 1.0) var bov_volume: float = 0.6
@export var has_flutter: bool = false  ## No BOV = flutter instead

# ─────────────────────────────────────────────
# FREQUENCY TUNING
# ─────────────────────────────────────────────
@export_group("Frequency")
## Base frequency at idle
@export var idle_frequency: float = 28.0
## Frequency at redline
@export var redline_frequency: float = 140.0
## Turbo whine base frequency (Hz)
@export var turbo_base_freq: float = 2000.0
## Turbo whine max frequency (Hz)
@export var turbo_max_freq: float = 8000.0

# ─────────────────────────────────────────────
# AUDIO COMPONENTS
# ─────────────────────────────────────────────
var _player: AudioStreamPlayer3D
var _generator: AudioStreamGenerator
var _playback: AudioStreamGeneratorPlayback

const SAMPLE_RATE: float = 44100.0
const BUFFER_LENGTH: float = 0.1

# ─────────────────────────────────────────────
# SYNTHESIS STATE
# ─────────────────────────────────────────────
# Combustion oscillators (up to 8 harmonics)
var _phases: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]

# Turbo state
var _turbo_phase: float = 0.0
var _turbo_spool: float = 0.0  # 0-1 spool amount (has inertia)
var _bov_active: bool = false
var _bov_timer: float = 0.0
var _bov_phase: float = 0.0
var _flutter_phase: float = 0.0

# Intake state
var _intake_noise_state: float = 0.0

# Exhaust state
var _crackle_timer: float = 0.0
var _crackle_active: bool = false
var _crackle_freq: float = 800.0
var _crackle_phase: float = 0.0

# Boxer rumble state
var _boxer_pulse_phase: float = 0.0

# Smoothed inputs
var _smooth_rpm: float = 1000.0
var _smooth_throttle: float = 0.0
var _prev_throttle: float = 0.0

# Limiter
var _limiter_phase: float = 0.0

# RNG
var _rng: RandomNumberGenerator


func _ready() -> void:
	_rng = RandomNumberGenerator.new()
	_rng.randomize()
	_setup_audio()


func _process(delta: float) -> void:
	# Detect throttle lift for BOV
	if _prev_throttle > 0.7 and throttle < 0.3 and has_turbo and _turbo_spool > 0.5:
		_trigger_bov()
	_prev_throttle = throttle

	# Smooth inputs
	_smooth_rpm = lerpf(_smooth_rpm, engine_rpm, 12.0 * delta)
	_smooth_throttle = lerpf(_smooth_throttle, throttle, 15.0 * delta)

	# Update turbo spool (has inertia)
	var target_spool := 0.0
	if has_turbo and _smooth_throttle > 0.3:
		target_spool = clampf((_smooth_rpm - 2500.0) / 4000.0, 0.0, 1.0) * _smooth_throttle
	_turbo_spool = lerpf(_turbo_spool, target_spool, 3.0 * delta)  # Slow spool
	if throttle < 0.2:
		_turbo_spool = lerpf(_turbo_spool, 0.0, 8.0 * delta)  # Faster despool

	# Update BOV timer
	if _bov_active:
		_bov_timer -= delta
		if _bov_timer <= 0.0:
			_bov_active = false

	# Random crackle on deceleration
	if throttle < 0.1 and _smooth_rpm > 2500.0 and exhaust_crackle > 0.0:
		_crackle_timer -= delta
		if _crackle_timer <= 0.0 and _rng.randf() < 0.15:
			_trigger_crackle()
			_crackle_timer = _rng.randf_range(0.05, 0.2)

	# Fill audio buffer
	_fill_buffer()


func _setup_audio() -> void:
	_player = AudioStreamPlayer3D.new()
	add_child(_player)

	_generator = AudioStreamGenerator.new()
	_generator.mix_rate = SAMPLE_RATE
	_generator.buffer_length = BUFFER_LENGTH

	_player.stream = _generator
	_player.volume_db = master_volume_db
	_player.play()

	_playback = _player.get_stream_playback() as AudioStreamGeneratorPlayback


func _fill_buffer() -> void:
	if _playback == null:
		return

	var frames_available := _playback.get_frames_available()
	if frames_available == 0:
		return

	var dt := 1.0 / SAMPLE_RATE
	var rpm_norm := clampf(_smooth_rpm / max_rpm, 0.0, 1.2)

	# Calculate base firing frequency
	var base_freq := lerpf(idle_frequency, redline_frequency, rpm_norm)

	# Get harmonic weights for this engine type
	var harmonics := _get_harmonic_weights()

	for i in range(frames_available):
		var sample := 0.0

		# ─────────────────────────────────────────
		# COMBUSTION HARMONICS
		# ─────────────────────────────────────────
		sample += _generate_combustion(base_freq, harmonics, dt)

		# ─────────────────────────────────────────
		# BOXER RUMBLE (if applicable)
		# ─────────────────────────────────────────
		if engine_type == 4:  # Boxer 4
			sample = _apply_boxer_modulation(sample, base_freq, dt)

		# ─────────────────────────────────────────
		# ROTARY CHARACTER (if applicable)
		# ─────────────────────────────────────────
		if engine_type == 5:  # Rotary
			sample = _generate_rotary(base_freq, dt)

		# ─────────────────────────────────────────
		# VTEC CROSSOVER
		# ─────────────────────────────────────────
		if has_vtec:
			sample = _apply_vtec(sample, rpm_norm)

		# ─────────────────────────────────────────
		# INTAKE INDUCTION
		# ─────────────────────────────────────────
		sample += _generate_intake(dt) * intake_mix

		# ─────────────────────────────────────────
		# TURBO SOUNDS
		# ─────────────────────────────────────────
		if has_turbo:
			sample += _generate_turbo(dt)

		# ─────────────────────────────────────────
		# EXHAUST CRACKLE
		# ─────────────────────────────────────────
		sample += _generate_crackle(dt)

		# ─────────────────────────────────────────
		# REDLINE LIMITER
		# ─────────────────────────────────────────
		if is_redlining:
			sample *= _apply_limiter(dt)

		# ─────────────────────────────────────────
		# FINAL PROCESSING
		# ─────────────────────────────────────────

		# Volume based on throttle and RPM
		var volume := lerpf(0.3, 1.0, _smooth_throttle) * lerpf(0.6, 1.0, rpm_norm)
		sample *= volume

		# Soft clip
		sample = _soft_clip(sample)

		_playback.push_frame(Vector2(sample, sample))


# ─────────────────────────────────────────────
# COMBUSTION SYNTHESIS
# ─────────────────────────────────────────────

func _get_harmonic_weights() -> Array[float]:
	## Returns harmonic weights based on engine type
	## Index 0 = fundamental, 1 = 2nd harmonic, etc.

	match engine_type:
		0:  # Inline 4 - strong 2nd and 4th orders
			return [1.0, 0.6, 0.3, 0.5, 0.2, 0.15, 0.1, 0.05]
		1:  # Inline 6 - smoother, strong 3rd and 6th
			return [1.0, 0.4, 0.6, 0.25, 0.15, 0.4, 0.1, 0.05]
		2:  # V6 - similar to I6 but with more rumble
			return [1.0, 0.5, 0.7, 0.3, 0.2, 0.5, 0.15, 0.08]
		3:  # V8 - strong 4th and 8th, classic muscle
			return [1.0, 0.3, 0.2, 0.7, 0.15, 0.1, 0.08, 0.4]
		4:  # Boxer 4 - handled separately with pulse modulation
			return [1.0, 0.5, 0.25, 0.4, 0.15, 0.1, 0.08, 0.05]
		5:  # Rotary - very different, handled separately
			return [1.0, 0.3, 0.2, 0.15, 0.1, 0.08, 0.05, 0.03]
		_:
			return [1.0, 0.5, 0.3, 0.2, 0.15, 0.1, 0.08, 0.05]


func _generate_combustion(base_freq: float, harmonics: Array[float], dt: float) -> float:
	var sample := 0.0
	var total_weight := 0.0

	# Add micro-modulation for realism
	var freq_jitter := 1.0 + (_rng.randf() - 0.5) * roughness

	for h in range(harmonics.size()):
		var freq := base_freq * (h + 1) * freq_jitter
		var weight: float = harmonics[h]

		# Throttle increases higher harmonics (more aggressive)
		if h > 1:
			weight *= lerpf(0.5, 1.0, _smooth_throttle * aggression)

		# Update phase
		_phases[h] += freq * dt
		if _phases[h] > 1.0:
			_phases[h] -= 1.0

		# Generate shaped waveform (not pure sine)
		var wave := _shaped_oscillator(_phases[h], aggression)
		sample += wave * weight
		total_weight += weight

	# Normalize
	if total_weight > 0.0:
		sample /= total_weight

	return sample * exhaust_mix


func _shaped_oscillator(phase: float, shape: float) -> float:
	## Creates a waveform between sine and more "edgy" sound
	var sine := sin(phase * TAU)

	# Add edge by power-shaping
	var shaped: float = signf(sine) * pow(absf(sine), lerpf(1.0, 0.6, shape))

	return lerpf(sine, shaped, shape * 0.7)


# ─────────────────────────────────────────────
# BOXER ENGINE MODULATION
# ─────────────────────────────────────────────

func _apply_boxer_modulation(sample: float, base_freq: float, dt: float) -> float:
	## Boxer engines have unequal exhaust pulse timing
	## This creates the distinctive "rumble" - pairs of pulses then gap

	# Pulse at twice the base frequency (simulating unequal headers)
	_boxer_pulse_phase += base_freq * 2.0 * dt
	if _boxer_pulse_phase > 1.0:
		_boxer_pulse_phase -= 1.0

	# Create asymmetric pulse pattern
	# Two quick pulses, then a longer gap
	var pulse_mod: float
	if _boxer_pulse_phase < 0.3:
		pulse_mod = 1.0  # First pulse
	elif _boxer_pulse_phase < 0.4:
		pulse_mod = 0.5  # Brief dip
	elif _boxer_pulse_phase < 0.7:
		pulse_mod = 0.9  # Second pulse
	else:
		pulse_mod = 0.4  # Longer gap (the "rumble" character)

	return sample * pulse_mod


# ─────────────────────────────────────────────
# ROTARY ENGINE
# ─────────────────────────────────────────────

func _generate_rotary(base_freq: float, dt: float) -> float:
	## Rotary engines have smooth, turbine-like sound
	## No discrete pops - continuous high-pitched whine

	var sample := 0.0

	# Higher base frequency for rotary (feels higher-pitched)
	var rotary_freq := base_freq * 1.5

	# Smooth sine-heavy tone with subtle harmonics
	for h in range(4):
		var freq := rotary_freq * (h + 1)
		var weight := 1.0 / pow(h + 1, 1.5)  # Rapid harmonic decay

		_phases[h] += freq * dt
		if _phases[h] > 1.0:
			_phases[h] -= 1.0

		# Pure sine for smoothness
		sample += sin(_phases[h] * TAU) * weight

	# Add characteristic high-frequency "whine"
	_phases[4] += rotary_freq * 6.0 * dt
	if _phases[4] > 1.0:
		_phases[4] -= 1.0
	sample += sin(_phases[4] * TAU) * 0.15 * _smooth_throttle

	return sample * 0.7


# ─────────────────────────────────────────────
# VTEC SIMULATION
# ─────────────────────────────────────────────

func _apply_vtec(sample: float, rpm_norm: float) -> float:
	## VTEC crossover boosts higher harmonics above engagement point

	var vtec_norm := vtec_engagement_rpm / max_rpm

	if rpm_norm > vtec_norm:
		# Above VTEC - boost high frequency content
		var vtec_intensity := clampf((rpm_norm - vtec_norm) / 0.1, 0.0, 1.0)

		# Add high-frequency "scream"
		var vtec_freq := lerpf(redline_frequency * 3.0, redline_frequency * 5.0, rpm_norm)
		_phases[6] += vtec_freq / SAMPLE_RATE
		if _phases[6] > 1.0:
			_phases[6] -= 1.0

		sample += sin(_phases[6] * TAU) * 0.2 * vtec_intensity * _smooth_throttle
		sample *= lerpf(1.0, 1.15, vtec_intensity)  # Slight volume boost

	return sample


# ─────────────────────────────────────────────
# INTAKE INDUCTION
# ─────────────────────────────────────────────

func _generate_intake(dt: float) -> float:
	## Intake noise - filtered broadband noise that rises with throttle

	var noise := _rng.randf() * 2.0 - 1.0

	# Low-pass filter the noise (simple one-pole)
	var cutoff := lerpf(0.02, 0.15, _smooth_throttle)
	_intake_noise_state = _intake_noise_state * (1.0 - cutoff) + noise * cutoff

	# Scale with throttle
	return _intake_noise_state * _smooth_throttle * 0.3


# ─────────────────────────────────────────────
# TURBO SOUNDS
# ─────────────────────────────────────────────

func _generate_turbo(dt: float) -> float:
	var sample := 0.0

	# ─── SPOOL WHINE ───
	if _turbo_spool > 0.05:
		var turbo_freq := lerpf(turbo_base_freq, turbo_max_freq, _turbo_spool)
		_turbo_phase += turbo_freq * dt
		if _turbo_phase > 1.0:
			_turbo_phase -= 1.0

		# Turbo whine is almost pure sine at high frequency
		var whine := sin(_turbo_phase * TAU)
		# Add slight harmonic for character
		whine += sin(_turbo_phase * TAU * 2.0) * 0.2

		sample += whine * _turbo_spool * turbo_volume * 0.15

	# ─── BLOW-OFF VALVE ───
	if _bov_active:
		sample += _generate_bov(dt)

	# ─── FLUTTER (if no BOV) ───
	if has_flutter and not _bov_active and _prev_throttle > throttle and _turbo_spool > 0.3:
		sample += _generate_flutter(dt)

	return sample


func _trigger_bov() -> void:
	if has_flutter:
		return  # Flutter instead of BOV
	_bov_active = true
	_bov_timer = 0.3  # 300ms blow-off sound
	_bov_phase = 0.0


func _generate_bov(dt: float) -> float:
	## Blow-off valve - "Pssshhh" sound
	## Filtered noise with falling pitch

	var progress := 1.0 - (_bov_timer / 0.3)  # 0 to 1 over duration

	# Noise burst
	var noise := _rng.randf() * 2.0 - 1.0

	# Falling pitch filter
	var cutoff := lerpf(0.8, 0.1, progress)
	_bov_phase = _bov_phase * (1.0 - cutoff) + noise * cutoff

	# Amplitude envelope - quick attack, slow decay
	var envelope := 1.0 - progress * progress

	return _bov_phase * envelope * bov_volume * 0.5


func _generate_flutter(dt: float) -> float:
	## Compressor surge - "stu-tu-tu" sound
	## Rapid amplitude modulation of turbo whine

	_flutter_phase += 30.0 * dt  # 30 Hz flutter rate
	if _flutter_phase > 1.0:
		_flutter_phase -= 1.0

	# Square-ish modulation
	var flutter_mod := 0.0 if _flutter_phase < 0.5 else 1.0

	# Apply to turbo whine
	var turbo_freq := turbo_base_freq * 1.5
	var whine := sin(_turbo_phase * TAU)

	return whine * flutter_mod * _turbo_spool * 0.3


# ─────────────────────────────────────────────
# EXHAUST CRACKLE
# ─────────────────────────────────────────────

func _trigger_crackle() -> void:
	_crackle_active = true
	_crackle_freq = _rng.randf_range(600.0, 1200.0)
	_crackle_phase = 0.0


func _generate_crackle(dt: float) -> float:
	if not _crackle_active:
		return 0.0

	_crackle_phase += _crackle_freq * dt

	# Very short burst (20-50ms)
	if _crackle_phase > _rng.randf_range(15.0, 40.0):
		_crackle_active = false
		return 0.0

	# Sharp attack, quick decay
	var envelope := exp(-_crackle_phase * 0.3)

	# Noise burst with some tone
	var noise := _rng.randf() * 2.0 - 1.0
	var tone := sin(_crackle_phase * 0.5)

	return (noise * 0.7 + tone * 0.3) * envelope * exhaust_crackle * 0.4


# ─────────────────────────────────────────────
# UTILITIES
# ─────────────────────────────────────────────

func _apply_limiter(dt: float) -> float:
	_limiter_phase += 25.0 * dt  # 25 Hz limiter
	if _limiter_phase > 1.0:
		_limiter_phase -= 1.0

	return 0.3 if _limiter_phase < 0.3 else 1.0


func _soft_clip(x: float) -> float:
	if x > 1.0:
		return 1.0 - exp(-x + 1.0) * 0.5
	elif x < -1.0:
		return -1.0 + exp(x + 1.0) * 0.5
	return x


# ─────────────────────────────────────────────
# PUBLIC API
# ─────────────────────────────────────────────

func set_engine_state(rpm: float, max_rpm_val: float, throttle_val: float, redlining: bool) -> void:
	engine_rpm = rpm
	max_rpm = max_rpm_val
	throttle = throttle_val
	is_redlining = redlining


func set_boost(psi: float) -> void:
	boost_psi = psi
	# Could use this to modulate turbo intensity


## Presets for common JDM cars
func set_preset_2jz() -> void:
	## Toyota 2JZ-GTE (Supra)
	engine_type = 1  # Inline 6
	has_turbo = true
	has_vtec = false
	aggression = 0.65
	exhaust_crackle = 0.4
	turbo_volume = 0.5
	has_flutter = false


func set_preset_rb26() -> void:
	## Nissan RB26DETT (Skyline GT-R)
	engine_type = 1  # Inline 6
	has_turbo = true
	has_vtec = false
	aggression = 0.7
	exhaust_crackle = 0.5
	turbo_volume = 0.45
	has_flutter = true  # Sequential turbos often flutter


func set_preset_b18c() -> void:
	## Honda B18C (Integra Type R)
	engine_type = 0  # Inline 4
	has_turbo = false
	has_vtec = true
	vtec_engagement_rpm = 5800.0
	aggression = 0.6
	exhaust_crackle = 0.3


func set_preset_ej257() -> void:
	## Subaru EJ257 (STI)
	engine_type = 4  # Boxer 4
	has_turbo = true
	has_vtec = false
	aggression = 0.65
	exhaust_crackle = 0.45
	turbo_volume = 0.4
	has_flutter = false


func set_preset_13b_rew() -> void:
	## Mazda 13B-REW (RX-7 FD)
	engine_type = 5  # Rotary
	has_turbo = true
	has_vtec = false
	aggression = 0.5
	exhaust_crackle = 0.2  # Rotaries don't crackle much
	turbo_volume = 0.5
	has_flutter = false


func set_preset_4g63() -> void:
	## Mitsubishi 4G63 (Evo)
	engine_type = 0  # Inline 4
	has_turbo = true
	has_vtec = false
	aggression = 0.7
	exhaust_crackle = 0.55
	turbo_volume = 0.5
	has_flutter = true
