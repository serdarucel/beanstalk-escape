extends ColorRect

# The single danger frame. GameManager owns its visibility and fade alpha.
func _ready() -> void:
	var danger_shader := Shader.new()
	danger_shader.code = """shader_type canvas_item;
render_mode unshaded;
void fragment() {
    // Screen pixels keep the border the same width after viewport resizing.
    vec2 edge_distance = min(SCREEN_UV, vec2(1.0) - SCREEN_UV) / SCREEN_PIXEL_SIZE;
    float edge = clamp((28.0 - min(edge_distance.x, edge_distance.y)) / 18.0, 0.0, 1.0);
    COLOR = vec4(0.85, 0.02, 0.03, edge * COLOR.a);
}
"""
	var danger_material := ShaderMaterial.new()
	danger_material.shader = danger_shader
	material = danger_material
