class_name RockHazard
extends Node2D

const ATLAS := preload("res://assets/art/hazards/rock_fire_atlas.png")
const CELL_SIZE := Vector2(512.0, 512.0)

var hazard_id := ""
var kind := "S"
var routes: Array[int] = [1]
var anchor_y := 0.0
var released := false
var threat_time := 0.0
var previous_position := Vector2.ZERO
var stages: StageManager
var sprite := Sprite2D.new()
var split_wall_sprites: Array[Sprite2D] = []
var redraw_count := 0
var last_hit := {}

func _swing_vine_x(route: int, at_y: float) -> float:
	var offset := ScaleLock.vine_visual_offset(route, at_y) if stages != null and stages.stage_for_y(at_y) > 2 else 0.0
	return float(Balance.ROUTE_X[route]) + offset

func _swing_point(s: float) -> Dictionary:
	var y_r := anchor_y - 110.0
	var a := _swing_vine_x(routes[0], y_r)
	var b := _swing_vine_x(routes[1], y_r)
	var length := 170.0
	var half_span := (b - a) * 0.5
	var theta := asin(half_span / length)
	# The vertical leg keeps both endpoints at y_r with a 170 px rope.
	var pivot := Vector2((a + b) * 0.5, y_r - sqrt(length * length - half_span * half_span))
	var angle := lerpf(-theta, theta, s)
	return {"pivot": pivot, "center": pivot + length * Vector2(sin(angle), cos(angle)), "angle": angle}

func _swing_progress() -> float:
	if not released:
		return 0.0
	var cycle := fposmod(threat_time, 2.8)
	var t := cycle if cycle < 1.0 else (1.0 if cycle < 1.4 else (2.4 - cycle if cycle < 2.4 else 0.0))
	return smoothstep(0.0, 1.0, clampf(t, 0.0, 1.0))

func _update_swing() -> void:
	var swing := _swing_point(_swing_progress())
	position = swing.center
	sprite.position = Vector2.ZERO
	sprite.rotation = -float(swing.angle)
	queue_redraw()

func setup(id: String, recipe_kind: String, lane_values: Array, at_y: float, stage_manager: StageManager) -> void:
	hazard_id = id
	kind = recipe_kind
	routes.clear()
	for lane in lane_values:
		routes.append(int(lane))
	anchor_y = at_y
	stages = stage_manager
	var cell := {"S": Vector2i(0, 0), "R": Vector2i(1, 0), "F": Vector2i(2, 0), "WALL": Vector2i(0, 1), "M": Vector2i(1, 1)}.get(kind, Vector2i.ZERO) as Vector2i
	var texture := AtlasTexture.new()
	texture.atlas = ATLAS
	texture.region = Rect2(Vector2(cell) * CELL_SIZE, CELL_SIZE)
	sprite.texture = texture
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	sprite.scale = Vector2.ONE * (0.26 if kind == "WALL" else (0.23 if kind == "S" else 0.18))
	add_child(sprite)
	if kind == "WALL" and routes.size() > 1 and absi(routes[0] - routes[-1]) > 1:
		split_wall_sprites.append(sprite)
		for index in range(1, routes.size()):
			var arch := Sprite2D.new()
			arch.texture = sprite.texture
			arch.texture_filter = sprite.texture_filter
			arch.scale = sprite.scale
			add_child(arch)
			split_wall_sprites.append(arch)
	_reset_position()
	_update_vine_visual_offset()
	previous_position = global_position
	queue_redraw()

func _reset_position() -> void:
	var route := routes[0] if not routes.is_empty() else 1
	var x := stages.branch_x_at(route, anchor_y) if stages != null else float(Balance.ROUTE_X[route])
	match kind:
		"R", "F": position = Vector2(x, anchor_y - 180.0)
		"M": _update_swing()
		"WALL": position = Vector2((float(Balance.ROUTE_X[routes[0]]) + float(Balance.ROUTE_X[routes[-1]])) * 0.5, anchor_y - 105.0)
		_: position = Vector2(x, anchor_y - 100.0)

