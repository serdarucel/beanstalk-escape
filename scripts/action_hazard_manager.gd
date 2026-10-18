class_name ActionHazardManager
extends Node2D

var player: PlayerController
var stages: StageManager
var hazards: Array[ActionHazard] = []
var loaded_stages: Dictionary = {}
var active_center_stage := -1
var hit_ids: Dictionary = {}
var cleared_ids: Dictionary = {}
var hit_count := 0
var cleared_count := 0
var previous_player_y := 0.0

func setup(target: PlayerController, stage_manager: StageManager) -> void:
	player = target
	stages = stage_manager
	process_physics_priority = 1 # Evaluate after the player's movement and action clock.
	previous_player_y = player.global_position.y

func reset_run() -> void:
	for hazard in hazards:
		if is_instance_valid(hazard):
			hazard.queue_free()
	hazards.clear()
	loaded_stages.clear()
	hit_ids.clear()
	cleared_ids.clear()
	hit_count = 0
	cleared_count = 0
	active_center_stage = -1
	sync_after_player_teleport()

func sync_after_player_teleport() -> void:
	if player == null or stages == null:
		return
	previous_player_y = player.global_position.y
	refresh_active_window(true)

func refresh_active_window(force := false) -> void:
	if player == null or stages == null:
		return
	var center := stages.stage_for_y(player.global_position.y)
	if not force and center == active_center_stage:
		return
	active_center_stage = center
	for index in range(hazards.size() - 1, -1, -1):
		var hazard := hazards[index]
		if not is_instance_valid(hazard):
			hazards.remove_at(index)
			continue
		if hazard.campaign_stage >= 0 and (hazard.campaign_stage < center or hazard.campaign_stage > center + 2):
			hazards.remove_at(index)
			hazard.queue_free()
	for stage_value in loaded_stages.keys():
		if int(stage_value) < center or int(stage_value) > center + 2:
			loaded_stages.erase(stage_value)
	for stage_number in range(maxi(stages.first_stage, center), center + 3):
		if loaded_stages.has(stage_number):
			continue
		for slot: Dictionary in stages.pattern_for_stage(stage_number).get("action_slots", []):
			var hazard := _spawn(String(slot.id), String(slot.kind), String(slot["class"]), int(slot.route), stages.stage_bottom_y(stage_number) - float(slot.anchor))
			hazard.campaign_stage = stage_number
		loaded_stages[stage_number] = true

func _spawn(id: String, kind: String, action_class: String, route: int, anchor_y: float) -> ActionHazard:
	var hazard := ActionHazard.new()
	hazard.hazard_id = id
	hazard.kind = kind
	hazard.action_class = action_class
	hazard.route = route
	hazard.position = Vector2(stages.branch_x_at(route, anchor_y), anchor_y)
	hazard.z_index = player.z_index + (10 if action_class == "HIGH" else -1)
	hazard.world_visual = get_parent().get_node_or_null("World")
	var names: Array = {
		"THORN": ["obstacle_thorn_ring"], "ARCH": ["obstacle_low_arch"],
		"WALL": ["obstacle_low_arch"], "WEB": ["obstacle_web_strand"],
		"K": ["obstacle_vine_gap_upper", "obstacle_vine_gap_lower"],
		"M": ["obstacle_hanging_anchor", "obstacle_hanging_rope", "obstacle_hanging_stone"],
	}.get(kind, [])
	for asset_name: String in names:
		var path := "res://assets/art/eglence/%s.png" % asset_name
		hazard.parts.append(load(path) as Texture2D if ResourceLoader.exists(path) else null)
	if not hazard.parts.is_empty() and not hazard.parts.has(null):
		hazard.texture = hazard.parts[0]
	if kind == "K" and hazard.texture != null:
		var gap := GapSky.new()
		gap.hazard = hazard
		gap.show_behind_parent = true
		hazard.add_child(gap)
	hazard.add_to_group("run_transient")
	add_child(hazard)
	hazards.append(hazard)
	return hazard

func _physics_process(delta: float) -> void:
	var game := get_parent() as GameManager
	if player == null or game == null or game.app_state != GameManager.AppState.PLAYING:
		return
	if game.tutorial_active:
		previous_player_y = player.global_position.y
		return
	# Sweep before retiring the previous stage, including a fast boundary crossing.
	var current_y := player.global_position.y
	for hazard in hazards:
		if not is_instance_valid(hazard):
			continue
		hazard.visible = absf(hazard.position.y - current_y) <= 1000.0
		hazard.clock += delta
		if hazard.visible:
			hazard.queue_redraw()
		if hit_ids.has(hazard.hazard_id) or cleared_ids.has(hazard.hazard_id):
			continue
		if not player.occupies_route(hazard.route):
			continue
		if minf(previous_player_y, current_y) > hazard.position.y + 18.0 or maxf(previous_player_y, current_y) < hazard.position.y - 18.0:
			continue
		var correct := player.is_airborne() if hazard.action_class == "LOW" else player.is_hugging()
		if correct:
			cleared_ids[hazard.hazard_id] = true
			cleared_count += 1
		else:
			hit_ids[hazard.hazard_id] = true
			hit_count += 1
			player.apply_rock_hit(hazard.hazard_id)
			game.on_rock_hit()
	previous_player_y = player.global_position.y
	refresh_active_window()

