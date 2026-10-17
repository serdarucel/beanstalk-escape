extends "res://scripts/world_visual.gd"

## Keep the protected renderer and its geometry; visit only resident chunks.
## Iterating the high-water mark would grow draw cost throughout an endless run.
func _draw_stage_branches(camera_top: float) -> void:
	var visible_bottom := camera_top + 556.0 + 160.0 + SURFACE_CACHE_MARGIN_PX
	var visible_top := camera_top - 160.0 - SURFACE_CACHE_MARGIN_PX
	for route in 3:
		var spans: Array[Vector3] = []
		for stage_number in range(maxi(3, stages.first_stage), stages.last_stage + 1):
			var bottom := stages.stage_bottom_y(stage_number)
			var length := stages.stage_length(stage_number)
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