func advance_threat_clock(delta: float, time_active: bool, player_y: float) -> void:
	previous_position = global_position
	var was_released := released
	if not released and player_y <= anchor_y:
		released = true
	if not released:
		if kind == "M":
			_update_swing()
			return
		sprite.rotation = sin(Time.get_ticks_msec() * 0.022) * (0.045 if kind == "F" else 0.015)
		return
	if released != was_released:
		queue_redraw()
	var scale := Balance.TIME_WINGS_SLOW_SCALE if time_active else 1.0
	threat_time += delta * scale
	match kind:
		"R":
			position.y += Balance.ROCK_ROLL_SPEED * delta * scale
			sprite.rotation += Balance.ROCK_ROLL_SPEED * delta * scale / 26.0
		"F":
			position.y += Balance.ROCK_FALL_SPEED * delta * scale
			sprite.rotation += 1.8 * delta * scale
		"M":
			_update_swing()
	_update_vine_visual_offset()

func _update_vine_visual_offset() -> void:
	if kind == "M":
		sprite.position = Vector2.ZERO
		return
	if not split_wall_sprites.is_empty():
		for index in split_wall_sprites.size():
			var route := routes[index]
			var vine_offset := ScaleLock.vine_visual_offset(route, global_position.y) if stages != null and stages.stage_for_y(global_position.y) > 2 else 0.0
			split_wall_sprites[index].position.x = float(Balance.ROUTE_X[route]) + vine_offset - position.x
		return
	if sprite == null or stages == null or stages.stage_for_y(global_position.y) <= 2 or routes.is_empty():
		if sprite != null: sprite.position.x = 0.0
		return
	var offset := ScaleLock.vine_visual_offset(routes[0], global_position.y)
	if kind == "WALL" and routes.size() > 1:
		offset = (ScaleLock.vine_visual_offset(routes[0], global_position.y) + ScaleLock.vine_visual_offset(routes[-1], global_position.y)) * 0.5
	sprite.position.x = offset

func collision_centers() -> Array[Vector2]:
	var result: Array[Vector2] = []
	if kind == "WALL":
		for route in routes:
			result.append(Vector2(float(Balance.ROUTE_X[route]), global_position.y))
	else:
		result.append(global_position)
	return result

func collision_radius() -> float:
	return 31.0 if kind == "M" else (24.0 if kind in ["R", "F"] else 42.0)

