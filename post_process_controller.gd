extends CanvasLayer
## Controller for the pixelation post-processing effect.
## Attach to the PostProcessing CanvasLayer node.

@export var target_resolution: Vector2 = Vector2(256, 144):
	set(value):
		target_resolution = value
		_update_shader()

@export_range(2.0, 32.0) var color_levels: float = 8.0:
	set(value):
		color_levels = value
		_update_shader()

@export_range(0.0, 1.0) var blend: float = 0.0:
	set(value):
		blend = value
		_update_shader()

@export var quantize_colors: bool = true:
	set(value):
		quantize_colors = value
		_update_shader()

@onready var _effect_rect: ColorRect = $PixelationEffect


func _ready() -> void:
	_update_shader()


func _update_shader() -> void:
	if not is_instance_valid(_effect_rect):
		return
	var mat := _effect_rect.material as ShaderMaterial
	if mat:
		mat.set_shader_parameter("target_resolution", target_resolution)
		mat.set_shader_parameter("color_levels", color_levels)
		mat.set_shader_parameter("blend", blend)
		mat.set_shader_parameter("quantize_colors", quantize_colors)


## Set the pixelation resolution preset
func set_resolution_preset(preset: String) -> void:
	match preset:
		"144p":
			target_resolution = Vector2(256, 144)
		"240p":
			target_resolution = Vector2(426, 240)
		"360p":
			target_resolution = Vector2(640, 360)
		"480p":
			target_resolution = Vector2(854, 480)
		_:
			push_warning("Unknown resolution preset: %s" % preset)


## Toggle the effect on/off
func set_enabled(enabled: bool) -> void:
	_effect_rect.visible = enabled
