class_name PowerupManager
extends Node2D

var types: Dictionary = {
	"MAGNET": {"id": "MAGNET", "duration": 10.0, "color": Color("68e58b"), "label": "MAGNET LEAF"},
	"DOUBLE": {"id": "DOUBLE", "duration": 10.0, "color": Color("ffd260"), "label": "GOLDEN BEAN ×2"},
	"WINGS": {"id": "WINGS", "duration": 8.0, "color": Color("ffab62"), "label": "WING FLIGHT"},
}
var active: Dictionary = {}
var items: Array[Dictionary] = []
var spawned := 0
var collected := 0
var next_spawn_time := 0.0
var player: PlayerController
var stages: StageManager
var game: GameManager
var rng := RandomNumberGenerator.new()
var previous_type := ""
var textures: Dictionary = {}
var visual_time := 0.0
var flight_serial := 0
var air_coins: Array[GoldCollectible] = []

func setup(target: PlayerController, stage_manager: StageManager, manager: GameManager) -> void:
	player = target
	stages = stage_manager
	game = manager
	z_index = 3
	for id: String in types.keys():
		register_type(id, types[id])

func register_type(id: String, data: Dictionary) -> void:
	if id.is_empty() or float(data.get("duration", 0.0)) <= 0.0:
		return
	var definition := data.duplicate(true)
	definition["id"] = id
	definition["color"] = data.get("color", Color.WHITE)
	definition["label"] = data.get("label", id)
	types[id] = definition
	var path := "res://assets/art/eglence/powerup_%s.png" % id.to_lower()
	if ResourceLoader.exists(path):
		textures[id] = load(path)
	elif id == "WINGS":
		# Fire Wings is an atlas region in PlayerVisual, not a separate rig PNG.
		var wing := AtlasTexture.new()
		wing.atlas = PlayerVisual.ROCK_FIRE_ATLAS
		wing.region = Rect2(Vector2(1024, 512), PlayerVisual.FIRE_WINGS_REGION_SIZE)
		textures[id] = wing

func reset_run() -> void:
	clear_air_coins()
	active.clear()
	items.clear()
	spawned = 0
	collected = 0
	previous_type = ""
	visual_time = 0.0
	rng.seed = stages.run_seed ^ 0xB8
	# The pickup appears now; its contact height is another 1.5 seconds ahead.
	next_spawn_time = rng.randf_range(15.0, 17.0)
	queue_redraw()

func is_active(id: String) -> bool:
	return float(active.get(id, 0.0)) > 0.0

func activate(id: String) -> void:
	if types.has(id):
		active[id] = float(types[id].duration)
		if id == "WINGS" and player != null:
			player.start_wing_flight(float(types[id].duration))
			_spawn_air_coins()

func _spawn_air_coins() -> void:
	clear_air_coins()
	flight_serial += 1
	var distance := 0.0
	var seconds := float(types.WINGS.duration)
	for step in range(ceili(seconds * 60.0)):
		distance += Balance.PLAYER_VERTICAL_SPEED * 1.5 * Balance.speed_scale_for_time(game.total_time + float(step) / 60.0) / 60.0
	for index in range(maxi(floori((distance - 120.0) / 70.0) + 1, 0)):
		var y := player.global_position.y - 120.0 - float(index) * 70.0
		for lane in 3:
			var id := "WINGS_%d_%d_%d" % [flight_serial, index, lane]
			# Stage -1 keeps the flight's coins outside the ground coin window.
			game.golds._spawn({"id": id, "route": lane, "position": Vector2(stages.branch_x_at(lane, y), y)}, -1)
			var coin := game.golds.get_node(NodePath(id)) as GoldCollectible
			coin.sprite.position.y = -70.0
			air_coins.append(coin)

func clear_air_coins() -> void:
	for coin in air_coins:
		if is_instance_valid(coin) and not coin.taken:
			coin.queue_free()
	air_coins.clear()

func sync_after_player_teleport() -> void:
	# Keep the run clock and effects through tutorial rewinds and rewarded continues.
	# Discard only pickups that are already behind the new player position.
	if player != null:
		items = items.filter(func(item: Dictionary) -> bool: return float(item.y) <= player.global_position.y + 40.0)
	queue_redraw()

