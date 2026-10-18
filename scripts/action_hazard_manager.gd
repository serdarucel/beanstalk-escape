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
	const HALO := Color("fff1c7")
	static var silhouettes: Dictionary = {}

	func visual_x(y: float) -> float:
		if world_visual != null:
			return float(world_visual.call("_branch_visual_x", route, y))
		return position.x

	func visual_angle(y: float) -> float:
		return atan2(visual_x(y - 8.0) - visual_x(y + 8.0), 16.0)

	func lane_width(y: float) -> float:
		if world_visual != null:
			var neighbor := route + 1 if route < 2 else route - 1
			return absf(float(world_visual.call("_branch_visual_x", neighbor, y)) - visual_x(y))
		return absf(float(Balance.ROUTE_X[1]) - float(Balance.ROUTE_X[0]))

	func visible_bounds(source: Texture2D) -> Rect2:
		if not silhouettes.has(source):
			var image := source.get_image()
			if image.is_compressed():
				image.decompress()
			var bounds := Rect2(image.get_used_rect())
			# A white alpha mask gives both borders a solid color, independent of art RGB.
			for row in image.get_height():
				for column in image.get_width():
					image.set_pixel(column, row, Color(1, 1, 1, image.get_pixel(column, row).a))
			silhouettes[source] = [bounds, ImageTexture.create_from_image(image)]
		return silhouettes[source][0]

	func screen_pixel() -> float:
		var basis := get_global_transform_with_canvas()
		return 1.0 / maxf(minf(basis.x.length(), basis.y.length()), 0.001)

	func part_scale(source: Texture2D, y: float, fraction: float) -> float:
		return lane_width(y) * fraction / maxf(visible_bounds(source).size.x * absf(cos(visual_angle(y))), 1.0)

	func draw_bordered(source: Texture2D, rect: Rect2) -> void:
		visible_bounds(source)
		var mask: Texture2D = silhouettes[source][1]
		var pixel := screen_pixel()
		for layer in [3.2, 2.1]:
			for index in 16:
				var offset: Vector2 = Vector2.from_angle(TAU * float(index) / 16.0) * layer * pixel
				draw_texture_rect(mask, Rect2(rect.position + offset, rect.size), false, HALO if layer == 3.2 else OUTLINE)
		draw_texture_rect(source, rect, false)

	func sprite_size() -> Vector2:
		return texture.get_size() * part_scale(texture, position.y, 0.9)

	func gap_attachment_y(upper: bool) -> float:
		var painted_width := float(world_visual.call("_branch_painted_width", route, position.y)) if world_visual != null else ScaleLock.BRANCH_WIDTH
		var reach := 378.0 * painted_width / 224.0 + 18.0
		return position.y + (-reach if upper else reach)

	func _draw_painted() -> void:
		var y := position.y
		var width := lane_width(y)
		draw_set_transform(Vector2(visual_x(y) - position.x, 0.0), visual_angle(y))
		match kind:
			"K":
				for index in 2:
					var attach_y := gap_attachment_y(index == 0)
					var painted_width := float(world_visual.call("_branch_painted_width", route, attach_y)) if world_visual != null else ScaleLock.BRANCH_WIDTH
					var scale := Vector2(part_scale(parts[index], attach_y, 0.9), painted_width / 224.0)
					draw_set_transform(Vector2(visual_x(attach_y) - position.x, attach_y - y), visual_angle(attach_y))
					var bounds := visible_bounds(parts[index])
					var pivot := Vector2(bounds.get_center().x, 6.0 if index == 0 else 378.0)
					draw_bordered(parts[index], Rect2(-pivot * scale, parts[index].get_size() * scale))
			"M":
				var scale := part_scale(parts[0], y, 0.9)
				var stone_scale := part_scale(parts[2], y, 0.8)
				var stone_center := Vector2(sin(clock * 2.8) * 18.0, 0.0)
				# Keep the stone upright so its opaque width is stable throughout the swing.
				var stone_bounds := visible_bounds(parts[2])
				var stone_rect := Rect2(stone_center - stone_bounds.get_center() * stone_scale, parts[2].get_size() * stone_scale)
				var attachment := stone_center - Vector2(0, stone_bounds.size.y * 0.5 * stone_scale)
				var rope_start := Vector2(-width * 0.35, attachment.y - 53.0)
				var anchor_origin := rope_start - Vector2(312, 232) * scale
				draw_bordered(parts[0], Rect2(anchor_origin, parts[0].get_size() * scale))
				var rope := attachment - rope_start
				var rotation := rope.angle() - PI * 0.5
				var basis := Transform2D(visual_angle(y), Vector2(visual_x(y) - position.x, 0))
				draw_set_transform(basis * rope_start, visual_angle(y) + rotation)
				var rope_bounds := visible_bounds(parts[1])
				var rope_width := maxf(4.5, 3.0 * screen_pixel())
				var rope_scale := Vector2(rope_width / maxf(rope_bounds.size.x, 1.0), rope.length() / maxf(rope_bounds.size.y, 1.0))
				draw_bordered(parts[1], Rect2(-Vector2(rope_bounds.get_center().x, rope_bounds.position.y) * rope_scale, parts[1].get_size() * rope_scale))
				draw_set_transform(Vector2(visual_x(y) - position.x, 0.0), visual_angle(y))
				draw_bordered(parts[2], stone_rect)
			_:
				var size := sprite_size()
				var rect := Rect2(-visible_bounds(texture).get_center() * (size / texture.get_size()), size)
				draw_bordered(texture, rect)
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
			var painted_width := float(hazard.world_visual.call("_branch_painted_width", hazard.route, y)) if hazard.world_visual != null else ScaleLock.BRANCH_WIDTH
			var half_width := painted_width * 0.5 + 5.0
			left.append(center - normal * half_width)
			right.append(center + normal * half_width)
		right.reverse()
		left.append_array(right)
		draw_colored_polygon(left, Color.WHITE)
