extends Node2D

const TRUNK_TEXTURE := preload("res://assets/art/world/v4/trunk_tile.png")
const LANE_TEXTURE := preload("res://assets/art/world/v4/vine_tile.png")
const CROWN_TEXTURE := preload("res://assets/art/world/v4/crown.png")
const SKY_VISUAL := preload("res://scripts/world_sky_visual.gd")
const SKY_TOP := Color("43b8ef")
const SKY_BOTTOM := Color("86dafa")
# v4_manifest.json: two source pixels per world unit, including transparent gutters.
const SOURCE_SCALE := 0.5
const TRUNK_BODY_WIDTH := 96.0
const VINE_BODY_WIDTH := 64.0
const TRUNK_TILE_HEIGHT := 128.0
const LANE_TILE_HEIGHT := 91.5
const CROWN_ANCHOR := Vector2(580.0, 116.0) * SOURCE_SCALE
const CROWN_VINE_EXIT := 260.0 * SOURCE_SCALE
const CROWN_SIZE := Vector2(1150.0, 360.0) * SOURCE_SCALE
# Retained for the endless renderer's inherited entry points.
const SURFACE_CACHE_MARGIN_PX := 0.0
const SURFACE_SHADER := """
shader_type canvas_item;
render_mode unshaded;
uniform float sunset_mix : hint_range(0.0, 1.0) = 0.0;
void fragment() {
    vec4 pigment = texture(TEXTURE, UV);
    pigment.rgb *= mix(vec3(1.0), vec3(1.04, 1.0, 0.94), sunset_mix);
    COLOR = pigment;
}
"""

@onready var player: PlayerController = get_parent().get_node_or_null("Player") as PlayerController
@onready var stages: StageManager = get_parent().get_node_or_null("StageManager") as StageManager

var redraw_count := 0
var branch_point_count := 0
var qa_storm_background := false
var qa_support_mask := false
var qa_support_mask_include_outline := false
var qa_sky_only := false
var cached_camera_top := INF
var cached_visible_size := Vector2.ZERO
var cached_first_stage := -1
var cached_last_stage := -1
var sky_visual: Node2D
var surface_material: ShaderMaterial
var dead_end_texture: Texture2D
var crown_origins: Array[Vector2] = []

func _ready() -> void:
	var tip_path := "res://assets/art/eglence/obstacle_dead_end_tip.png"
	if ResourceLoader.exists(tip_path):
		dead_end_texture = load(tip_path) as Texture2D
	var surface_shader := Shader.new()
	surface_shader.code = SURFACE_SHADER
	surface_material = ShaderMaterial.new()
	surface_material.shader = surface_shader
	material = surface_material
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	sky_visual = SKY_VISUAL.new()
	sky_visual.name = "Sky"
	sky_visual.z_index = -100
	sky_visual.setup(player, stages)
	add_child(sky_visual)
	var sky_copy := BackBufferCopy.new()
	sky_copy.name = "GapSkyBuffer"
	sky_copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	sky_copy.z_index = -99
	add_child(sky_copy)
	cached_camera_top = _camera_top()
	cached_visible_size = _visible_size()
	queue_redraw()
	set_process(true)

func _process(_delta: float) -> void:
	if player != null and stages != null:
		var sunset: float = sky_visual.sunset_mix_at(stages.stage_for_y(player.global_position.y), stages.progress_in_stage(player.global_position.y))
		surface_material.set_shader_parameter("sunset_mix", sunset)
	var current_camera_top := _camera_top()
	var current_visible_size := _visible_size()
	var first := stages.first_stage if stages != null else -1
	var last := stages.last_stage if stages != null else -1
	# Four clipped strips are cheap enough to follow the viewport without overscan.
	if current_visible_size != cached_visible_size or current_camera_top != cached_camera_top or first != cached_first_stage or last != cached_last_stage:
		cached_camera_top = current_camera_top
		cached_visible_size = current_visible_size
		cached_first_stage = first
		cached_last_stage = last
		queue_redraw()

func _visible_size() -> Vector2:
	var zoom := Vector2.ONE
	if player != null:
		var camera := player.get_node_or_null("Camera2D") as Camera2D
		if camera != null:
			zoom = camera.zoom
	return get_viewport_rect().size / zoom

func _camera_top() -> float:
	var result := player.global_position.y - ScaleLock.CHARACTER_REFERENCE_Y if player != null else -270.0
	if player != null:
		var camera := player.get_node_or_null("Camera2D") as Camera2D
		if camera != null:
			result = camera.get_screen_center_position().y - _visible_size().y * 0.5
	return result

func _draw() -> void:
	redraw_count += 1
	branch_point_count = 0
	if qa_sky_only:
		return
	var camera_top := cached_camera_top if not is_inf(cached_camera_top) else _camera_top()
	_collect_crowns()
	_draw_trunk(camera_top)
	_draw_visible_stage_branches(camera_top)
	if not qa_support_mask:
		_draw_crowns(camera_top)

