extends SceneTree

# Headless draw geometry, not rendered-pixel or gameplay acceptance.
# In-memory spies intercept drawing sinks; production layout code runs unchanged.
var passed := 0
var failed := 0
var expected_failures := 0
var alpha_bounds: Dictionary = {}
var retained_scripts: Array[GDScript] = []

func _initialize() -> void:
	call_deferred("run")

func check(label: String, ok: bool, mutation := false) -> void:
	if mutation:
		print("%s EXPECTED_MUTATION %s" % ["PASS" if ok else "FAIL", label])
		expected_failures += int(not ok)
		failed += int(ok)
	else:
		print("%s %s" % ["PASS" if ok else "FAIL", label])
		passed += int(ok)
		failed += int(not ok)

func compile_probe(source: String) -> GDScript:
	var script := GDScript.new()
	script.source_code = source
	var error := script.reload()
	if error != OK:
		push_error("K2 probe compilation failed: %s" % error)
		quit(2)
	retained_scripts.append(script)
	return script

func hazard_probe(mutation := "") -> GDScript:
	var source := FileAccess.get_file_as_string("res://scripts/action_hazard_manager.gd").replace("\r\n", "\n").replace("class_name ActionHazardManager\n", "")
	if mutation == "narrow":
		source = source.replace("lane_width(y) * fraction /", "lane_width(y) * fraction * 0.1 /")
	elif mutation == "thin":
		source = source.replace("maxf(4.5, 3.0 * screen_pixel())", "0.1 * screen_pixel()")
	# Record the rectangle actually submitted by _draw_painted, with its transform.
	var start := source.find("\tfunc draw_bordered(")
	var end := source.find("\tfunc sprite_size()", start)
	source = source.left(start) + "\tfunc draw_bordered(source: Texture2D, rect: Rect2) -> void:\n\t\tprobe_draws.append({\"texture\": source, \"rect\": rect, \"transform\": probe_transform})\n\n" + source.substr(end)
	source = source.replace("draw_set_transform(", "probe_set_transform(")
	source = source.replace("\tfunc visual_x(", "\tvar probe_draws: Array = []\n\tvar probe_transform := Transform2D.IDENTITY\n\n\tfunc probe_set_transform(at: Vector2, angle := 0.0, scale_value := Vector2.ONE) -> void:\n\t\tprobe_transform = Transform2D(angle, scale_value, 0.0, at)\n\n\tfunc visual_x(")
	return compile_probe(source)

func bean_probe(mutation := "") -> GDScript:
	var source := FileAccess.get_file_as_string("res://scripts/bean_visual.gd").replace("\r\n", "\n")
	# Exercise both pulse extrema deterministically in the test copy only.
	source = source.replace("1.0 + sin(Time.get_ticks_msec() * 0.018) * 0.14", "probe_pulse")
	if mutation == "overlap":
		source = source.replace("var offset := warning_offset(pulse)", "var offset := Vector2.ZERO")
	elif mutation == "shadow":
		source = source.replace("if warning:\n", "if warning:\n\t\t_draw_centered(preload(\"res://assets/art/gpt/items/landing_shadow.png\"), Vector2.ZERO, Vector2.ONE)\n")
	source = source.replace("draw_set_transform(", "probe_set_transform(").replace("draw_texture(", "probe_texture(")
	source += "\nvar probe_pulse := 1.0\nvar probe_draws: Array = []\nvar probe_transform := Transform2D.IDENTITY\n\nfunc probe_set_transform(at: Vector2, angle := 0.0, scale_value := Vector2.ONE) -> void:\n\tprobe_transform = Transform2D(angle, scale_value, 0.0, at)\n\nfunc probe_texture(texture: Texture2D, at: Vector2) -> void:\n\tprobe_draws.append({\"texture\": texture, \"rect\": probe_transform * Rect2(at, texture.get_size())})\n"
	return compile_probe(source)

func used_rect(texture: Texture2D) -> Rect2:
	if not alpha_bounds.has(texture):
		var image := texture.get_image()
		if image.is_compressed():
			image.decompress()
		alpha_bounds[texture] = Rect2(image.get_used_rect())
	return alpha_bounds[texture]

func screen_transform(item: CanvasItem) -> Transform2D:
	# Canvas transform alone omits content stretch to physical window pixels.
	return root.get_stretch_transform() * item.get_global_transform_with_canvas()

func opaque_screen_rect(hazard: Node2D, draw: Dictionary) -> Rect2:
	var texture: Texture2D = draw.texture
	var rect: Rect2 = draw.rect
	var bounds := used_rect(texture)
	var scale_value := rect.size / texture.get_size()
	var local := Rect2(rect.position + bounds.position * scale_value, bounds.size * scale_value)
	return (screen_transform(hazard) * draw.transform) * local

func lane_pixels(hazard: Node2D, world: Node2D, y: float) -> float:
	var route: int = hazard.route
	var neighbor := route + 1 if route < 2 else route - 1
	var transform := screen_transform(world)
	var a := transform * Vector2(world.call("_branch_visual_x", route, y), y)
	var b := transform * Vector2(world.call("_branch_visual_x", neighbor, y), y)
	return absf(a.x - b.x)