func _draw() -> void:
	redraw_count += 1
	if kind == "M":
		var swing := _swing_point(_swing_progress())
		var pivot: Vector2 = swing.pivot
		var root := Vector2(_swing_vine_x(routes[0], pivot.y), pivot.y)
		var direction := 1.0 if pivot.x >= root.x else -1.0
		root.x -= direction * 10.0
		var p := pivot - position
		var v := root - position
		var control := (v + p) * 0.5 + Vector2(0.0, -16.0)
		var centers := PackedVector2Array()
		var normals := PackedVector2Array()
		var outline := PackedVector2Array()
		var branch := PackedVector2Array()
		var highlight := PackedVector2Array()
		var shadow := PackedVector2Array()
		# Thirteen Bezier samples, with normals pointing toward the upper edge.
		for index in 13:
			var t := float(index) / 12.0
			# A quadratic Bezier uses the same control point for both lerps.
			var center := v.lerp(control, t).lerp(control.lerp(p, t), t)
			var tangent := (control - v).lerp(p - control, t).normalized()
			var normal := Vector2(tangent.y, -tangent.x) * direction
			var half_width := lerpf(11.0, 5.0, t)
			centers.append(center)
			normals.append(normal)
			outline.append(center + normal * (half_width + 3.0))
			branch.append(center + normal * half_width)
			highlight.append(center + normal * half_width)
			shadow.append(center - normal * half_width * 0.65)
		for index in range(12, -1, -1):
			var center := centers[index]
			var normal := normals[index]
			var half_width := lerpf(11.0, 5.0, float(index) / 12.0)
			outline.append(center - normal * (half_width + 3.0))
			branch.append(center - normal * half_width)
			highlight.append(center + normal * half_width * 0.3)
			shadow.append(center - normal * half_width)
		draw_polygon(outline, PackedColorArray([Color("0f370d")]))
		draw_polygon(branch, PackedColorArray([Color("7ebf1b")]))
		draw_polygon(highlight, PackedColorArray([Color("91cd21")]))
		draw_polygon(shadow, PackedColorArray([Color("519b15")]))
		var leaf_base := centers[6] + normals[6] * 8.0
		var leaf_axis := (normals[6] + Vector2(direction * 0.5, 0.0)).normalized()
		var leaf_side := Vector2(-leaf_axis.y, leaf_axis.x)
		var leaf_center := leaf_base + leaf_axis * 7.0
		var leaf_outline := PackedVector2Array()
		var leaf := PackedVector2Array()
		for index in 12:
			var angle := TAU * float(index) / 12.0
			leaf_outline.append(leaf_center + leaf_axis * cos(angle) * 8.5 + leaf_side * sin(angle) * 5.5)
			leaf.append(leaf_center + leaf_axis * cos(angle) * 7.0 + leaf_side * sin(angle) * 4.0)
		draw_polygon(leaf_outline, PackedColorArray([Color("0f370d")]))
		draw_polygon(leaf, PackedColorArray([Color("91cd21")]))
		var rope_end := p.normalized() * 20.0
		draw_line(p, rope_end, Color("0f370d"), 9.0, true)
		draw_line(p, rope_end, Color("7ebf1b"), 5.0, true)
		var rope_direction := (rope_end - p).normalized()
		var rope_cross := Vector2(-rope_direction.y, rope_direction.x)
		var twist_direction := (rope_cross + rope_direction).normalized()
		for index in range(1, int(p.distance_to(rope_end) / 14.0) + 1):
			var twist_center := p + rope_direction * float(index) * 14.0
			draw_line(twist_center - twist_direction * 2.5, twist_center + twist_direction * 2.5, Color("91cd21"), 2.0, true)
		draw_circle(p, 9.0, Color("0f370d"))
		draw_circle(p, 6.5, Color("7ebf1b"))
	if not released:
		var warning := Vector2(70.0, -46.0) if kind == "M" else Vector2(0.0, -46.0)
		draw_circle(warning, 11.0, Color("ffd55c"))
		draw_line(warning + Vector2(0.0, -16.0), warning + Vector2(0.0, -6.0), Color("142b39"), 3.0, true)
		if kind == "M":
			var arc := PackedVector2Array()
			for index in 25:
				var point: Vector2 = _swing_point(float(index) / 24.0).center
				arc.append(point - position + Vector2(0.0, 42.0))
			draw_polyline(arc, Color(1.0, 0.82, 0.28, 0.65), 4.0, true)
	if kind in ["R", "M"] and released:
		for index in 3:
			draw_circle(Vector2(-34.0 - index * 10.0, 24.0 + index * 3.0), 5.0 - index, Color(0.72, 0.62, 0.42, 0.45))

func snapshot() -> Dictionary:
	var screen := get_global_transform_with_canvas().origin
	var result := {"id": hazard_id, "kind": kind, "routes": routes.duplicate(), "anchor_y": anchor_y, "released": released, "position": {"x": global_position.x, "y": global_position.y}, "threat_time": threat_time, "screen": {"x": screen.x, "y": screen.y}, "last_hit": last_hit.duplicate(true)}
	if kind == "M":
		var swing := _swing_point(_swing_progress())
		var pivot: Vector2 = get_parent().get_global_transform() * Vector2(swing.pivot)
		result["pivot"] = {"x": pivot.x, "y": pivot.y}
		result["angle"] = swing.angle
	return result
