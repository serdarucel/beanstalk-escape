extends SceneTree

# Focused drawing-layer check; this is not a rendered or device acceptance test.
class VisualGame extends Node2D:
	var app_state := GameManager.AppState.PLAYING

var passed := 0
var failed := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		push_error(label)

func _run() -> void:
	var game := VisualGame.new()
	var player := PlayerController.new()
	player.name = "Player"
	var visual := PlayerVisual.new()
	visual.name = "Body"
	player.add_child(visual)
	game.add_child(player)
	root.add_child(game)
	player.set_physics_process(false)
	visual.set_process(false)
	for skin in ["M1", "F1"]:
		_check(visual.set_skin(skin), "%s loads" % skin)
		visual._explorer_previous_app_state = GameManager.AppState.PLAYING
		visual._explorer_respawning = false
		player.support_state = PlayerController.SupportState.SUPPORTED
		player.action_state = PlayerController.ActionState.NONE
		visual.climb_time = 0.0
		visual._update_explorer_mode(player, game.app_state, 0.125)
		_check(is_equal_approx(visual.sprite.position.y, PlayerVisual.EXPLORER_FOOT_Y - 3.5), "%s legacy climb lift" % skin)
		_check(visual.frame_name == "climb", "%s keeps Mixamo climb frames" % skin)
		var data: Dictionary = visual._explorer_meta["anims"]["climb"]
		var cell: Array = data["cell"]
		var image := Image.load_from_file("res://assets/art/character3d/%s/base/climb.png" % visual._explorer_kind)
		var source_height := 0
		for index in int(data["frames"]):
			var origin := Vector2i(index % int(data["cols"]), index / int(data["cols"])) * Vector2i(int(cell[0]), int(cell[1]))
			var frame_image := image.get_region(Rect2i(origin, Vector2i(int(cell[0]), int(cell[1]))))
			source_height = maxi(source_height, frame_image.get_used_rect().size.y)
		var height := source_height * visual.sprite.scale.y
		print("%s climb silhouette: source=%d, height=%.3f px" % [skin, source_height, height])
		_check(absf(height - 175.5) < 0.01, "%s height is original spider x1.5" % skin)
		for direction in [-1, 1]:
			player.transition_from = 1
			player.transition_to = 1 + direction
			player.transition_progress = 0.075
			player.support_state = PlayerController.SupportState.TRANSFERRING
			player._update_transition_visual(player.transition_progress)
			visual._update_explorer_mode(player, game.app_state, 0.0)
			_check(visual.frame_name == ("lane_left" if direction < 0 else "lane_right"), "%s directional frames" % skin)
			_check(visual.scale.is_equal_approx(Vector2(1.04, 0.95)), "%s legacy takeoff squash" % skin)
			_check(is_equal_approx(visual.position.y, 7.0), "%s legacy takeoff dip" % skin)
			_check(is_equal_approx(visual.rotation, direction * 0.18 * sin(0.075 * PI)), "%s legacy lane lean" % skin)
			_check(visual.takeoff_particles.emitting and visual.takeoff_particles.scale.x == direction, "%s directional takeoff particles" % skin)
			_check(visual.transfer_trails[0].visible and visual.transfer_trails[0].scale.x == direction, "%s directional trail" % skin)
			visual._was_transferring = false
		player._reset_visual_pose()
		player.support_state = PlayerController.SupportState.SUPPORTED
		player.action_state = PlayerController.ActionState.AIRBORNE
		player.action_total = 1.0
		player.action_remaining = 0.5
		player._apply_action_visual()
		visual._update_explorer_mode(player, game.app_state, 0.0)
		_check(visual.frame_name == "jump" and is_equal_approx(visual.scale.y, player.jump_visual_scale), "%s preserves manual jump pulse and frames" % skin)
		player.cancel_action()
		player.support_state = PlayerController.SupportState.FALLING_RECOVERY
		visual._update_explorer_mode(player, game.app_state, 0.0)
		_check(visual.frame_name == "fall", "%s keeps fall frames" % skin)
		visual._update_explorer_mode(player, GameManager.AppState.PLAYER_DEAD, 0.125)
		_check(is_equal_approx(visual.sprite.position.y, PlayerVisual.EXPLORER_FOOT_Y + 9.5), "%s legacy 76px/s death drift" % skin)
		visual._update_explorer_mode(player, GameManager.AppState.PLAYER_DEAD, 2.0)
		_check(is_equal_approx(visual.death_offset, 92.0), "%s legacy death drift cap" % skin)
		player.support_state = PlayerController.SupportState.SUPPORTED
	var spider_visual := load("res://scripts/spider_visual.gd").new() as Node2D
	root.add_child(spider_visual)
	spider_visual.set_process(false)
	var spider_sprite: Sprite2D = spider_visual.get("sprite")
	var spider_image := Image.load_from_file("res://assets/art/gpt/spider/climb_1.png")
	var spider_height := spider_image.get_used_rect().size.y * spider_sprite.scale.y
	print("Spider climb silhouette: source=%d, height=%.3f px" % [spider_image.get_used_rect().size.y, spider_height])
	_check(absf(spider_height - 234.0) < 0.01, "spider height is original x2")
	spider_visual.scale = Vector2.ONE
	_check(is_equal_approx(spider_sprite.scale.y, 2.0), "run Body reset preserves spider size")
	spider_visual.free()
	game.free()
	print("PASS: %d, FAIL: %d, SKIP: 0" % [passed, failed])
	quit(1 if failed > 0 else 0)