func measure_hazard(hazard: Node2D, world: Node2D, label: String, mutation := false, rope_only := false) -> void:
	hazard.probe_draws.clear()
	hazard._draw_painted()
	var draws: Array = hazard.probe_draws
	if rope_only:
		var draw: Dictionary = draws[1]
		var rect: Rect2 = draw.rect
		var texture: Texture2D = draw.texture
		var transform: Transform2D = screen_transform(hazard) * draw.transform
		var pixels := used_rect(texture).size.x * rect.size.x / texture.get_width() * transform.x.length()
		check("%s M rope_px=%.6f >=3" % [label, pixels], pixels >= 3.0 - 0.00001, mutation)
		return
	for index in draws.size():
		if hazard.kind == "M" and index == 1:
			continue
		var y: float = hazard.position.y
		var part := "body"
		var minimum := 0.8
		if hazard.kind == "K":
			y = hazard.gap_attachment_y(index == 0)
			part = "upper" if index == 0 else "lower"
		elif hazard.kind == "M":
			part = "anchor" if index == 0 else "stone"
			minimum = 0.8 if index == 0 else 0.6
		var lane := lane_pixels(hazard, world, y)
		var width := opaque_screen_rect(hazard, draws[index]).size.x
		var ratio := width / lane
		check("%s %s %s width_px=%.6f lane_px=%.6f ratio=%.6f >=%.2f" % [label, hazard.kind, part, width, lane, ratio, minimum], ratio >= minimum - 0.00001, mutation)

func warning_area(bean: Node2D, coin: GoldCollectible, resource_name: String) -> float:
	var coin_rect := screen_transform(coin.sprite) * coin.sprite.get_rect()
	var area := 0.0
	for draw: Dictionary in bean.probe_draws:
		if draw.texture.resource_path.get_file() == resource_name:
			var rect: Rect2 = screen_transform(bean) * draw.rect
			area += rect.intersection(coin_rect).get_area() if rect.intersects(coin_rect) else 0.0
	return area

func shadow_absent(bean: Node2D) -> bool:
	var names: Array[String] = []
	for draw: Dictionary in bean.probe_draws:
		names.append(draw.texture.resource_path.get_file())
	names.sort()
	return names == ["warning_arrow.png", "warning_badge.png"]

func run() -> void:
	var game := (load("res://scenes/main.tscn") as PackedScene).instantiate() as GameManager
	game.save_manager = SaveManager.new("user://qa/k2_obstacle_profile.json")
	root.add_child(game)
	await process_frame
	game.process_mode = Node.PROCESS_MODE_DISABLED
	var world := game.get_node("World") as Node2D
	var managers: Array[Node2D] = []
	for mutation in ["", "narrow", "thin"]:
		var manager := hazard_probe(mutation).new() as Node2D
		game.add_child(manager)
		manager.setup(game.player, game.stages)
		managers.append(manager)
	var beans: Array[Node2D] = []
	for mutation in ["", "overlap", "shadow"]:
		var bean := bean_probe(mutation).new() as Node2D
		bean.warning = true
		bean.position = Vector2(480, -5000)
		game.add_child(bean)
		beans.append(bean)
	var coin := GoldCollectible.new()
	coin.position = beans[0].position
	game.add_child(coin)
	coin.sprite.rotation = 0.08
	var coin_position := coin.position
	var bean_position := beans[0].position
	for size in [Vector2i(2400, 1080), Vector2i(1080, 2400)]:
		root.size = size
		await process_frame
		await process_frame
		var label := "%dx%d" % [size.x, size.y]
		check(label + " window size", root.size == size)
		for kind in ["THORN", "ARCH", "WALL", "WEB", "K", "M"]:
			for index in 2:
				var hazard: Node2D = managers[index]._spawn("K2-" + kind, kind, "LOW", 1, -5000.0)
				measure_hazard(hazard, world, label, index == 1)
				if kind == "M" and index == 0:
					measure_hazard(hazard, world, label, false, true)
				hazard.queue_free()
		var thin: Node2D = managers[2]._spawn("K2-thin", "M", "HIGH", 1, -5000.0)
		measure_hazard(thin, world, label, true, true)
		thin.queue_free()
		for pulse in [0.86, 1.14]:
			for resource_name in ["warning_badge.png", "warning_arrow.png"]:
				# Origin overlap for badge; a second fixture puts the coin under
				# the arrow too, so its own zero-area gate has a real negative case.
				coin.position = coin_position + (Vector2.ZERO if resource_name == "warning_badge.png" else Vector2(0, -70))
				for index in 2:
					var bean := beans[index]
					bean.probe_pulse = pulse
					bean.probe_draws.clear()
					bean._draw()
					for measured_name in ["warning_badge.png", "warning_arrow.png"]:
						if index == 1 and measured_name != resource_name:
							continue
						var area := warning_area(bean, coin, measured_name)
						check("%s coin_at=%s pulse=%.2f %s overlap_px2=%.6f ==0" % [label, resource_name, pulse, measured_name, area], area == 0.0, index == 1)
		coin.position = coin_position
		for index in [0, 2]:
			var bean := beans[index]
			bean.probe_draws.clear()
			bean._draw()
			check("%s LANDING_SHADOW absent draw_count=%d" % [label, bean.probe_draws.size()], shadow_absent(bean), index == 2)
		check(label + " coin active and landing positions unchanged", not coin.taken and coin.visible and coin.sprite.visible and coin.position == coin_position and beans[0].position == bean_position)
	print("RESULT test_K2_engel.gd PASS=%d FAIL=%d EXPECTED_MUTATION_FAIL=%d (in-memory faults discarded; disk code unchanged)" % [passed, failed, expected_failures])
	for audio_player in game.find_children("*", "AudioStreamPlayer", true, false):
		audio_player.stop()
		audio_player.stream = null
	game.queue_free()
	await process_frame
	await process_frame
	quit(0 if failed == 0 else 1)
