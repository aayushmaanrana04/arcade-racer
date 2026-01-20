extends Control

@onready var viewport := $SubViewportContainer/SubViewport
@onready var post_fx_material := $ColorRect.material as ShaderMaterial

func _ready():
	post_fx_material.set_shader_parameter(
		"screen_tex",
		viewport.get_texture()
	)
