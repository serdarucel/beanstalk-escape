extends Control

var game: GameManager
var redraw_count := 0

func _draw() -> void:
	redraw_count += 1
	draw_line(Vector2(24, 24), Vector2(24, size.y - 24), Palette.WORLD_STALK_EDGE, 4.0)
	draw_string(ThemeDB.fallback_font, Vector2(4, size.y - 4), "TRAIL", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Palette.WORLD_STALK_EDGE)
	var summit_color := Palette.ACCENT_PROGRESS
	if game != null and game.stages.summit_flash_count > 0:
		summit_color = Palette.SUMMIT_FLASH if int(Time.get_ticks_msec() / 120) % 2 == 0 else Palette.SUMMIT_DARK
	draw_string(ThemeDB.fallback_font, Vector2(2, 12), "AHEAD", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, summit_color)
	for stage in 30:
		var t := float(stage) / 29.0
		var y := lerpf(size.y - 28.0, 28.0, t)
		var active := true
		draw_circle(Vector2(24, y), 3.5 if active else 2.0, Palette.ACCENT_PROGRESS if active else Palette.MAP_INACTIVE)
	if game == null:
		return
	var start := game.stages.stage_start_height(game.stages.first_stage)
	var total_height := game.stages.stage_target_height(game.stages.last_stage) - start
	var progress := clampf((-game.player.global_position.y - start) / maxf(total_height, 1.0), 0.0, 1.0)
	var player_y := lerpf(size.y - 28.0, 28.0, progress)
	draw_circle(Vector2(24, player_y), 7.0, Palette.WHITE_FLASH)
