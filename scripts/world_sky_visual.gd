class_name WorldSkyVisual
extends Node2D

const SKY_DAY := preload("res://assets/art/world/v2/sky_day.png")
const SKY_GOLDEN := preload("res://assets/art/world/v3/sky_golden.png")
const SKY_SUNSET := preload("res://assets/art/world/v2/sky_sunset.png")

var player: PlayerController
var stages: StageManager
var redraw_count := 0
var redraw_elapsed := 0.0
var camera_top := -270.0

func setup(target: PlayerController, stage_manager: StageManager) -> void:
	player = target
	stages = stage_manager

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	set_process(true)
	queue_redraw()

func _process(delta: float) -> void:
	if player == null:
		return
	var camera := player.get_node_or_null("Camera2D") as Camera2D
	var camera_center := player.global_position + Vector2(0.0, -120.0)
	if camera != null:
		camera_center = camera.get_screen_center_position()
	camera_top = camera_center.y + _view_rect().position.y + 8.0
	global_position = camera_center
	redraw_elapsed += delta
	if redraw_elapsed >= 0.05:
		redraw_elapsed = fmod(redraw_elapsed, 0.05)
	queue_redraw()

func _view_rect() -> Rect2:
	var zoom := Vector2.ONE
	if player != null:
		var camera := player.get_node_or_null("Camera2D") as Camera2D
		if camera != null:
			zoom = camera.zoom
	var size := get_viewport_rect().size / zoom
	return Rect2(-size * 0.5 - Vector2.ONE * 8.0, size + Vector2.ONE * 16.0)

func _draw_sky_cover(texture: Texture2D, destination: Rect2, tint := Color.WHITE) -> void:
	var texture_size := texture.get_size()
	var scale := maxf(destination.size.x / texture_size.x, destination.size.y / texture_size.y)
	var source_size := destination.size / scale
	var source := Rect2((texture_size - source_size) * 0.5, source_size)
	draw_texture_rect_region(texture, destination, source, tint)

func sunset_mix_at(stage_number: int, stage_progress: float) -> float:
	# Day through Stage 11; continuous transition from the start of 12 to 20.
	return smoothstep(12.0, 20.0, float(stage_number) + stage_progress)

func _draw() -> void:
	redraw_count += 1
	if player == null:
		return
	var view_rect := _view_rect()
	var world := get_parent()
	if bool(world.get("qa_support_mask")):
		draw_rect(view_rect, Color.BLACK)
		return
	if bool(world.get("qa_storm_background")):
		draw_rect(view_rect, Color("313c68"))
		return
	var stage_number := stages.stage_for_y(player.global_position.y) if stages != null else 1
	var progress := stages.progress_in_stage(player.global_position.y) if stages != null else 0.0
	var sunset := sunset_mix_at(stage_number, progress)
	if sunset <= 0.5:
		_draw_sky_cover(SKY_DAY, view_rect)
		_draw_sky_cover(SKY_GOLDEN, view_rect, Color(1.0, 1.0, 1.0, sunset * 2.0))
	else:
		_draw_sky_cover(SKY_GOLDEN, view_rect)
		_draw_sky_cover(SKY_SUNSET, view_rect, Color(1.0, 1.0, 1.0, sunset * 2.0 - 1.0))
	# Lightning remains subtle without a permanent purple storm wash.
	if stage_number >= 20:
		var flash := pow(maxf(sin(Time.get_ticks_msec() * 0.0017 + float(stage_number)), 0.0), 18.0)
		draw_rect(view_rect, Color(0.86, 0.83, 0.95, flash * 0.04))
