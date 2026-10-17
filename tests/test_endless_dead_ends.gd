extends SceneTree

var failures := 0
var dead_ends := 0
var no_exit := 0
var first_time := INF
var rows: Array[String] = []

func _initialize() -> void:
	var stages := StageManager.new()
	root.add_child(stages)
	await process_frame
	stages.reset_run(12345)
	var templates := StageDatabase.canonical_stages()
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var recent: Array = []
	var last_time := -INF
	var previous: Dictionary = {}
	for number in range(1, 41):
		stages.ensure_stage(number)
		var stage: Dictionary = stages.stage_records[number]
		var expected_template := number
		if number >= 4:
			var pool: Array[int] = []
			for candidate in range(4, [8, 14, 22, 30][int(stage.tier)] + 1):
				if not recent.has(candidate):
					pool.append(candidate)
			expected_template = pool[rng.randi_range(0, pool.size() - 1)]
		_check(stage.template == expected_template, "unchanged RNG template sequence S%d" % number)
		recent.append(expected_template)
		if recent.size() > 3:
			recent.pop_front()
		if number <= 3:
			_check(stage.encounters == templates[number - 1].encounters, "unchanged authored S%d" % number)
		var pattern := stages.pattern_for_stage(number)
		for index in stage.encounters.size():
			var encounter: Dictionary = stage.encounters[index]
			for threat: Dictionary in StageDatabase.threats_for_recipe(encounter.recipe):
				if String(threat.kind) != "FORK":
					continue
				var seconds := Balance.estimated_time_for_height(float(stage.start_height) + float(encounter.anchor))
				first_time = minf(first_time, seconds)
				if number < 4:
					last_time = seconds
					continue
				dead_ends += 1
				var closed := -1
				var hazards: Array = []
				for lane in 3:
					if not threat.supports.has(lane):
						closed = lane
				for other: Dictionary in StageDatabase.threats_for_recipe(encounter.recipe):
					if String(other.kind) in ["BEAN", "S", "R", "F", "K", "WEB"]:
						hazards.append(int(other.lane))
					elif String(other.kind) in ["WALL", "M"]:
						hazards.append_array(other.lanes)
				var exits: Array = []
				for lane in threat.supports:
					if absi(int(lane) - closed) == 1 and not hazards.has(lane):
						exits.append(lane)
				if exits.is_empty():
					no_exit += 1
				_check(closed != int(encounter.witness) and not hazards.has(encounter.witness), "safe witness " + encounter.id)
				_check(seconds >= 20.0 and seconds - last_time >= 15.0, "time spacing " + encounter.id)
				_check(seconds - last_time <= 30.0, "regular cadence " + encounter.id)
				_check(pattern.support_windows.any(func(window: Dictionary) -> bool: return window.id == encounter.id and window.supports == threat.supports), "runtime support " + encounter.id)
				var tick := int(ceil((float(stage.start_height) + float(encounter.anchor) + 1.0) / Balance.PLAYER_VERTICAL_SPEED * ReachabilityValidator.PHYSICS_HZ))
				_check(not ReachabilityValidator._routes_connected_at_tick(stage, closed, int(exits[0]) if not exits.is_empty() else 1, tick), "validator COMBO " + encounter.id)
				_check(not AntiCheeseHarness._route_survives(encounter, closed), "anti-cheese COMBO " + encounter.id)
				_check(not GoldPlacementData._route_survives(encounter, closed), "gold COMBO " + encounter.id)
				var mirrored: Dictionary = encounter.recipe.duplicate(true)
				StageDatabase._mirror_recipe(mirrored)
				for mirrored_threat: Dictionary in StageDatabase.threats_for_recipe(mirrored):
					if String(mirrored_threat.kind) == "FORK":
						_check(not mirrored_threat.supports.has(2 - closed), "mirror FORK " + encounter.id)
				_check_slots(pattern, encounter, closed)
				for coin: Dictionary in GoldPlacementData.placements_for_stage(number, 30, stages):
					var height := stages.stage_bottom_y(number) - float(coin.position.y)
					_check(not (int(coin.route) == closed and height >= float(encounter.anchor) and height <= float(encounter.occupancy[1])), "coin outside gap " + coin.id)
				if index + 1 < stage.encounters.size():
					var next: Dictionary = stage.encounters[index + 1]
					var crosses := closed >= mini(int(encounter.witness), int(next.witness)) and closed <= maxi(int(encounter.witness), int(next.witness))
					if crosses:
						var rise := float(absi(int(next.witness) - int(encounter.witness))) * Balance.PLAYER_VERTICAL_SPEED * Balance.ENDLESS_MAX_SPEED_SCALE * (Balance.BRANCH_TRANSITION_SECONDS + Balance.BRANCH_COMMAND_BUFFER_SECONDS)
						_check(float(next.anchor) - float(encounter.occupancy[1]) >= rise, "next witness transition " + encounter.id)
				if index > 0:
					previous = stage.encounters[index - 1]
				if index > 0 and int(previous.witness) == closed:
					_check(float(previous.occupancy[1]) <= float(encounter.anchor), "previous witness remains supported " + encounter.id)
				rows.append("%2d | %7.2f | %d | %s | %d | %s" % [number, seconds, closed, str(threat.supports), int(encounter.witness), str(hazards)])
				last_time = seconds
		previous = stage.encounters[-1]
	_check(dead_ends > 0, "endless dead ends exist")
	_check(no_exit == 0, "no exit count is zero")
	_check(first_time >= 20.0, "first dead end at least 20 seconds")
	print("stage | seconds | closed | open | witness | hazard lanes")
	for row in rows:
		print(row)
	print("ENDLESS-DEAD-ENDS: forks=%d first=%.2f no_exit=%d FAIL=%d" % [dead_ends, first_time, no_exit, failures])
	stages.free()
	quit(0 if failures == 0 else 1)

func _check_slots(pattern: Dictionary, encounter: Dictionary, closed: int) -> void:
	for slot: Dictionary in pattern.bean_slots:
		var end := float(slot.anchor) + 120.0 + 70.0 * float(int(slot.count) - 1)
		_check(not (int(slot.blocked_route) == closed and end >= float(encounter.anchor) and float(slot.anchor) <= float(encounter.occupancy[1])), "bean outside gap " + slot.id)
	for slot: Dictionary in pattern.rock_slots:
		_check(not (slot.routes.has(closed) and float(slot.anchor) + 180.0 >= float(encounter.anchor) and float(slot.anchor) <= float(encounter.occupancy[1])), "rock outside gap " + slot.id)

func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		print("FAIL: " + label)
