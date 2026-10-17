extends SceneTree

const MAIN = preload("res://scenes/main.tscn")
var violations := 0
var samples := 0
var forks := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var game := MAIN.instantiate() as GameManager
	root.add_child(game)
	await process_frame
	await physics_frame
	_freeze(game)
	game.stages.reset_run(12345)
	game.app_state = GameManager.AppState.PLAYING
	game.tutorial_active = false
	game.total_time = 300.0
	game.player.speed_scale = 2.0
	# Use the full, unshortened transition as a conservative independent bound.
	var required := 250.0 * (Balance.DEAD_END_WARNING_SECONDS + Balance.BRANCH_TRANSITION_SECONDS + Balance.BRANCH_COMMAND_BUFFER_SECONDS)
	var last_candidate := Vector2.ZERO
	for number in range(4, 41):
		game.stages.ensure_stage(number + 1)
		var windows: Array = game.stages.pattern_for_stage(number).support_windows.duplicate(true)
		for window: Dictionary in windows:
			forks += 1
			var tip_y := game.stages.stage_bottom_y(number) - float(window.start_progress) * game.stages.stage_length(number)
			for route in 3:
				if window.supports.has(route):
					continue
				var offsets: Array = [0.0, 1.0, 24.0, 48.0, 67.0, 80.0, 120.0, -40.0]
				# Include lookahead from the previous chunk, where applicable.
				if float(window.start_progress) * game.stages.stage_length(number) < required - 48.0:
					offsets.append(float(window.start_progress) * game.stages.stage_length(number) + 48.0)
				for offset: float in offsets:
					var candidate := Vector2(float(Balance.ROUTE_X[route]), tip_y + offset)
					last_candidate = candidate
					var validated := game._validated_continue_position(candidate)
					_check_clearance(game, validated, required, "validated S%d offset %.0f" % [number, offset])
					_check(is_equal_approx(validated.y, candidate.y) and absi(game.stages.route_for_x(validated.x) - route) == 1, "prefer a safe adjacent branch at the same height")
					if offset >= 0.0:
						game.player.reset_run(candidate)
						game._remember_continue_checkpoint()
						_check_clearance(game, game.continue_checkpoint.position, required, "saved S%d offset %.0f" % [number, offset])
	# Exercise the actual continue respawn, including a previously falling player.
	game.continue_checkpoint = {"position": last_candidate}
	game.player.support_state = PlayerController.SupportState.FALLING_RECOVERY
	game.player.on_support = false
	game._respawn_at_continue_checkpoint()
	_check_clearance(game, game.player.global_position, required, "respawn")
	game.player._physics_process(1.0 / 120.0)
	_check(game.player.support_state == PlayerController.SupportState.SUPPORTED and game.player.on_support, "respawn remains supported on the first physics tick")
	_check(forks > 0 and samples > 100, "nonempty endless checkpoint cases")
	# All three branches have a nearby tip: same-height relocation cannot help.
	var number := 40
	var pattern := game.stages.pattern_for_stage(number)
	var original_windows: Array = pattern.support_windows.duplicate(true)
	pattern.support_windows = []
	for route in 3:
		var supports := [0, 1, 2]
		supports.erase(route)
		pattern.support_windows.append({"start_progress": 1000.0 / game.stages.stage_length(number), "end_progress": 1200.0 / game.stages.stage_length(number), "supports": supports})
	var candidate := Vector2(0.0, game.stages.stage_bottom_y(number) - 900.0)
	var fallback := game._validated_continue_position(candidate)
	_check(fallback.y > candidate.y and is_zero_approx(fallback.x), "rewind preserves the preferred route when no same-height route is safe")
	_check_clearance(game, fallback, required, "rewind fallback")
	pattern.support_windows = original_windows
	print("CONTINUE-CLEARANCE: seed=12345 speed=250 required=%.2f forks=%d samples=%d violations=%d" % [required, forks, samples, violations])
	_stop_audio(game)
	await process_frame
	game.queue_free()
	await process_frame
	await process_frame
	quit(0 if violations == 0 else 1)

func _stop_audio(node: Node) -> void:
	if node is AudioStreamPlayer or node is AudioStreamPlayer2D:
		node.stop()
	for child in node.get_children():
		_stop_audio(child)

func _freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children():
		_freeze(child)

func _check_clearance(game: GameManager, position: Vector2, required: float, label: String) -> void:
	samples += 1
	var stages := game.stages
	var stage := stages.stage_for_y(position.y)
	var route := stages.route_for_x(position.x)
	_check(stages.can_enter_route_at(stage, route, stages.progress_in_stage(position.y)), label + " open at spawn")
	var distance := INF
	# Inspect the actual support windows independently of the validator.
	for number in stages.stage_records:
		for window: Dictionary in stages.pattern_for_stage(int(number)).support_windows:
			if window.supports.has(route):
				continue
			var start := stages.stage_start_height(int(number)) + float(window.start_progress) * stages.stage_length(int(number))
			var end := stages.stage_start_height(int(number)) + float(window.end_progress) * stages.stage_length(int(number))
			if end >= -position.y:
				distance = minf(distance, maxf(start + position.y, 0.0))
	_check(distance > required, "%s distance=%.2f required>%.2f" % [label, distance, required])

func _check(ok: bool, label: String) -> void:
	if not ok:
		violations += 1
		if violations <= 12:
			print("FAIL: " + label)