func _collect_crowns() -> void:
	crown_origins.clear()
	if stages == null:
		return
	# Keep resident anchors for absolute texture phase even when a crown is offscreen.
	for stage_number in range(maxi(3, stages.first_stage), stages.last_stage + 1):
		crown_origins.append(Vector2(-CROWN_ANCHOR.x, stages.stage_bottom_y(stage_number) - CROWN_ANCHOR.y))

func _draw_trunk(camera_top: float) -> void:
	_draw_tiled_strip(TRUNK_TEXTURE, 0.0, camera_top, camera_top + _visible_size().y, 0.0)

func _trunk_center_x(_world_y: float) -> float:
	return 0.0

func _trunk_half_width(_world_y: float) -> float:
	return TRUNK_BODY_WIDTH * 0.5

func _draw_stage_branches(camera_top: float) -> void:
	_draw_visible_stage_branches(camera_top)

func _draw_visible_stage_branches(camera_top: float) -> void:
	var visible_bottom := camera_top + _visible_size().y
	var visible_top := camera_top
	# The early gameplay lanes remain untouched; the v4 visual already has three vines.
	var early_top := maxf(visible_top, _stage_3_bottom_y())
	if stages == null:
		early_top = visible_top
	if visible_bottom > early_top:
		for route in 3:
			_draw_vine_span(route, early_top, visible_bottom)
	if stages == null:
		return
	for route in 3:
		# Union touching support intervals before clipping or building geometry.
		# A stage/support boundary is not a botanical endpoint.
		var spans: Array[Vector3] = []
		for stage_number in range(maxi(3, stages.first_stage), stages.last_stage + 1):
			var bottom := stages.stage_bottom_y(stage_number)
			var length := stages.stage_length(stage_number)
			if bottom < visible_top or bottom - length > visible_bottom:
				continue
			for segment: Array in stages.support_segments(stage_number, route):
				spans.append(Vector3(bottom - float(segment[0]) * length, bottom - float(segment[1]) * length, stage_number))
		spans.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.x > b.x)
		var joined: Array[Vector3] = []
		for span in spans:
			if not joined.is_empty() and span.x >= joined[joined.size() - 1].y - 0.01:
				joined[joined.size() - 1].y = minf(joined[joined.size() - 1].y, span.y)
			else:
				joined.append(span)
		for span in joined:
			var start_y := minf(span.x, visible_bottom)
			var end_y := maxf(span.y, visible_top)
			if start_y <= end_y:
				continue
			var stage_number := int(span.z)
			var bottom := stages.stage_bottom_y(stage_number)
			var length := stages.stage_length(stage_number)
			_draw_branch_segment(stage_number, route, (bottom - start_y) / length, (bottom - end_y) / length, is_equal_approx(start_y, span.x), is_equal_approx(end_y, span.y))

func _draw_branch_segment(stage_number: int, route: int, start_progress: float, end_progress: float, _show_start_tip := true, show_end_tip := true) -> void:
	if end_progress <= start_progress:
		return
	var stage_bottom := stages.stage_bottom_y(stage_number)
	var length := stages.stage_length(stage_number)
	var bottom := stage_bottom - start_progress * length
	var top := stage_bottom - end_progress * length
	_draw_vine_span(route, top, bottom)
	if show_end_tip and not qa_support_mask:
		_draw_branch_tip_detail(Vector2(_branch_visual_x(route, top), top), Vector2.UP, route, false)

func _branch_visual_x(route: int, world_y: float) -> float:
	return float(Balance.ROUTE_X[route]) + ScaleLock.vine_visual_offset(route, world_y)

func _branch_painted_width(_route: int, _world_y: float) -> float:
	return VINE_BODY_WIDTH

func _draw_vine_span(route: int, top: float, bottom: float) -> void:
	# The crown supplies the wraps above its exit. Drawing a straight stripe there
	# would run through the bough and double the painted attachment.
	var spans: Array[Vector2] = [Vector2(top, bottom)]
	for origin in crown_origins:
		var exit_y := origin.y + CROWN_VINE_EXIT
		var clipped: Array[Vector2] = []
		for span in spans:
			if origin.y >= span.y or exit_y <= span.x:
				clipped.append(span)
				continue
			if span.x < origin.y:
				clipped.append(Vector2(span.x, origin.y))
			if span.y > exit_y:
				clipped.append(Vector2(exit_y, span.y))
		spans = clipped
	for span in spans:
		var phase_origin := 0.0
		var nearest_exit := -INF
		for origin in crown_origins:
			var exit_y := origin.y + CROWN_VINE_EXIT
			if exit_y <= span.x and exit_y > nearest_exit:
				nearest_exit = exit_y
				phase_origin = exit_y
		_draw_tiled_strip(LANE_TEXTURE, float(Balance.ROUTE_X[route]), span.x, span.y, phase_origin)
		branch_point_count += 2

