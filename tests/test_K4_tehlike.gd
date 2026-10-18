extends SceneTree

const DT := 1.0 / 60.0
var passed := 0
var failed := 0
var game: GameManager

func _initialize() -> void:
	_run.call_deferred()

func check(label: String, ok: bool) -> void:
	passed += int(ok)
	failed += int(not ok)
	print("%s %s" % ["PASS" if ok else "FAIL", label])

func step_frames(count: int) -> void:
	for tick in count:
		await physics_frame
		await process_frame

func measurements(rows: Array) -> Dictionary:
	var arrival := -1.0
	var visible_seconds := 0.0
	var approach_visible := false
	var held_closed := true
	var retreat_closed := true
	var held_samples := 0
	var retreat_samples := 0
	for row: Dictionary in rows:
		if arrival < 0.0 and row.gap <= Balance.DANGER_GAP + 0.001:
			arrival = row.time
		if row.visible:
			visible_seconds += DT
			if arrival < 0.0:
				approach_visible = true
		if arrival >= 0.0 and row.time >= arrival + GameManager.DANGER_FADE_OUT_SECONDS + DT and row.remaining > 0.0:
			held_samples += 1
			held_closed = held_closed and not row.visible and row.alpha <= 0.000001
		if row.remaining <= 0.0 and row.gap > Balance.DANGER_GAP + 0.001:
			retreat_samples += 1
			retreat_closed = retreat_closed and not row.visible
	return {"a": approach_visible, "b": held_samples > 0 and held_closed,
		"c": retreat_samples > 0 and retreat_closed,
		"d": arrival > 0.0 and visible_seconds <= arrival + GameManager.DANGER_FADE_OUT_SECONDS + 0.000001,
		"arrival": arrival, "visible_seconds": visible_seconds,
		"held_samples": held_samples, "retreat_samples": retreat_samples}

func thickness_ok(short_edge: float) -> bool:
	var mat := game.danger_vignette.material as ShaderMaterial
	var ratio: Variant = mat.get_shader_parameter("frame_width_ratio")
	# Verify the shader actually uses the measured uniform in screen pixels.
	return ratio != null and float(ratio) > 0.0 and float(ratio) * short_edge <= short_edge * 0.03 + 0.000001 and mat.shader.code.contains("min(screen_size.x, screen_size.y) * frame_width_ratio")

func _run() -> void:
	for size in [Vector2i(2400, 1080), Vector2i(1080, 2400)]:
		root.size = size
		game = (load("res://scenes/main.tscn") as PackedScene).instantiate() as GameManager
		game.save_manager = SaveManager.new("user://qa/k4_profile.json")
		root.add_child(game)
		await process_frame
		game._finish_intro()
		game._finish_onboarding()
		game._apply_window_aspect(size)
		# Isolate the real danger lifecycle from unrelated obstacle collisions.
		for system in [game.beans, game.rocks, game.storm]:
			system.set_physics_process(false)
			system.reset_run()
		game.audio.set_process(false)
		await step_frames(420)
		var label := "%dx%d" % [size.x, size.y]
		check(label + " setup PLAYING tutorial off", game.app_state == GameManager.AppState.PLAYING and not game.tutorial_active)
		var rows: Array = []
		var csv := FileAccess.open(get_script().resource_path.get_base_dir().path_join("K4-%s.csv" % label), FileAccess.WRITE)
		csv.store_line("cycle,time,gap,danger_remaining,alpha,visible")
		for cycle in 2:
			game._begin_danger()
			rows = []
			for tick in 300:
				await step_frames(1)
				var row := {"time": (tick + 1) * DT, "gap": game.spider.distance_to_player(),
					"remaining": game.danger_remaining, "alpha": game.danger_vignette_alpha,
					"visible": game.danger_vignette.visible}
				rows.append(row)
				csv.store_line("%d,%.6f,%.6f,%.6f,%.6f,%s" % [cycle, row.time, row.gap, row.remaining, row.alpha, row.visible])
			var measured := measurements(rows)
			print("RAW %s cycle=%d approach=%.6fs visible=%.6fs fade_limit=%.6fs hold_samples=%d retreat_samples=%d" % [label, cycle, measured.arrival, measured.visible_seconds, GameManager.DANGER_FADE_OUT_SECONDS, measured.held_samples, measured.retreat_samples])
			for key in ["a", "b", "c", "d"]:
				check("%s cycle=%d %s" % [label, cycle, key], measured[key])
		csv.close()
		var short_edge := float(mini(size.x, size.y))
		var mat := game.danger_vignette.material as ShaderMaterial
		var ratio: Variant = mat.get_shader_parameter("frame_width_ratio")
		print("RAW %s thickness=%s px limit=%.3f px (shader formula; headless)" % [label, str(float(ratio) * short_edge) if ratio != null else "unknown", short_edge * 0.03])
		check(label + " e", thickness_ok(short_edge))
		# Mutate only recorded observations, then run the SAME predicates.
		# No production debug flags or product behavior changes are involved.
		for key in ["a", "b", "c", "d"]:
			var broken := rows.duplicate(true)
			for row: Dictionary in broken:
				if key == "a":
					row.visible = false
				elif key == "b" and row.remaining > 0.0:
					row.visible = true
				elif key == "c" and row.remaining <= 0.0:
					row.visible = true
				elif key == "d":
					row.visible = true
			var rejected := not bool(measurements(broken)[key])
			print("MUTATION %s %s %s" % [label, key, "FAIL observed" if rejected else "NOT DETECTED"])
			check(label + " mutation " + key, rejected)
		mat.set_shader_parameter("frame_width_ratio", 0.04)
		var rejected := not thickness_ok(short_edge)
		print("MUTATION %s e %s" % [label, "FAIL observed" if rejected else "NOT DETECTED"])
		check(label + " mutation e", rejected)
		mat.set_shader_parameter("frame_width_ratio", ratio)
		game.queue_free()
		await step_frames(2)
	print("RESULT test_K4_tehlike.gd PASS=%d FAIL=%d" % [passed, failed])
	quit(0 if failed == 0 else 1)