func snapshot() -> Dictionary:
	var items := []
	for hazard in hazards:
		if not is_instance_valid(hazard):
			continue
		var ahead := player.global_position.y - hazard.position.y
		if ahead >= 0.0 and ahead <= 900.0:
			items.append({"id": hazard.hazard_id, "kind": hazard.kind, "class": hazard.action_class, "route": hazard.route, "y": hazard.position.y})
	return {"active": hazards.filter(func(hazard): return is_instance_valid(hazard)).size(), "cleared": cleared_count, "hits": hit_count, "items": items}

class ActionHazard extends Node2D:
	var hazard_id := ""
	var kind := ""
	var action_class := ""
	var route := 1
	var campaign_stage := -1
	var clock := 0.0
	var texture: Texture2D
	var parts: Array[Texture2D] = []
	var world_visual: Node2D
	const OUTLINE := Color("302820")

	func visual_x(y: float) -> float:
		if world_visual != null:
			return float(world_visual.call("_branch_visual_x", route, y))
		return position.x

	func visual_angle(y: float) -> float:
		return atan2(visual_x(y - 8.0) - visual_x(y + 8.0), 16.0)

	func lane_width(y: float) -> float:
		if world_visual != null:
			return float(world_visual.call("_branch_painted_width", route, y))
		return ScaleLock.BRANCH_WIDTH

	func sprite_size() -> Vector2:
		var width := lane_width(position.y) * 1.1
		if kind == "WEB":
			width = maxf(width, 18.0 * texture.get_width() / texture.get_height())
		return texture.get_size() * (width / texture.get_width())

	func gap_attachment_y(upper: bool) -> float:
		var reach := 378.0 * lane_width(position.y) / 224.0 + 18.0
		return position.y + (-reach if upper else reach)

	func _draw_painted() -> void:
		var y := position.y
		var width := lane_width(y)
		draw_set_transform(Vector2(visual_x(y) - position.x, 0.0), visual_angle(y))
		match kind:
			"K":
				for index in 2:
					var attach_y := gap_attachment_y(index == 0)
					var scale := lane_width(attach_y) / 224.0
					draw_set_transform(Vector2(visual_x(attach_y) - position.x, attach_y - y), visual_angle(attach_y))
					var pivot := Vector2(128.0, 6.0 if index == 0 else 378.0)
					draw_texture_rect(parts[index], Rect2(-pivot * scale, parts[index].get_size() * scale), false)
			"M":
				var scale := width / 224.0
				var knot := Vector2(-width * 0.5, -53.0)
				draw_texture_rect(parts[0], Rect2(knot - Vector2(310, 130) * scale, parts[0].get_size() * scale), false)
				var rope_start := knot + Vector2(2, 102) * scale
				var stone_scale := width * 0.85 / 256.0
				var stone_center := Vector2(sin(clock * 2.8) * 18.0, 0.0)
				var rotation := (stone_center - rope_start).angle() - PI * 0.5
				var attachment := stone_center + (Vector2(0, -99) * stone_scale).rotated(rotation)
				var rope := attachment - rope_start
				var basis := Transform2D(visual_angle(y), Vector2(visual_x(y) - position.x, 0))
				draw_set_transform(basis * rope_start, visual_angle(y) + rotation)
				# Repeat the authored 128 px period without stretching the rope.
				var rope_width := 4.5
				var tile_height := 128.0 * rope_width / 48.0
				var cursor := 0.0
				while cursor < rope.length():
					var height := minf(tile_height, rope.length() - cursor)
					draw_texture_rect_region(parts[1], Rect2(-rope_width * 0.5, cursor, rope_width, height), Rect2(0, 0, 48, height * 48.0 / rope_width))
					cursor += height
				draw_set_transform(basis * attachment, visual_angle(y) + rotation)
				draw_texture_rect(parts[2], Rect2(-Vector2(128, 29) * stone_scale, parts[2].get_size() * stone_scale), false)
			_:
				var size := sprite_size()
				var rect := Rect2(-size * 0.5, size)
				if kind == "WEB":
					draw_texture_rect(texture, Rect2(rect.position + Vector2(0, 4), size), false, Color(0, 0, 0, 0.5))
					for offset in [Vector2(-1.5, 0), Vector2(1.5, 0), Vector2(0, -1.5), Vector2(0, 1.5)]:
						draw_texture_rect(texture, Rect2(rect.position + offset, size), false, OUTLINE)
				elif kind in ["THORN", "ARCH", "WALL"]:
					for layer in range(3, 0, -1):
						_oval(Vector2(0, size.y * 0.3 + 3), Vector2(size.x * 0.46 + layer, 4 + layer), Color(0.03, 0.04, 0.02, 0.14))
				draw_texture_rect(texture, rect, false)
		draw_set_transform(Vector2.ZERO)

	func _draw() -> void:
		var swing := Vector2(sin(clock * 2.8) * 18.0, 0.0) if kind == "M" else Vector2.ZERO
		if texture != null:
			_draw_painted()
			return
		match kind:
			"THORN":
				var ring := PackedVector2Array()
				for i in range(14):
					var x := -35.0 + float(i) * 70.0 / 13.0
					ring.append(Vector2(x, -11.0 if i % 2 == 0 else -4.0))
				for i in range(13, -1, -1):
					var x := -35.0 + float(i) * 70.0 / 13.0
					ring.append(Vector2(x, 11.0 if i % 2 == 1 else 4.0))
				draw_colored_polygon(ring, Color("944536"))
				ring.append(ring[0])
				draw_polyline(ring, OUTLINE, 2.5, true)
			"K":
				_oval(Vector2.ZERO, Vector2(32, 25), Color("b9dfeb"))
				for side in [-1.0, 1.0]:
					for i in range(6):
						var x := -24.0 + float(i) * 9.0
						draw_line(Vector2(x, side * 29.0), Vector2(x + 3.0, side * (17.0 + float(i % 3) * 3.0)), Color("b5d984"), 3.0, true)
			"ARCH":
				_oval(Vector2(0, 9), Vector2(39, 12), Color(0.05, 0.08, 0.05, 0.65))
				var arch := PackedVector2Array([Vector2(-40, 16), Vector2(-38, -7), Vector2(-25, -24), Vector2(0, -30), Vector2(25, -24), Vector2(38, -7), Vector2(40, 16)])
				draw_polyline(arch, OUTLINE, 13.0, true)
				draw_polyline(arch, Color("817b65"), 8.0, true)
			"WEB":
				draw_line(Vector2(-38, 9), Vector2(38, 9), Color(0.03, 0.06, 0.04, 0.65), 4.0, true)
				for y in [-5.0, -1.0]:
					draw_line(Vector2(-38, y), Vector2(38, y), Color("e5edf1"), 1.5, true)
				draw_line(Vector2(-13, -8), Vector2(-13, 2), Color.WHITE, 1.0, true)
				draw_line(Vector2(-18, -3), Vector2(-8, -3), Color.WHITE, 1.0, true)
			"M":
				draw_line(Vector2(-39, -53), Vector2(-13, -53), Color("6b8546"), 7.0, true)
				draw_line(Vector2(-23, -53), swing, OUTLINE, 4.0, true)
				draw_line(Vector2(-23, -53), swing, Color("b7a17a"), 2.0, true)
				draw_circle(swing, 19.0, OUTLINE)
				draw_circle(swing, 16.5, Color("858c90"))
				draw_circle(swing + Vector2(-5, -5), 5.0, Color("a3a8a8"))

	func _oval(center: Vector2, radii: Vector2, color: Color) -> void:
		var points := PackedVector2Array()
		for i in range(32):
			var angle := TAU * float(i) / 32.0
			points.append(center + Vector2(cos(angle), sin(angle)) * radii)
		draw_colored_polygon(points, color)

# The back buffer contains the sky before the solid stalk is painted. Sampling
# it opens only the visual gap; support and collision data remain untouched.
class GapSky extends Node2D:
	var hazard: ActionHazard

	func _ready() -> void:
		var shader := Shader.new()
		shader.code = "shader_type canvas_item; uniform sampler2D sky : hint_screen_texture, repeat_disable, filter_linear; void fragment() { COLOR = texture(sky, SCREEN_UV); }"
		var sky_material := ShaderMaterial.new()
		sky_material.shader = shader
		material = sky_material

	func _draw() -> void:
		var left := PackedVector2Array()
		var right := PackedVector2Array()
		var top := hazard.gap_attachment_y(true)
		var bottom := hazard.gap_attachment_y(false)
		for index in 33:
			var y := lerpf(top, bottom, float(index) / 32.0)
			var center := Vector2(hazard.visual_x(y) - hazard.position.x, y - hazard.position.y)
			var normal := Vector2.RIGHT.rotated(hazard.visual_angle(y))
			var half_width := hazard.lane_width(y) * 0.5 + 5.0
			left.append(center - normal * half_width)
			right.append(center + normal * half_width)
		right.reverse()
		left.append_array(right)
		draw_colored_polygon(left, Color.WHITE)