func _draw_tiled_strip(texture: Texture2D, center_x: float, top: float, bottom: float, phase_origin: float) -> void:
	if bottom <= top:
		return
	var world_width := float(texture.get_width()) * SOURCE_SCALE
	var destination := Rect2(center_x - world_width * 0.5, top, world_width, bottom - top)
	if qa_support_mask:
		var body_width := TRUNK_BODY_WIDTH if texture == TRUNK_TEXTURE else VINE_BODY_WIDTH
		draw_rect(Rect2(center_x - body_width * 0.5, top, body_width, bottom - top), Color.WHITE)
		return
	# Fold the starting phase to avoid precision loss late in an endless run.
	var source_y := fposmod((top - phase_origin) / SOURCE_SCALE, float(texture.get_height()))
	var source := Rect2(0.0, source_y, float(texture.get_width()), (bottom - top) / SOURCE_SCALE)
	draw_texture_rect_region(texture, destination, source, Color.WHITE, false, false)

func _draw_crowns(camera_top: float) -> void:
	var camera_bottom := camera_top + _visible_size().y
	for origin in crown_origins:
		var top := maxf(camera_top, origin.y)
		var bottom := minf(camera_bottom, origin.y + CROWN_SIZE.y)
		if bottom <= top:
			continue
		var destination := Rect2(origin.x, top, CROWN_SIZE.x, bottom - top)
		var source := Rect2(0.0, (top - origin.y) / SOURCE_SCALE, float(CROWN_TEXTURE.get_width()), (bottom - top) / SOURCE_SCALE)
		draw_texture_rect_region(CROWN_TEXTURE, destination, source)

func _is_dead_end_tip(route: int, world_y: float) -> bool:
	if stages == null:
		return false
	# A closed support window starts a real dead end. Stage/cache clipping
	# and the upper edge of the resident scene never qualify on their own.
	var stage_number := stages.stage_for_y(world_y)
	for number in range(maxi(stages.first_stage, stage_number - 1), mini(stages.last_stage, stage_number + 1) + 1):
		for window: Dictionary in stages.pattern_for_stage(number).get("support_windows", []):
			var endpoint := stages.stage_bottom_y(number) - float(window.start_progress) * stages.stage_length(number)
			if not window.supports.has(route) and absf(endpoint - world_y) < 0.1:
				return true
	return false

func _draw_branch_tip_detail(base: Vector2, direction: Vector2, route: int, is_restart: bool) -> void:
	if is_restart or dead_end_texture == null or not _is_dead_end_tip(route, base.y):
		return
	var scale := _branch_painted_width(route, base.y) / 224.0
	# Keep the existing gameplay dead-end marker at the actual support endpoint.
	draw_set_transform(base, direction.angle() + PI * 0.5)
	draw_texture_rect(dead_end_texture, Rect2(-Vector2(128, 506) * scale, dead_end_texture.get_size() * scale), false)
	draw_set_transform(Vector2.ZERO)

func qa_branch_visual_deviation(route: int, world_y: float) -> float:
	return absf(_branch_visual_x(route, world_y) - float(Balance.ROUTE_X[route]))

func qa_visual_contract() -> Dictionary:
	return {
		"trunk_nominal_width_px": TRUNK_BODY_WIDTH,
		"trunk_body_face_width_formula": "96",
		"trunk_render_width_formula": "96 body + 1 transparent world unit per side",
		"trunk_edge_padding_px": [1.0, 1.0],
		"trunk_silhouette_edge_padding_px": 0.0,
		"trunk_early_silhouette_width_px": [TRUNK_BODY_WIDTH, TRUNK_BODY_WIDTH],
		"trunk_center_world_x": 0.0,
		"branch_width_px": [VINE_BODY_WIDTH, VINE_BODY_WIDTH],
		"branch_centers_world_x": Balance.ROUTE_X.duplicate(),
		"early_gameplay_centers_world_x": ScaleLock.TRUNK_SAFE_WORLD_X.duplicate(),
		"texture_repeat_px": TRUNK_TILE_HEIGHT,
		"branch_texture_repeat_px": LANE_TILE_HEIGHT,
		"outline_px": 0.0,
		"max_leaf_px": 0.0,
		"surface_texture": "res://assets/art/world/v4/trunk_tile.png",
		"branch_surface_texture": "res://assets/art/world/v4/vine_tile.png",
		"crown_texture": "res://assets/art/world/v4/crown.png",
		"crown_world_size": [CROWN_SIZE.x, CROWN_SIZE.y],
		"crown_anchor_world": [CROWN_ANCHOR.x, CROWN_ANCHOR.y],
		"crown_vine_exit_world_y": CROWN_VINE_EXIT,
		"stage_3_layout": "centered_trunk_three_straight_hanging_vines_and_stage_crowns",
		"side_branch_textures": [],
		"foliage_atlas": "",
		"draw_order": ["trunk", "vines", "crowns", "gameplay_objects"],
	}

func _stage_3_bottom_y() -> float:
	if stages != null:
		return stages.stage_bottom_y(3)
	return -float(StageDatabase.stage(3).start_height)
