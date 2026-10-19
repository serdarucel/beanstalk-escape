extends RefCounted

const SHADER := preload("res://assets/shaders/character_flash.gdshader")
# H (turns), S, V multiplier. Old torso medians: see TESLIM-codex-C.md.
# Clay/fern corrected to the requested names; moss/plum shifted for separation.
const COLORS := {
	"clay": Vector3(0.045, 0.62, 0.70),
	"ember": Vector3(0.033, 0.82, 1.10),
	"fern": Vector3(0.29, 0.57, 1.20),
	"moss": Vector3(0.22, 0.68, 0.58),
	"night": Vector3(0.642, 0.65, 0.38),
	"ocean": Vector3(0.486, 0.72, 0.82),
	"plum": Vector3(0.79, 0.58, 0.67),
	"sky": Vector3(0.592, 0.46, 1.25),
	"sun": Vector3(0.12, 0.61, 1.16),
}

static func configure(material: ShaderMaterial, outfit_id: String, mask: Texture2D) -> void:
	var outfit := outfit_id.trim_prefix("outfit_")
	material.set_shader_parameter("outfit_mask", mask)
	material.set_shader_parameter("outfit_hsv", COLORS.get(outfit, Vector3(0.0, 0.0, 1.0)))
	material.set_shader_parameter("outfit_enabled", 1.0 if mask != null and COLORS.has(outfit) else 0.0)

static func portrait_material(outfit_id: String, mask: Texture2D) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("outline_source_px", 0.0)
	material.set_shader_parameter("shadow_strength", 0.0)
	configure(material, outfit_id, mask)
	return material
