extends Node2D

const BEAN_FRAMES := [
	preload("res://assets/art/gpt/items/bean_0.png"),
	preload("res://assets/art/gpt/items/bean_45.png"),
	preload("res://assets/art/gpt/items/bean_90.png"),
	preload("res://assets/art/gpt/items/bean_burst.png"),
]
const WARNING_BADGE := preload("res://assets/art/gpt/items/warning_badge.png")
const WARNING_ARROW := preload("res://assets/art/gpt/items/warning_arrow.png")

@export var warning := false
var burst := false
var redraw_count := 0
var redraw_elapsed := 0.0

func _process(delta: float) -> void:
	redraw_elapsed += delta
	if redraw_elapsed >= 1.0 / 30.0:
		redraw_elapsed = fmod(redraw_elapsed, 1.0 / 30.0)
		queue_redraw()

func _draw() -> void:
	redraw_count += 1
	if warning:
		var pulse := 1.0 + sin(Time.get_ticks_msec() * 0.018) * 0.14
		var offset := warning_offset(pulse)
		_draw_centered(WARNING_BADGE, Vector2(0, -35) + offset, Vector2(0.19, 0.19) * pulse)
		_draw_centered(WARNING_ARROW, Vector2(0, -70) + offset, Vector2(0.16, 0.16) * pulse)
	else:
		var frame := 3 if burst else int(Time.get_ticks_msec() / 90) % 3
		var scale_value := 0.26 if burst else 0.22
		_draw_centered(BEAN_FRAMES[frame], Vector2.ZERO, Vector2(scale_value, scale_value))

func warning_rects(pulse: float, offset := Vector2.ZERO) -> Array[Rect2]:
	var badge_size := WARNING_BADGE.get_size() * 0.19 * pulse
	var arrow_size := WARNING_ARROW.get_size() * 0.16 * pulse
	return [Rect2(Vector2(0, -35) + offset - badge_size * 0.5, badge_size),
		Rect2(Vector2(0, -70) + offset - arrow_size * 0.5, arrow_size)]

func warning_offset(pulse: float) -> Vector2:
	# Compare actual sprite rectangles, including their rotation, scale and canvas.
	# Move only the drawing: the warning node and the bean landing point stay put.
	var inverse := get_global_transform_with_canvas().affine_inverse()
	var coins: Array[Rect2] = []
	for node in get_tree().root.find_children("*", "Sprite2D", true, false):
		var sprite := node as Sprite2D
		if not sprite.get_parent() is GoldCollectible or not sprite.is_visible_in_tree() or sprite.modulate.a <= 0.0 or sprite.texture == null:
			continue
		var screen_rect: Rect2 = sprite.get_global_transform_with_canvas() * sprite.get_rect()
		coins.append((inverse * screen_rect).grow(1.0))
	var rects := warning_rects(pulse)
	var candidates: Array[float] = [0.0]
	for coin in coins:
		for rect in rects:
			if rect.end.x <= coin.position.x or rect.position.x >= coin.end.x:
				continue
			candidates.append(coin.position.y - rect.end.y - 1.0)
			candidates.append(coin.end.y - rect.position.y + 1.0)
	candidates.sort_custom(func(a: float, b: float) -> bool: return absf(a) < absf(b))
	for displacement in candidates:
		var clear := true
		for coin in coins:
			for rect in rects:
				if Rect2(rect.position + Vector2(0, displacement), rect.size).intersects(coin):
					clear = false
		if clear:
			return Vector2(0, displacement)
	return Vector2.ZERO

func show_burst() -> void:
	burst = true
	visible = true
	queue_redraw()

func _draw_centered(texture: Texture2D, position: Vector2, scale_value: Vector2) -> void:
	draw_set_transform(position, 0.0, scale_value)
	draw_texture(texture, -texture.get_size() * 0.5)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
