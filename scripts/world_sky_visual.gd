class_name WorldSkyVisual
extends Node2D

const SKY_DAY := preload("res://assets/art/world/v2/sky_day.png")
const SKY_GOLDEN := preload("res://assets/art/world/v3/sky_golden.png")
const SKY_SUNSET := preload("res://assets/art/world/v2/sky_sunset.png")
const FAR_STALKS := [
	preload("res://assets/art/world/v3/far_stalks_far.png"),
	preload("res://assets/art/world/v3/far_stalks_near.png"),
]
const PARALLAX_SPEEDS := [0.06, 0.14]
const FAR_STRIP_WIDTHS := [150.0, 210.0]
const FAR_OPACITIES := [0.50, 0.70]

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
	camera_top = camera_center.y - get_viewport_rect().size.y * 0.5
	global_position = camera_center
	redraw_elapsed += delta
	if redraw_elapsed >= 0.05:
		redraw_elapsed = fmod(redraw_elapsed, 0.05)
		queue_redraw()

func sunset_mix_at(stage_number: int, stage_progress: float) -> float:
	# Day through Stage 11; continuous transition from the start of 12 to 20.
	return smoothstep(12.0, 20.0, float(stage_number) + stage_progress)

func _draw() -> void:
	redraw_count += 1
	if player == null:
		return
	var view_rect := Rect2(-488.0, -278.0, 976.0, 556.0)
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
		draw_texture_rect(SKY_DAY, view_rect, false)
		draw_texture_rect(SKY_GOLDEN, view_rect, false, Color(1.0, 1.0, 1.0, sunset * 2.0))
	else:
		draw_texture_rect(SKY_GOLDEN, view_rect, false)
		draw_texture_rect(SKY_SUNSET, view_rect, false, Color(1.0, 1.0, 1.0, sunset * 2.0 - 1.0))
	_draw_far_vines(camera_top, sunset)
	# Lightning remains subtle without a permanent purple storm wash.
	if stage_number >= 20:
		var flash := pow(maxf(sin(Time.get_ticks_msec() * 0.0017 + float(stage_number)), 0.0), 18.0)
		draw_rect(view_rect, Color(0.86, 0.83, 0.95, flash * 0.04))

func _draw_far_vines(top_y: float, sunset := 0.0) -> void:
	for layer in 2:
		# Preserve the painted RGB. Sunset only boosts channels, never darkens them.
		var sunset_tint := Color(1.30, 1.04, 1.30) if layer == 0 else Color(1.45, 1.05, 1.12)
		var tint := Color.WHITE.lerp(sunset_tint, sunset)
		tint.a = FAR_OPACITIES[layer]
		var strip_width: float = FAR_STRIP_WIDTHS[layer]
		var source: Texture2D = FAR_STALKS[layer]
		var tile_height := strip_width * float(source.get_height()) / float(source.get_width())
		var first_y := -278.0 + fposmod(-top_y * PARALLAX_SPEEDS[layer], tile_height) - tile_height
		# Matched top/bottom texture edges share one continuous parallax phase.
		for tile in ceili(556.0 / tile_height) + 1:
			var tile_y := first_y + float(tile) * tile_height
			for strip_x in [-480.0, 480.0 - strip_width]:
				var destination := Rect2(strip_x, tile_y, strip_width, tile_height)
				draw_texture_rect(source, destination, false, tint)
