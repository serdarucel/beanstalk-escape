extends ColorRect

# The single danger frame. GameManager owns the fade alpha and danger lifecycle.
@onready var game: GameManager = get_parent().get_parent() as GameManager

func _process(_delta: float) -> void:
	# Physics children can move after the manager's HUD update. Check the actual
	# rendered frame's distance too, especially during retreat or a respawn.
	visible = game.app_state == GameManager.AppState.PLAYING and not game.tutorial_active and game.danger_vignette_alpha > 0.0 and game.spider.distance_to_player() <= GameManager.DANGER_FRAME_MAX_GAP
	modulate.a = game.danger_vignette_alpha

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
