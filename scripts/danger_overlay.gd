extends ColorRect

# The single danger frame. GameManager owns the fade alpha and danger lifecycle.
@onready var game: GameManager = get_parent().get_parent() as GameManager

func _process(_delta: float) -> void:
	# The manager owns the approach latch and the fade after first arrival.
	visible = game.app_state == GameManager.AppState.PLAYING and not game.tutorial_active and game.danger_remaining > 0.0 and game.danger_vignette_alpha > 0.0
	modulate.a = game.danger_vignette_alpha

func _ready() -> void:
	var danger_shader := Shader.new()
	danger_shader.code = """shader_type canvas_item;
render_mode unshaded;
uniform float frame_width_ratio = 0.03;
void fragment() {
    // Screen pixels keep the border the same width after viewport resizing.
    vec2 edge_distance = min(SCREEN_UV, vec2(1.0) - SCREEN_UV) / SCREEN_PIXEL_SIZE;
    vec2 screen_size = vec2(1.0) / SCREEN_PIXEL_SIZE;
    float width = min(screen_size.x, screen_size.y) * frame_width_ratio;
    float edge = clamp((width - min(edge_distance.x, edge_distance.y)) / max(width * 0.64, 1.0), 0.0, 1.0);
    COLOR = vec4(0.85, 0.02, 0.03, edge * COLOR.a);
}
"""
	var danger_material := ShaderMaterial.new()
	danger_material.shader = danger_shader
	danger_material.set_shader_parameter("frame_width_ratio", 0.03)
	material = danger_material
