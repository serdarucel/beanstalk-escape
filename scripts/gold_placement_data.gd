class_name GoldPlacementData
extends RefCounted

const HAZARD_CLEARANCE_PX := 16.0
const LINE_COUNT := 5
# gold_coin.png is 64 px, displayed at 0.82 by GoldCollectible.
const COIN_DIAMETER_PX := 64.0 * 0.82
const MIN_COIN_SPACING_PX := COIN_DIAMETER_PX * 1.4
const COIN_SPACING_PX := COIN_DIAMETER_PX * 1.6
const ARC_HEIGHT_PX := 22.0

static func placements_for_stage(stage_number: int, count: int, stages: StageManager) -> Array:
	var result: Array = []
	if count <= 0:
		return result
	var definition: Dictionary = stages.stage_records.get(stage_number, {})
	var encounters: Array = definition.get("encounters", [])
	if encounters.is_empty():
		return result
	var first: Dictionary = encounters[0]
	# Whole rows have priority; count remains a hard cap. Fill encounter gaps
	# before spending spare row budget on the entry corridor.
	var line_start := HAZARD_CLEARANCE_PX
	var row_gaps: Array = range(1, encounters.size())
	row_gaps.append(0)
	for index: int in row_gaps:
		if result.size() + LINE_COUNT > count:
			break
		var current: Dictionary = encounters[index]
		# One pixel also survives Vector2 world-coordinate rounding late in a run.
		var gap_start := HAZARD_CLEARANCE_PX if index == 0 else float(encounters[index - 1].occupancy[1]) + HAZARD_CLEARANCE_PX + 1.0
		var gap_end := float(current.anchor) - HAZARD_CLEARANCE_PX - 1.0
		if gap_end <= gap_start:
			continue
		var row_count := mini(LINE_COUNT, int(floor((gap_end - gap_start) / MIN_COIN_SPACING_PX)) + 1)
		if row_count < 3:
			continue
		var spacing := minf(COIN_SPACING_PX, (gap_end - gap_start) / float(row_count - 1))
		var start := (gap_start + gap_end - spacing * float(row_count - 1)) * 0.5
		var x := _witness_x(stage_number, current.witness)
		var route := _route_at_x(stage_number, x, stages)
		var row: Array = []
		for coin_index in row_count:
			_append_coin(row, stage_number, Vector2(x, start + float(coin_index) * spacing), route, encounters, stages)
		if row.size() == row_count:
			for coin: Dictionary in row:
				coin.id = "S%03d-G%02d" % [stage_number, result.size() + 1]
				result.append(coin)
			if index == 0:
				line_start = start
	var remaining := count - result.size()
	if remaining <= 0:
		return _filter_coin_spacing(result)
	# Spend the remaining budget on an authored route change. Never draw a
	# direct L-to-R jump: the player transfers between adjacent branches.
	# Include the entry from C to the first witness, before the first hazard.
	# This also supplies an arc when every authored witness uses one branch.
	var changes: Array = encounters.duplicate()
	changes.push_front({"witness": 1, "occupancy": [0.0, line_start - COIN_SPACING_PX - HAZARD_CLEARANCE_PX]})
	for index in range(1, changes.size()):
		var previous: Dictionary = changes[index - 1]
		var current: Dictionary = changes[index]
		var from_x := _witness_x(stage_number, previous.witness)
		var to_x := _witness_x(stage_number, current.witness)
		var from_route := _route_at_x(stage_number, from_x, stages)
		var to_route := _route_at_x(stage_number, to_x, stages)
		if is_equal_approx(from_x, to_x) or (stage_number > 2 and absi(to_route - from_route) != 1):
			continue
		var rise := Balance.PLAYER_VERTICAL_SPEED * Balance.BRANCH_TRANSITION_SECONDS
		var base_height := float(previous.occupancy[1]) + HAZARD_CLEARANCE_PX - rise
		if index == 1:
			base_height = maxf(HAZARD_CLEARANCE_PX, base_height)
			if stages.template_for_stage(stage_number) == 13:
				base_height = maxf(base_height, float(first.anchor) - 280.0)
		if stage_number > 2 and not stages.transfer_window_open(stage_number, base_height / stages.stage_length(stage_number)):
			continue
		var arc_count := mini(remaining, 3)
		var last_arc_position := Vector2.ZERO
		var has_arc_coin := false
		for coin_index in arc_count:
			var t := float(coin_index) / float(maxi(arc_count - 1, 1))
			var height := base_height + rise * t + sin(PI * t) * ARC_HEIGHT_PX
			var position := Vector2(lerpf(from_x, to_x, t), height)
			if has_arc_coin and position.distance_to(last_arc_position) < MIN_COIN_SPACING_PX:
				continue
			# Keep collection eligibility on the source/destination branches.
			var coin_route := from_route if t < 0.5 else to_route
			var previous_size := result.size()
			_append_coin(result, stage_number, position, coin_route, encounters, stages)
			if result.size() > previous_size:
				last_arc_position = position
				has_arc_coin = true
		break
	result = _filter_coin_spacing(result)
	# Spend spare budget in whole vertical rows, exhausting witness corridors
	# before looking on other lanes. All candidates still use _append_coin.
	for index in encounters.size():
		var current: Dictionary = encounters[index]
		var start := HAZARD_CLEARANCE_PX if index == 0 else float(encounters[index - 1].occupancy[1]) + HAZARD_CLEARANCE_PX + 1.0
		var end := stages.stage_length(stage_number) - HAZARD_CLEARANCE_PX if index == encounters.size() - 1 else float(current.occupancy[1])
		_fill_vertical_rows(result, stage_number, count, _witness_x(stage_number, current.witness), start, end, encounters, stages)
	for lane in 3:
		var x := float(ScaleLock.TRUNK_SAFE_WORLD_X[lane]) if stage_number <= 2 else float(Balance.ROUTE_X[lane])
		_fill_vertical_rows(result, stage_number, count, x, HAZARD_CLEARANCE_PX, stages.stage_length(stage_number) - HAZARD_CLEARANCE_PX, encounters, stages)
	for index in result.size():
		result[index].id = "S%03d-G%02d" % [stage_number, index + 1]
	return result

