extends SceneTree

var passed := 0
var failed := 0

func _init() -> void:
	call_deferred("_run")

func _check(condition: bool, label: String, detail: String) -> void:
	if condition:
		passed += 1
		print("PASS %s %s" % [label, detail])
	else:
		failed += 1
		print("FAIL %s %s" % [label, detail])

func _check_run(game: GameManager, label: String) -> void:
	var camera := game.player.get_node("Camera2D") as Camera2D
	var spider_body := game.spider.get_node("Body") as Node2D
	_check(game.app_state == GameManager.AppState.PLAYING and game.state == GameManager.State.PLAYING, label + "-STATE", "PLAYING immediately")
	_check(not game.get_node("HUD/IntroText").visible and not game.get_node("HUD/IntroSummit").visible, label + "-HUD", "cinematic hidden")
	_check(game.player.is_physics_processing() and game.spider.is_physics_processing() and game.beans.is_physics_processing() and game.rocks.is_physics_processing() and game.storm.is_physics_processing(), label + "-PHYSICS", "run systems enabled")
	_check(game.player.global_position == Vector2.ZERO and game.total_time == 0.0 and game.score == 0.0 and game.current_lives == game.max_lives and game.golds.visible, label + "-RESET", "fresh run and visible golds")
	_check(camera.position == game.camera_play_position and camera.offset == Vector2.ZERO and spider_body.visible and spider_body.position == Vector2.ZERO and spider_body.scale == Vector2.ONE, label + "-PRESENTATION", "normal camera and guardian")
	_check(game.audio.music.stream == game.audio.STREAMS.music_game, label + "-MUSIC", "music_game")

func _run() -> void:
	var game := (load("res://scenes/main.tscn") as PackedScene).instantiate() as GameManager
	game.save_manager = SaveManager.new("user://qa/direct_play_%d.json" % Time.get_ticks_usec())
	root.add_child(game)
	_check_run(game, "STARTUP")
	_check(game.tutorial_active and game.tutorial_step == 1, "FIRST-RUN-TUTORIAL", "onboarding starts without cinematic")
	game._finish_onboarding()
	game.economy.shop.selected_character = "F1"
	game._show_menu()
	game.get_node("HUD/NewRun").pressed.emit()
	assert(game.app_state == GameManager.AppState.PLAYING, "Play must enter PLAYING synchronously")
	_check_run(game, "PLAY")
	_check(not game.meta_ui.visible and (game.player.get_node("Body") as PlayerVisual).skin_id == "F1" and game.mode == GameManager.MODE_NORMAL, "NEW-RUN-DIRECT", "selected=F1 character_select=false")
	_check(not game.tutorial_active and game.danger_remaining > 0.0, "RETURNING-RUN-DANGER", "saved tutorial rule retained")
	var start_snapshot := [game.player.global_position, game.spider.global_position, game.beans.hit_count, game.total_time]
	game.start_game()
	assert(game.app_state == GameManager.AppState.PLAYING, "start_game must enter PLAYING synchronously")
	_check_run(game, "START-GAME")
	var generation := game.run_generation
	game._enter_player_dead(GameManager.DeathCause.CAUGHT)
	game._show_run_result()
	game._show_leaderboard()
	var play_again := game.get_node("HUD/RestartRun") as Button
	_check(game.app_state == GameManager.AppState.PLAYER_DEAD and game.death_phase == "result" and game.leaderboard_visible and play_again.visible and not play_again.disabled, "PLAY-AGAIN-SETUP", "death result button available")
	play_again.pressed.emit()
	assert(game.app_state == GameManager.AppState.PLAYING, "Play Again must enter PLAYING synchronously")
	_check_run(game, "PLAY-AGAIN")
	var replay_snapshot := [game.player.global_position, game.spider.global_position, game.beans.hit_count, game.total_time]
	_check(game.run_generation == generation + 1 and replay_snapshot == start_snapshot, "PLAY-AGAIN-EQUIVALENCE", "same fresh run as Play")
	game.save_manager.profile.replay.nightmare_unlocked = true
	game._show_menu()
	game.mode = GameManager.MODE_NIGHTMARE
	game.start_game()
	_check_run(game, "NIGHTMARE")
	_check(game.mode == GameManager.MODE_NIGHTMARE and not game.tutorial_active and not game.meta_ui.visible and (game.player.get_node("Body") as PlayerVisual).skin_id == "F1", "NIGHTMARE-DIRECT", "selected=F1 character_select=false")
	root.content_scale_size = Vector2i.ZERO
	for viewport_size in [Vector2i(960, 540), Vector2i(1586, 669), Vector2i(540, 960)]:
		root.size = viewport_size
		game.layout_hud_for_viewport(Vector2(viewport_size))
		var logo := game.get_node("HUD/MenuLogo") as TextureRect
		var prompt := game.get_node("HUD/Menu") as Label
		_check(logo.get_global_rect().end.y + 16.0 <= prompt.get_global_rect().position.y and prompt.get_global_rect().end.y < game.get_node("HUD/NewRun").position.y, "MENU-SEPARATION", "%s" % viewport_size)
	game.queue_free()
	await process_frame
	print("RESULT intro_smoke PASS=%d FAIL=%d" % [passed, failed])
	quit(0 if failed == 0 else 1)