func _physics_process(delta: float) -> void:
	visible = game != null and game.app_state == GameManager.AppState.PLAYING
	if not visible or player == null:
		return
	visual_time += delta
	for id: String in active.keys():
		if id == "WINGS":
			active[id] = player.flight_remaining if player.is_flying() else 0.0
		else:
			active[id] = maxf(float(active[id]) - delta, 0.0)
		if float(active[id]) <= 0.0:
			active.erase(id)
			if id == "WINGS":
				clear_air_coins()
	if game.total_time >= next_spawn_time:
		_try_spawn()
	for index in range(items.size() - 1, -1, -1):
		var item := items[index]
		var lane := int(item.route)
		var eligible := lane == player.active_branch
		if player.movement_mode == PlayerController.MovementMode.TRANSITION:
			eligible = lane == player.transition_from or lane == player.transition_to
		if eligible and absf(float(item.y) - player.global_position.y) <= 40.0:
			activate(String(item.type))
			collected += 1
			items.remove_at(index)
		elif float(item.y) > player.global_position.y + 500.0:
			items.remove_at(index)
	queue_redraw()

func _try_spawn() -> void:
	var y := player.global_position.y - player.climb_speed() * 1.5
	var preferred := player.transition_to if player.movement_mode == PlayerController.MovementMode.TRANSITION else player.active_branch
	var route := -1
	for candidate in [preferred, (preferred + 1) % 3, (preferred + 2) % 3]:
		if _safe_route(int(candidate), y):
			route = int(candidate)
			break
	if route < 0:
		return # Retry against actual run position; never put a reward in a hazard.
	var id := "MAGNET"
	if spawned > 0:
		var pool: Array = types.keys().filter(func(key: String) -> bool: return key != previous_type)
		if pool.is_empty():
			return
		id = String(pool[rng.randi_range(0, pool.size() - 1)])
	spawned += 1
	items.append({"id": "P%04d" % spawned, "type": id, "route": route, "y": y})
	previous_type = id
	next_spawn_time = game.total_time + rng.randf_range(20.0, 25.0)

func _safe_route(route: int, y: float) -> bool:
	# Check both sides of contact, including stage boundaries and disappearing support.
	for sample_y in [y - 60.0, y, y + 60.0]:
		var stage_number := stages.stage_for_y(float(sample_y))
		stages.ensure_stage(stage_number)
		var progress := stages.progress_in_stage(float(sample_y))
		if not stages.can_enter_route_at(stage_number, route, progress):
			return false
		if stages.route_end_world_y(stage_number, route) > float(sample_y):
			return false
		var pattern := stages.pattern_for_stage(stage_number)
		var height := stages.stage_bottom_y(stage_number) - float(sample_y)
		for slot: Dictionary in pattern.get("action_slots", []):
			if int(slot.route) == route and height >= float(slot.occupancy[0]) - 60.0 and height <= float(slot.occupancy[1]) + 60.0:
				return false
		for slot: Dictionary in pattern.get("bean_slots", []):
			if int(slot.blocked_route) == route and height >= float(slot.occupancy[0]) - 100.0 and height <= maxf(float(slot.occupancy[1]), float(slot.anchor) + 120.0 + 70.0 * float(int(slot.get("count", 1)) - 1)) + 60.0:
				return false
		for slot: Dictionary in pattern.get("rock_slots", []):
			if slot.routes.has(route) and absf(height - float(slot.anchor)) <= 360.0:
				return false
	return true

func snapshot() -> Dictionary:
	return {"active": active.duplicate(true), "spawned": spawned, "collected": collected, "next_spawn_time": next_spawn_time, "items": items.duplicate(true)}

func _draw() -> void:
	for item: Dictionary in items:
		var id := String(item.type)
		var center := Vector2(stages.branch_x_at(int(item.route), float(item.y)), float(item.y) + sin(visual_time * 3.5) * 5.0)
		var color: Color = types[id].color
		draw_circle(center, 22.0, Color(color, 0.25), true, -1.0, true)
		draw_arc(center, 21.0, 0.0, TAU, 40, color, 2.0, true)
		if textures.has(id):
			draw_texture_rect(textures[id], Rect2(center - Vector2(22, 22), Vector2(44, 44)), false)
		elif id == "MAGNET":
			draw_colored_polygon(PackedVector2Array([center + Vector2(-15, 4), center + Vector2(-10, -14), center + Vector2(7, -10), center + Vector2(0, 2)]), color)
			draw_arc(center + Vector2(4, 1), 10.0, 0.0, PI, 20, Color.WHITE, 5.0, true)
			draw_line(center + Vector2(-6, 1), center + Vector2(-6, -7), Color.WHITE, 5.0, true)
			draw_line(center + Vector2(14, 1), center + Vector2(14, -7), Color.WHITE, 5.0, true)
		else:
			draw_circle(center + Vector2(-5, -4), 11.0, color, true, -1.0, true)
			draw_circle(center + Vector2(4, -9), 9.0, color, true, -1.0, true)
			draw_string(ThemeDB.fallback_font, center + Vector2(-14, 15), "×2", HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color.WHITE)
