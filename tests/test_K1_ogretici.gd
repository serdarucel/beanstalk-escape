extends SceneTree

var passed := 0
var failed := 0
var negative_passed := 0
var game: GameManager

func _initialize() -> void:
	_run.call_deferred()

func check(label: String, ok: bool) -> void:
	passed += int(ok)
	failed += int(not ok)
	print("%s %s" % ["PASS" if ok else "FAIL", label])

func tick() -> void:
	await physics_frame
	await process_frame

func tap(key: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = key
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()

func measurements() -> Dictionary:
	var panel := game.get_node("HUD/TutorialPanel") as Label
	var arrow := game.get_node("HUD/TutorialArrow") as Control
	var skip := game.get_node("HUD/TutorialSkip") as Button
	var viewport := game.get_viewport_rect().size
	var pixel_scale := float(root.size.x) / viewport.x
	var font_size := panel.get_theme_font_size("font_size")
	var font_height := panel.get_theme_font("font").get_height(font_size)
	var hud_bottom := 0.0
	for key in ["Score", "Meters", "RunCoins", "Multiplier"]:
		var counter := game.get_node("HUD/" + key) as Control
		hud_bottom = maxf(hud_bottom, counter.position.y + counter.size.y)
	return {
		"panel visible": panel.is_visible_in_tree(),
		"text filled": not panel.text.strip_edges().is_empty(),
		"arrow visible": arrow.is_visible_in_tree(),
		"font device px >=36": font_size * pixel_scale >= 36.0,
		"panel inside screen": Rect2(Vector2.ZERO, viewport).encloses(panel.get_rect()),
		"portrait width >=80%": viewport.x > viewport.y or panel.size.x >= viewport.x * 0.8,
		"text not clipped": panel.get_visible_line_count() >= panel.get_line_count(),
		"arrow length >=2 text heights": arrow.size.y - 20.0 >= font_height * 2.0 - 0.01,
		"arrow upper half": arrow.position.y + arrow.size.y <= viewport.y * 0.5,
		"skip <=120x36": skip.size.x <= 120.0 and skip.size.y <= 36.0,
		"skip outside panel": not skip.get_rect().intersects(panel.get_rect()),
		"skip below score": skip.position.y >= hud_bottom,
		"skip upper right": skip.position.x >= viewport.x * 0.75 and skip.position.y + skip.size.y < viewport.y * 0.5,
		"skip smaller font": skip.get_theme_font_size("font_size") < font_size,
		"skip touch target >=44": skip._has_point(Vector2(1, -5.9)) and skip._has_point(Vector2(1, 37.9)),
	}

func sample(label: String) -> void:
	var panel := game.get_node("HUD/TutorialPanel") as Label
	var skip := game.get_node("HUD/TutorialSkip") as Button
	print("RAW %s window=%s viewport=%s text=%s font_px=%.2f panel=%s skip=%s" % [label, root.size, game.get_viewport_rect().size, panel.text.replace("\n", " / "), panel.get_theme_font_size("font_size") * float(root.size.x) / game.get_viewport_rect().size.x, panel.get_rect(), skip.get_rect()])
	var values := measurements()
	for key in values:
		check(label + " " + key, values[key])

func reject(label: String) -> void:
	var rejected := not bool(measurements()[label])
	negative_passed += int(rejected)
	check("negative control rejects " + label, rejected)
	print("EXPECTED_FAIL %s detected=%s" % [label, rejected])

func negative_controls() -> void:
	var panel := game.get_node("HUD/TutorialPanel") as Label
	var arrow := game.get_node("HUD/TutorialArrow") as Control
	var skip := game.get_node("HUD/TutorialSkip") as Button
	panel.hide()
	reject("panel visible")
	panel.show()
	var text := panel.text
	panel.text = ""
	reject("text filled")
	panel.text = text
	arrow.hide()
	reject("arrow visible")
	arrow.show()
	var font_size := panel.get_theme_font_size("font_size")
	panel.add_theme_font_size_override("font_size", 1)
	reject("font device px >=36")
	panel.add_theme_font_size_override("font_size", font_size)
	var position := panel.position
	panel.position.x = -100.0
	reject("panel inside screen")
	panel.position = position
	var size := panel.size
	panel.size.x = 50.0
	reject("portrait width >=80%")
	panel.size = size
	panel.max_lines_visible = 1
	panel.text = "A\nB\nC"
	await process_frame
	reject("text not clipped")
	panel.max_lines_visible = -1
	panel.text = text
	var arrow_size := arrow.size
	arrow.size.y = 1.0
	reject("arrow length >=2 text heights")
	arrow.size = arrow_size
	var arrow_position := arrow.position
	arrow.position.y = game.get_viewport_rect().size.y
	reject("arrow upper half")
	arrow.position = arrow_position
	skip.size = Vector2(121, 37)
	reject("skip <=120x36")
	skip.size = Vector2(88, 32)
	var skip_position := skip.position
	skip.position = panel.position
	reject("skip outside panel")
	skip.position.y = 0.0
	reject("skip below score")
	skip.position = Vector2.ZERO
	reject("skip upper right")
	skip.position = skip_position
	skip.add_theme_font_size_override("font_size", font_size)
	reject("skip smaller font")
	skip.add_theme_font_size_override("font_size", 14)
	skip.size.y = 1.0
	reject("skip touch target >=44")
	skip.size.y = 32.0

func run_window(window_size: Vector2i) -> void:
	root.size = window_size
	game = (load("res://scenes/main.tscn") as PackedScene).instantiate() as GameManager
	game.save_manager = SaveManager.new("user://qa/k1_%d.json" % Time.get_ticks_usec())
	root.add_child(game)
	await process_frame
	assert(game.app_state == GameManager.AppState.PLAYING, "startup must enter PLAYING immediately")
	game.layout_hud_for_viewport(game.get_viewport_rect().size)
	var seen := {}
	var last_step := 0
	for frame in range(2200):
		if not game.tutorial_active:
			break
		var step := game.tutorial_step
		if step != last_step:
			last_step = step
			sample("%s step%d start" % [window_size, step])
			seen["%d-start" % step] = true
		var opening: Dictionary = game.stages.stage_records[3]
		var ahead := game.player.global_position.y + float(opening.start_height) + float(opening.encounters[step - 1].anchor)
		if ahead <= game.player.climb_speed() * 2.0 and not seen.has("%d-middle" % step):
			sample("%s step%d middle(2s)" % [window_size, step])
			seen["%d-middle" % step] = true
		if ahead <= 40.0 and not seen.has("%d-end" % step):
			sample("%s step%d end" % [window_size, step])
			seen["%d-end" % step] = true
		if step == 1 and ahead < game.player.climb_speed() and game.player.active_branch == 1 and game.player.movement_mode == PlayerController.MovementMode.ATTACHED:
			tap(KEY_RIGHT)
		if step >= 2 and game.player.active_branch != 1 and game.player.movement_mode == PlayerController.MovementMode.ATTACHED:
			tap(KEY_LEFT)
		if step == 2 and ahead < 44.0 and not game.player.is_airborne():
			tap(KEY_W)
		if step == 3 and ahead < 44.0 and not game.player.is_hugging():
			tap(KEY_S)
		await tick()
	check("all 9 step checkpoints " + str(window_size), seen.size() == 9)
	check("natural input completes tutorial " + str(window_size), not game.tutorial_active)
	game._start_onboarding()
	game.tutorial_step_elapsed = 0.2
	game._retry_onboarding()
	check("TRY AGAIN retained " + str(window_size), "TRY AGAIN" in game.get_node("HUD/TutorialPanel").text)
	sample("retry " + str(window_size))
	if window_size.x < window_size.y:
		await negative_controls()
	var skip := game.get_node("HUD/TutorialSkip") as Button
	skip.pressed.disconnect(game._finish_onboarding)
	skip.pressed.emit()
	check("negative control SKIP missing callback rejected", game.tutorial_active)
	negative_passed += int(game.tutorial_active)
	print("EXPECTED_FAIL SKIP ends tutorial detected=%s" % game.tutorial_active)
	skip.pressed.connect(game._finish_onboarding)
	skip.pressed.emit()
	check("SKIP ends tutorial " + str(window_size), not game.tutorial_active and not game.get_node("HUD/TutorialPanel").visible and not game.get_node("HUD/TutorialArrow").visible)
	game.audio.set_process(false)
	for stream_player in game.find_children("*", "AudioStreamPlayer", true, false):
		stream_player.stop()
		stream_player.stream = null
	game.queue_free()
	await process_frame
	await process_frame

func _run() -> void:
	await run_window(Vector2i(2400, 1080))
	await run_window(Vector2i(1080, 2400))
	print("RESULT test_K1_ogretici.gd PASS=%d FAIL=%d NEGATIVE_REJECTED=%d (headless; visual/touch hardware NOT RUN)" % [passed, failed, negative_passed])
	quit(0 if failed == 0 else 1)