static func _fill_vertical_rows(result: Array, stage_number: int, count: int, x: float, start: float, end: float, encounters: Array, stages: StageManager) -> void:
	var route := _route_at_x(stage_number, x, stages)
	var height := start
	while height + 2.0 * COIN_SPACING_PX <= end and count - result.size() >= 3:
		var accepted := false
		for row_count in range(mini(LINE_COUNT, count - result.size()), 2, -1):
			if height + float(row_count - 1) * COIN_SPACING_PX > end:
				continue
			var row: Array = []
			for coin_index in row_count:
				_append_coin(row, stage_number, Vector2(x, height + float(coin_index) * COIN_SPACING_PX), route, encounters, stages)
			if row.size() != row_count:
				continue
			var overlaps := false
			for coin: Dictionary in row:
				for existing: Dictionary in result:
					if coin.position.distance_to(existing.position) < MIN_COIN_SPACING_PX:
						overlaps = true
						break
				if overlaps:
					break
			if overlaps:
				continue
			result.append_array(row)
			height += float(row_count) * COIN_SPACING_PX
			accepted = true
			break
		if not accepted:
			height += MIN_COIN_SPACING_PX * 0.25

static func _filter_coin_spacing(coins: Array) -> Array:
	var result: Array = []
	for coin: Dictionary in coins:
		var position: Vector2 = coin.position
		var overlaps := false
		for accepted: Dictionary in result:
			if position.distance_to(accepted.position) < MIN_COIN_SPACING_PX:
				overlaps = true
				break
		if not overlaps:
			result.append(coin)
	return result

static func _witness_x(stage_number: int, witness: Variant) -> float:
	if stage_number > 2:
		return float(Balance.ROUTE_X[int(witness)])
	var normalized := float(ScaleLock.TRUNK_SAFE_NORMALIZED_X[int(witness)]) if typeof(witness) == TYPE_INT else float(witness)
	return (normalized - 0.5) * 2.0 * (Balance.TRUNK_HALF_WIDTH - 12.0)

static func _route_at_x(stage_number: int, x: float, stages: StageManager) -> int:
	if stage_number <= 2:
		return stages.route_for_x(x)
	var route := 0
	for candidate in 3:
		if absf(x - float(Balance.ROUTE_X[candidate])) < absf(x - float(Balance.ROUTE_X[route])):
			route = candidate
	return route

static func _append_coin(result: Array, stage_number: int, local_position: Vector2, route: int, encounters: Array, stages: StageManager) -> void:
	if local_position.y < HAZARD_CLEARANCE_PX or local_position.y > stages.stage_length(stage_number) - HAZARD_CLEARANCE_PX:
		return
	for encounter: Dictionary in encounters:
		if local_position.y + HAZARD_CLEARANCE_PX < float(encounter.anchor) or local_position.y - HAZARD_CLEARANCE_PX > float(encounter.occupancy[1]):
			continue
		for lane in 3:
			var lane_x := float(ScaleLock.TRUNK_SAFE_WORLD_X[lane]) if stage_number <= 2 else float(Balance.ROUTE_X[lane])
			if absf(local_position.x - lane_x) <= COIN_DIAMETER_PX * 0.5 + HAZARD_CLEARANCE_PX and not _route_survives(encounter, lane):
				return
	result.append({
		"id": "S%03d-G%02d" % [stage_number, result.size() + 1],
		"stage": stage_number,
		"route": route,
		"position": Vector2(local_position.x, stages.stage_bottom_y(stage_number) - local_position.y),
	})

static func _route_survives(encounter: Dictionary, route: int) -> bool:
	return StageDatabase.route_survives(encounter.recipe, route)
