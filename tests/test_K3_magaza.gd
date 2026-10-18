extends SceneTree

var passed := 0
var failed := 0
var expected_failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(label: String, ok: bool) -> void:
	passed += int(ok)
	failed += int(not ok)
	print("%s %s" % ["PASS" if ok else "FAIL", label])

func gate(label: String, normal: bool, broken: bool) -> void:
	check(label, normal)
	print("%s EXPECTED_MUTATION %s" % ["FAIL" if not broken else "PASS", label])
	expected_failures += int(not broken)
	check("negative control detected: " + label, not broken)

func portrait_path_ok(icon: TextureRect) -> bool:
	return icon.texture != null and "character3d/" in icon.texture.resource_path

func female_preview_ok(sprite: Sprite2D) -> bool:
	return sprite.texture != null and "character3d/kadin/" in sprite.texture.resource_path

func portrait_scale(icon: TextureRect) -> float:
	if icon.texture == null:
		return INF
	# KEEP_ASPECT_CENTERED draws the full image at this uniform scale.
	# Visible alpha height cancels: (alpha_height * scale) / alpha_height.
	var fit := minf(icon.size.x / icon.texture.get_width(), icon.size.y / icon.texture.get_height())
	return fit * device_scale(icon)

func device_scale(item: CanvasItem) -> float:
	# Headless get_screen_transform omits window stretch. Derive physical
	# pixels independently from the requested window and logical viewport.
	var canvas := item.get_global_transform_with_canvas()
	var viewport_size := root.get_visible_rect().size
	var pixels := Vector2(root.size) / viewport_size
	return maxf((canvas.x * pixels).length(), (canvas.y * pixels).length())

func preview_scale(sprite: Sprite2D) -> float:
	return device_scale(sprite)

func scale_ok(value: float) -> bool:
	return is_finite(value) and value > 0.0 and value <= 2.0 + 0.0001

func text_counts(node: Node) -> Vector2i:
	var counts := Vector2i.ZERO
	if (node is Label or node is Button) and node.is_visible_in_tree():
		counts.x += 1
		var value := str(node.text).to_upper()
		counts.y += int("LV" in value or "XP" in value)
	for child in node.get_children():
		counts += text_counts(child)
	return counts

func test_text(main: Node, context: String) -> void:
	var counts := text_counts(main)
	print("MEASURE %s visible_texts=%d forbidden=%d" % [context, counts.x, counts.y])
	check(context + " visible text coverage", counts.x > 0)
	for token in ["LV", "XP"]:
		var injected := Label.new()
		injected.text = token
		main.add_child(injected)
		var broken := text_counts(main).y == 0
		main.remove_child(injected)
		injected.free()
		gate(context + " no " + token, counts.y == 0, broken)

func settle() -> void:
	for frame in range(8):
		await process_frame

func _run() -> void:
	# A dependency compile error otherwise leaves the scene partially initialized
	# and the runner waiting forever instead of returning a failed test.
	var hazard_script := load("res://scripts/action_hazard_manager.gd") as GDScript
	if hazard_script == null or not hazard_script.can_instantiate():
		check("main scene dependencies compile (K3 assertions NOT RUN)", false)
		print("K3 RESULT PASS=%d FAIL=%d EXPECTED_FAIL=%d" % [passed, failed, expected_failures])
		quit(1)
		return
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await settle()
	var ui = main.meta_ui
	for dimensions in [Vector2i(1080, 2400), Vector2i(2400, 1080)]:
		root.size = dimensions
		main._show_menu()
		await settle()
		test_text(main, "%s menu" % dimensions)
		main._show_shop()
		await settle()
		print("MEASURE window=%s viewport=%s screen_scale=%s" % [root.size, root.get_visible_rect().size, ui.get_screen_transform().get_scale()])
		var cards: Array[Node] = ui.grid.get_children().filter(func(node): return node is PanelContainer)
		check("%s two character cards" % dimensions, cards.size() == 2)
		for card in cards:
			var icons: Array[Node] = card.find_children("*", "TextureRect", true, false)
			check("%s card portrait exists" % dimensions, icons.size() == 1)
			if icons.size() != 1:
				continue
			var icon := icons[0] as TextureRect
			var saved := icon.texture
			var normal := portrait_path_ok(icon)
			print("MEASURE %s portrait=%s scale=%.6f" % [dimensions, saved.resource_path, portrait_scale(icon)])
			icon.texture = GradientTexture2D.new()
			var broken := portrait_path_ok(icon)
			icon.texture = saved
			gate("%s %s 3D portrait" % [dimensions, card.get_index()], normal, broken)
			var measured := portrait_scale(icon)
			var saved_scale := icon.scale
			icon.scale *= 100.0
			broken = scale_ok(portrait_scale(icon))
			icon.scale = saved_scale
			gate("%s %s portrait scale <=2" % [dimensions, card.get_index()], scale_ok(measured), broken)
		ui._preview_character("F1")
		await settle()
		var sprite: Sprite2D = ui.preview.sprite
		var female := female_preview_ok(sprite)
		print("MEASURE %s preview=%s scale=%.6f" % [dimensions, sprite.texture.resource_path, preview_scale(sprite)])
		ui._preview_character("M1")
		var wrong_sex := female_preview_ok(sprite)
		ui._preview_character("F1")
		gate("%s F1 female preview" % dimensions, female, wrong_sex)
		var measured := preview_scale(sprite)
		var saved_scale := sprite.scale
		sprite.scale *= 100.0
		var broken := scale_ok(preview_scale(sprite))
		sprite.scale = saved_scale
		gate("%s preview scale <=2" % dimensions, scale_ok(measured), broken)
		test_text(main, "%s shop CHARACTERS" % dimensions)
		for tab in ["OUTFIT", "PET"]:
			ui.active_tab = tab
			ui.refresh()
			await settle()
			test_text(main, "%s shop %s" % [dimensions, tab])
	main.free()
	await process_frame
	print("K3 RESULT PASS=%d FAIL=%d EXPECTED_FAIL=%d" % [passed, failed, expected_failures])
	quit(0 if failed == 0 else 1)
