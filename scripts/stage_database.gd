class_name StageDatabase
extends RefCounted

const CANONICAL_VARIANT := "canonical_v1"
const MIRROR_VARIANT := "mirror_v1"
const QA_VARIANTS := [CANONICAL_VARIANT, MIRROR_VARIANT]
const RELEASE_ALLOWLIST := []
const DEFAULT_STAGE_LENGTH := 2800
const DEFAULT_LATE_STAGE_LENGTH := 3000
const WARNING_LEAD := 360
const OCCUPANCY_HEIGHT := 220
const ACTION_OCCUPANCY_HEIGHT := 90
const MIN_REACTION_SECONDS := 0.45
const THREAT_CLASS := {
	"BEAN": "LANE", "S": "LANE", "R": "LANE", "FORK": "LANE",
	"THORN": "LOW", "K": "LOW",
	"ARCH": "HIGH", "WEB": "HIGH", "M": "HIGH",
}
const ENDLESS_DEAD_END_INTERVAL_SECONDS := 15.0
const ENDLESS_DEAD_END_FIRST_SECONDS := 20.0
const STAGE_TEMPO_CONFIG_PATH := "res://config/stage_tempo.json"
const REPLAY_NIGHTMARE_CONFIG_PATH := "res://config/replay_nightmare.json"

static var active_run_seed: int = Balance.PATTERN_SEED
static var _sequence_cache: Dictionary = {}

static func set_run_seed(seed_value: int) -> void:
	if active_run_seed != seed_value:
		active_run_seed = seed_value
		_sequence_cache.clear()

static func replay_nightmare_config() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(REPLAY_NIGHTMARE_CONFIG_PATH))
	if parsed is Dictionary:
		return (parsed as Dictionary).duplicate(true)
	push_error("Replay/Nightmare config could not be loaded")
	return {"challenges": [], "nightmare": {}}

static func nightmare_modifiers() -> Dictionary:
	return replay_nightmare_config().get("nightmare", {}).duplicate(true)

static func stage_tempo_config() -> Dictionary:
	if not FileAccess.file_exists(STAGE_TEMPO_CONFIG_PATH):
		push_error("Stage tempo config is missing; legacy stage lengths will be used")
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(STAGE_TEMPO_CONFIG_PATH))
	if parsed is not Dictionary or (parsed as Dictionary).get("stages", null) is not Array:
		push_error("Stage tempo config is invalid; legacy stage lengths will be used")
		return {}
	var result := {}
	for entry_value in (parsed as Dictionary).stages:
		if entry_value is Dictionary:
			var entry: Dictionary = entry_value
			result[int(entry.get("stage", 0))] = entry.duplicate(true)
	return result

const STAGE_DEFINITIONS := [
	{
		"number": 1, "title": "Ground Awakening", "branch_graph": "TRUNK", "skill_unlock": "none",
		"witness": [0.20, 0.80, 0.50, 0.20, 0.80],
		"encounters": [
			{"id": "S01-E01", "anchor": 500, "recipe": {"kind": "GUIDE", "x": 0.20}, "witness": 0.20, "objective": "Follow the left surface; climbing stays automatic."},
			{"id": "S01-E02", "anchor": 950, "recipe": {"kind": "GUIDE", "x": 0.80}, "witness": 0.80, "objective": "Traverse the full trunk surface."},
			{"id": "S01-E03", "anchor": 1400, "recipe": {"kind": "GUIDE", "x": 0.50}, "witness": 0.50, "objective": "Release input while automatic climbing continues."},
			{"id": "S01-E04", "anchor": 1850, "recipe": {"kind": "GUIDE", "x": 0.20}, "witness": 0.20, "objective": "Choose direction under spider audio pressure."},
			{"id": "S01-E05", "anchor": 2300, "recipe": {"kind": "GUIDE", "x": 0.80}, "witness": 0.80, "objective": "Reach the right exit corridor."},
		],
	},
	{
		"number": 2, "title": "First Fork", "branch_graph": "TRUNK", "skill_unlock": "none",
		"witness": [0.80, 0.20, 0.50, 0.80, 0.20],
		"encounters": [
			{"id": "S02-E01", "anchor": 500, "recipe": {"kind": "BULGE", "x": 0.80}, "witness": 0.80, "objective": "Pass the first bark bulge on its right."},
			{"id": "S02-E02", "anchor": 970, "recipe": {"kind": "BULGE", "x": 0.20}, "witness": 0.20, "objective": "Read the opposite bulge early."},
			{"id": "S02-E03", "anchor": 1430, "recipe": {"kind": "BULGE", "x": 0.50}, "witness": 0.50, "objective": "Take the central surface corridor."},
			{"id": "S02-E04", "anchor": 1890, "recipe": {"kind": "BULGE", "x": 0.80}, "witness": 0.80, "objective": "Follow the right curve continuously."},
			{"id": "S02-E05", "anchor": 2350, "recipe": {"kind": "BULGE", "x": 0.20}, "witness": 0.20, "objective": "Make the final trunk-side change."},
		],
	},
	{
		"number": 3, "title": "Three Vines", "branch_graph": "G3", "skill_unlock": "none",
		"witness": [0, 1, 2, 1, 0],
		"encounters": [
			{"id": "S03-E01", "anchor": 500, "recipe": {"kind": "FORK", "supports": [0, 1]}, "witness": 0, "objective": "Move from C to supported L."},
			{"id": "S03-E02", "anchor": 950, "recipe": {"kind": "FORK", "supports": [1, 2]}, "witness": 1, "objective": "Leave the visible L tip for C."},
			{"id": "S03-E03", "anchor": 1400, "recipe": {"kind": "FORK", "supports": [0, 2]}, "witness": 2, "objective": "Leave the visible C tip for R."},
			{"id": "S03-E04", "anchor": 1850, "recipe": {"kind": "FORK", "supports": [0, 1]}, "witness": 1, "objective": "Leave the R tip for C."},
			{"id": "S03-E05", "anchor": 2300, "recipe": {"kind": "FORK", "supports": [0, 2]}, "witness": 0, "objective": "Exit on L through the final fork."},
		],
	},
	{
		"number": 4, "title": "Falling Beans", "branch_graph": "G3", "skill_unlock": "none",
		"witness": [0, 1, 2, 0, 1],
		"encounters": [
			{"id": "S04-E01", "anchor": 500, "recipe": {"kind": "BEAN", "lane": 1, "count": 1}, "witness": 0, "objective": "Leave the first center bean on L."},
			{"id": "S04-E02", "anchor": 950, "recipe": {"kind": "BEAN", "lane": 0, "count": 1}, "witness": 1, "objective": "Read the new L target and use C."},
			{"id": "S04-E03", "anchor": 1400, "recipe": {"kind": "BEAN", "lane": 1, "count": 1}, "witness": 2, "objective": "Evade the repeated bean on R."},
			{"id": "S04-E04", "anchor": 1850, "recipe": {"kind": "BEAN", "lane": 2, "count": 1}, "witness": 0, "objective": "Use the open two-transfer corridor to L."},
			{"id": "S04-E05", "anchor": 2300, "recipe": {"kind": "BEAN", "lane": 0, "count": 1}, "witness": 1, "objective": "Take the calm center exit."},
		],
	},
	{
		"number": 5, "title": "Violet Wings", "branch_graph": "G3", "skill_unlock": "TIME",
		"witness": [2, 1, 0, 2, 1],
		"encounters": [
			{"id": "S05-E01", "anchor": 500, "recipe": {"kind": "BEAN", "lane": 1, "count": 1}, "witness": 2, "objective": "Show TIME READY while R stays safe."},
			{"id": "S05-E02", "anchor": 960, "recipe": {"kind": "BEAN", "lane": 2, "count": 1}, "witness": 1, "objective": "Track a Time-slowed bean from C."},
			{"id": "S05-E03", "anchor": 1440, "recipe": {"kind": "BEAN", "lane": 1, "count": 1}, "witness": 0, "objective": "Keep player speed unchanged on L."},
			{"id": "S05-E04", "anchor": 1900, "recipe": {"kind": "BEAN", "lane": 0, "count": 1}, "witness": 2, "objective": "Use the open two-transfer corridor to R."},
			{"id": "S05-E05", "anchor": 2370, "recipe": {"kind": "BEAN", "lane": 2, "count": 1}, "witness": 1, "objective": "Let Time end without moving the threat."},
		],
	},
]

static func canonical_stages() -> Array:
	var result: Array = []
	var definitions: Array = STAGE_DEFINITIONS.duplicate(true)
	definitions.append_array(_stages_6_to_15())
	definitions.append_array(_stages_16_to_30())
	var tempo_by_stage := stage_tempo_config()
	var accumulated_height := 0
	for definition_value in definitions:
		var stage: Dictionary = (definition_value as Dictionary).duplicate(true)
		var stage_number := int(stage.number)
		var fallback_length := _fallback_stage_length(stage_number)
		var tempo: Dictionary = tempo_by_stage.get(stage_number, {})
		if tempo.is_empty():
			push_error("Stage %d tempo is missing; legacy values will be used" % stage_number)
		stage["length"] = int(tempo.get("length_px", fallback_length))
		stage["encounter_count"] = int(tempo.get("encounter_count", 10 if stage_number <= 5 else 9))
		stage["min_encounter_spacing_px"] = int(tempo.get("min_encounter_spacing_px", OCCUPANCY_HEIGHT))
		stage["start_height"] = accumulated_height
		stage["theme"] = String(stage.get("theme", "sunny"))
		stage["qa_seed_set"] = QA_VARIANTS.duplicate()
		stage["release_allowlist"] = RELEASE_ALLOWLIST.duplicate()
		stage["checkpoint"] = "stage_start"
		stage["tutorial_trigger"] = "none" if int(stage.number) >= 15 else "encounter_warning_once"
		stage["end_transition"] = "next_stage_immediate_with_three_async_pulses"
		stage["nominal_duration_no_fire"] = float(stage.length) / Balance.PLAYER_VERTICAL_SPEED
		stage["validation_status"] = "NOT_RUN"
		if stage_number == 1:
			# A harmless center guide supplies the existing five-coin generator.
			stage["encounters"] = [{"id": "S01-GOLD", "anchor": 464, "occupancy_height": 0, "recipe": {"kind": "GUIDE", "x": 0.5}, "witness": 1, "objective": "Climb the center coin line."}]
		elif stage_number == 2:
			stage["encounters"] = []
		elif stage_number == 3:
			stage["encounters"] = _opening_encounters(accumulated_height)
		else:
			stage["encounters"] = _paced_encounters(stage) if stage_number <= 5 else _densify_encounters(stage)
		stage["witness"] = stage.encounters.map(func(encounter: Dictionary) -> Variant: return encounter.witness)
		for encounter: Dictionary in stage.encounters:
			var anchor := int(encounter.anchor)
			encounter["warning_height"] = anchor - WARNING_LEAD
			encounter["occupancy"] = [anchor, anchor + int(encounter.get("occupancy_height", OCCUPANCY_HEIGHT))]
		_repair_reaction_windows(stage)
		accumulated_height += int(stage.length)
		stage["target_height"] = accumulated_height
		result.append(stage)
	return result

## Invert the canonical B1 clock instead of assuming constant climbing speed.
static func height_for_time(seconds: float) -> float:
	var lower := 0.0
	var upper := maxf(seconds, 0.0) * Balance.PLAYER_VERTICAL_SPEED * Balance.ENDLESS_MAX_SPEED_SCALE + 1.0
	for iteration in 48:
		var middle := (lower + upper) * 0.5
		if Balance.estimated_time_for_height(middle) < seconds:
			lower = middle
		else:
			upper = middle
	return (lower + upper) * 0.5

static func _opening_encounters(start_height: int) -> Array:
	var rows := [
		[5.0, _hazard("BEAN", 1), 0, 220],
		[8.5, _low("THORN", 1), 1, 90],
		[12.5, _high("ARCH", 1), 1, 90],
		[20.0, {"kind": "COMBO", "threats": [_hazard("S", 0), _low("THORN", 1)]}, 2, 90],
		# WEB and the following bean are one deliberately close two-beat phrase.
		[22.6, _high("WEB", 1), 0, 90],
		[23.2, _hazard("BEAN", 2), 0, 90],
		[26.5, {"kind": "COMBO", "threats": [{"kind": "FORK", "supports": [0, 1]}, _high("ARCH", 1)]}, 1, 90],
	]
	var result: Array = []
	for row: Array in rows:
		var recipe: Dictionary = row[1]
		var solutions := encounter_solutions(recipe)
		var chosen: Dictionary = solutions[0]
		for solution: Dictionary in solutions:
			if int(solution.route) == int(row[2]):
				chosen = solution
				break
		result.append({"id": "S03-E%02d" % [result.size() + 1], "anchor": int(round(height_for_time(float(row[0])))) - start_height, "recipe": recipe, "witness": int(chosen.route), "occupancy_height": int(row[3]), "objective": "Read the opening runner rhythm."})
	return result

static func _stages_6_to_15() -> Array:
	return [
		_runner_stage(6, "Rock Roots", "rock_cloud", "S", "THORN", "ARCH"),
		_runner_stage(7, "Stone and Seed", "rock_cloud", "BEAN", "THORN", "ARCH"),
		_runner_stage(8, "The Rolling Boulder", "rock_cloud", "R", "K", "ARCH"),
		_runner_stage(9, "Crossfire", "rock_cloud", "R", "THORN", "WEB"),
		_runner_stage(10, "Fire Ascension", "rock_cloud", "BEAN", "K", "ARCH", "FIRE"),
		_runner_stage(11, "Purple Glide", "violet_twilight", "S", "THORN", "WEB"),
		_runner_stage(12, "The Stone Locks", "violet_twilight", "S", "K", "ARCH"),
		_runner_stage(13, "Twisting Junction", "violet_twilight", "R", "THORN", "WEB", "none", true),
		_runner_stage(14, "Final Lesson", "violet_twilight", "BEAN", "K", "ARCH"),
		_runner_stage(15, "Into the Unknown", "violet_twilight", "R", "THORN", "WEB"),
	]

static func _stages_16_to_30() -> Array:
	return [
		_runner_stage(16, "Root Arches", "storm", "S", "THORN", "ARCH"),
		_runner_stage(17, "Threaded Seeds", "storm", "BEAN", "K", "WEB"),
		_runner_stage(18, "Stone and Thorns", "storm", "S", "THORN", "ARCH"),
		_runner_stage(19, "Snapping Vines", "storm", "R", "K", "WEB"),
		_runner_stage(20, "Taut Threads", "storm", "BEAN", "THORN", "WEB"),
		_runner_stage(21, "Thorn Heights", "lightning_rock", "S", "THORN", "ARCH"),
		_runner_stage(22, "The Low Arch", "lightning_rock", "R", "K", "ARCH"),
		_runner_stage(23, "Bean Monsoon", "lightning_rock", "BEAN", "THORN", "WEB"),
		_runner_stage(24, "Crushing Rhythm", "lightning_rock", "R", "K", "ARCH"),
		_runner_stage(25, "The Hunter Closes", "lightning_rock", "BEAN", "THORN", "WEB"),
		_runner_stage(26, "The Hanging Stones", "upper_cloud", "S", "K", "M"),
		_runner_stage(27, "Hanging Labyrinth", "upper_cloud", "R", "THORN", "M"),
		_runner_stage(28, "All Against You", "upper_cloud", "BEAN", "K", "ARCH"),
		_runner_stage(29, "Last Chase", "upper_cloud", "R", "THORN", "M"),
		_runner_stage(30, "Summit", "summit", "BEAN", "K", "M"),
	]

## Six beats keep the authored LANE / LOW / HIGH rhythm balanced per template.
## Early templates teach single threats; later ones layer choices and dead ends.
static func _runner_stage(number: int, title: String, theme: String, lane_kind: String, low_kind: String, high_kind: String, skill := "none", junction := false) -> Dictionary:
	var rows: Array = []
	var witnesses: Array = []
	for index in 6:
		var route := (number + index) % 3
		var other := (route + 1) % 3
		var third := (route + 2) % 3
		var threats: Array
		match index % 3:
			0:
				threats = [_hazard(lane_kind, other)]
			1:
				threats = [_low(low_kind, route)]
			2:
				threats = [_high(high_kind, route)]
		if number >= 9:
			match index % 3:
				0:
					threats.append(_hazard("BEAN" if lane_kind != "BEAN" else "S", third))
				1:
					threats.append(_low("K" if low_kind != "K" else "THORN", other))
				2:
					threats.append(_high("WEB" if high_kind != "WEB" else "ARCH", other))
		if number >= 16:
			match index:
				0:
					# Stone + low threat + an empty lane.
					threats = [_hazard("S", other), _low("THORN", third)]
				1:
					threats = [_low(low_kind, route), _hazard(lane_kind, other), _high(high_kind, third)]
				2:
					threats = [_high("ARCH", route), {"kind": "FORK", "supports": [route, other]}]
				5:
					# Both supported alternatives require hugging.
					threats = [_high("WEB", route), _high("M", other), _hazard("BEAN", third)]
		rows.append([500 + index * 400, threats, route])
		witnesses.append(route)
	return _late_stage(number, title, theme, witnesses, rows, skill, junction)

static func _low(kind: String, lane: int) -> Dictionary:
	return {"kind": kind, "lane": lane}

static func _high(kind: String, lane: int) -> Dictionary:
	return {"kind": kind, "lane": lane}

static func _hazard(kind: String, lane: int, count := 1) -> Dictionary:
	var result := {"kind": kind, "lane": lane}
	if kind == "BEAN": result["count"] = count
	return result

static func _late_stage(number: int, title: String, theme: String, witness: Array, rows: Array, skill := "none", junction := false) -> Dictionary:
	var encounters: Array = []
	for index in rows.size():
		var row: Array = rows[index]
		var threats: Array = row[1]
		var recipe: Dictionary = (threats[0] as Dictionary).duplicate(true) if threats.size() == 1 else {"kind": "COMBO", "threats": threats.duplicate(true)}
		encounters.append({"id": "S%02d-E%02d" % [number, index + 1], "anchor": int(row[0]), "recipe": recipe, "witness": int(row[2]), "objective": "Read the telegraph and reach the canonical safe lane."})
	return {"number": number, "title": title, "branch_graph": "J13" if junction else "G3", "skill_unlock": skill, "theme": theme, "witness": witness, "encounters": encounters, "junction_override": junction}

static func _densify_encounters(stage: Dictionary) -> Array:
	var result: Array = stage.encounters.duplicate(true)
	var target_count := int(stage.encounter_count)
	while result.size() < target_count:
		var best_index := 0
		var best_gap := -1
		for index in range(result.size() - 1):
			var gap := int((result[index + 1] as Dictionary).anchor) - int((result[index] as Dictionary).anchor)
			if gap > best_gap:
				best_gap = gap
				best_index = index
		var left: Dictionary = result[best_index]
		var right: Dictionary = result[best_index + 1]
		var inserted: Dictionary = left.duplicate(true)
		inserted["id"] = "S%02d-X%02d" % [int(stage.number), result.size() + 1]
		inserted["anchor"] = int(round((float(left.anchor) + float(right.anchor)) * 0.5))
		inserted["occupancy_height"] = 120
		inserted["objective"] = "Keep the established safe route through the denser rhythm."
		result.insert(best_index + 1, inserted)
	_repace_anchors(result, stage, WARNING_LEAD)
	return result

static func threats_for_recipe(recipe: Dictionary) -> Array:
	return recipe.threats if String(recipe.kind) == "COMBO" else [recipe]

static func route_survives(recipe: Dictionary, route: int, action := "none") -> bool:
	if route < 0 or route > 2 or action not in ["none", "jump", "hug"]:
		return false
	for threat: Dictionary in threats_for_recipe(recipe):
		var kind := String(threat.kind)
		if kind == "FORK" and not threat.supports.has(route):
			return false
		if kind == "WALL" and threat.lanes.has(route):
			return false
		if int(threat.get("lane", -1)) != route:
			continue
		match String(THREAT_CLASS.get(kind, "")):
			"LANE":
				return false
			"LOW":
				if action != "jump":
					return false
			"HIGH":
				if action != "hug":
					return false
	return true

static func encounter_solutions(recipe: Dictionary) -> Array:
	var result: Array = []
	for route in 3:
		for action in ["none", "jump", "hug"]:
			if route_survives(recipe, route, action):
				result.append({"route": route, "action": action})
	return result

static func _has_action_conflict(recipe: Dictionary) -> bool:
	var classes_by_lane := {}
	for threat: Dictionary in threats_for_recipe(recipe):
		var threat_class := String(THREAT_CLASS.get(String(threat.kind), ""))
		if threat_class not in ["LOW", "HIGH"]:
			continue
		var lane := int(threat.lane)
		if classes_by_lane.has(lane) and classes_by_lane[lane] != threat_class:
			return true
		classes_by_lane[lane] = threat_class
	return false

static func _transfer_seconds(from_route: int, to_route: int) -> float:
	return float(absi(to_route - from_route)) * (Balance.BRANCH_TRANSITION_SECONDS * 0.5 + Balance.BRANCH_COMMAND_BUFFER_SECONDS)

## Called after anchor pacing and again after runtime dead-end insertion. The
## previous solution survives cache eviction, so even a long run is paced safely.
static func _repair_reaction_windows(stage_value: Dictionary, previous := {}) -> Dictionary:
	var start := float(stage_value.start_height)
	var previous_route := int(previous.get("route", -1))
	var previous_end := float(previous.get("end", 0.0))
	var previous_anchor := float(previous.get("anchor", previous_end))
	var previous_recipe: Dictionary = previous.get("recipe", {})
	var previous_combo := bool(previous.get("combo", false))
	for encounter: Dictionary in stage_value.encounters:
		var solutions := encounter_solutions(encounter.recipe)
		if solutions.is_empty() or _has_action_conflict(encounter.recipe):
			push_error("Invalid encounter recipe: %s" % encounter.id)
			continue
		var chosen: Dictionary = solutions[0]
		for solution: Dictionary in solutions:
			if int(solution.route) == int(encounter.witness):
				chosen = solution
				break
		var anchor := int(encounter.anchor)
		if int(stage_value.number) >= 4 and previous_combo:
			var end_time := Balance.estimated_time_for_height(previous_end)
			var breath := maxf(2.0 * Balance.PLAYER_VERTICAL_SPEED * Balance.speed_scale_for_time(end_time), height_for_time(end_time + 2.0) - previous_end)
			anchor = maxi(anchor, int(ceil(previous_end + breath - start)))
		if previous_route >= 0:
			var reaction_start := previous_end
			if previous_route == int(chosen.route) and not previous_recipe.is_empty() and route_survives(previous_recipe, previous_route):
				reaction_start = previous_anchor
			var available := Balance.estimated_time_for_height(start + float(anchor)) - Balance.estimated_time_for_height(reaction_start)
			if available - _transfer_seconds(previous_route, int(chosen.route)) < MIN_REACTION_SECONDS:
				for solution: Dictionary in solutions:
					if _transfer_seconds(previous_route, int(solution.route)) < _transfer_seconds(previous_route, int(chosen.route)):
						chosen = solution
				if previous_route == int(chosen.route) and not previous_recipe.is_empty() and route_survives(previous_recipe, previous_route):
					reaction_start = previous_anchor
			var required_anchor := height_for_time(Balance.estimated_time_for_height(reaction_start) + MIN_REACTION_SECONDS + _transfer_seconds(previous_route, int(chosen.route))) - start
			# One pixel above the boundary keeps subtraction rounding from making
			# the measured window smaller than 0.45 seconds.
			anchor = maxi(anchor, int(ceil(required_anchor)) + 1)
		encounter["anchor"] = anchor
		encounter["warning_height"] = anchor - WARNING_LEAD
		encounter["occupancy"] = [anchor, anchor + int(encounter.get("occupancy_height", OCCUPANCY_HEIGHT))]
		encounter["witness"] = int(chosen.route)
		previous_route = int(chosen.route)
		previous_end = start + float(encounter.occupancy[1])
		previous_anchor = start + float(anchor)
		previous_recipe = encounter.recipe
		previous_combo = String(encounter.recipe.kind) == "COMBO"
	stage_value["witness"] = stage_value.encounters.map(func(encounter: Dictionary) -> Variant: return encounter.witness)
	stage_value["length"] = maxi(int(stage_value.length), int(ceil(previous_end - start)))
	stage_value["nominal_duration_no_fire"] = float(stage_value.length) / Balance.PLAYER_VERTICAL_SPEED
	return {"route": previous_route, "end": previous_end, "anchor": previous_anchor, "recipe": previous_recipe, "combo": previous_combo}

static func _paced_encounters(stage: Dictionary) -> Array:
	var source: Array = stage.encounters
	var result: Array = []
	var target_count := int(stage.encounter_count)
	for index in target_count:
		var template: Dictionary = (source[index % source.size()] as Dictionary).duplicate(true)
		# Stage 1 starts targeting the idle center lane at the third encounter;
		# Stages 2-3 alternate beans with their authored teaching encounters.
		var use_bean := int(stage.number) >= 4 or (int(stage.number) == 1 and index >= 2 and index % 2 == 0) or (int(stage.number) in [2, 3] and index % 2 == 1)
		template["id"] = "S%02d-E%02d" % [int(stage.number), index + 1]
		if int(stage.number) == 3 and not use_bean and index > 0:
			template["witness"] = int((result[-1] as Dictionary).witness)
		if use_bean:
			# Trunk beans cycle across center, left and right. The first Stage 1
			# bean targets the no-input center lane; the first three cover every
			# fixed-position strategy while leaving two reachable safe lanes.
			var trunk_bean_index := int(index / 2) - 1 if int(stage.number) == 1 else int((index - 1) / 2)
			var trunk_cycle := [1, 0, 2]
			var blocked: int = int(trunk_cycle[trunk_bean_index % trunk_cycle.size()]) if int(stage.number) <= 2 else (index + int(stage.number)) % 3
			if int(stage.number) == 3:
				var preceding_supports: Array = (result[-1] as Dictionary).recipe.supports
				template["witness"] = int(preceding_supports[0])
				if index + 1 < target_count:
					var next_supports: Array = (source[(index + 1) % source.size()] as Dictionary).recipe.supports
					for supported_route in preceding_supports:
						if next_supports.has(supported_route):
							template["witness"] = int(supported_route)
							break
				for route in 3:
					if route != int(template.witness):
						blocked = route
						break
			template["recipe"] = {"kind": "BEAN", "lane": blocked, "count": 2 if int(stage.number) == 5 else 1}
			if int(stage.number) != 3:
				template["witness"] = (blocked + 1) % 3
			template["objective"] = "Read the warning and keep one safe route."
		result.append(template)
	_repace_anchors(result, stage, 500)
	return result

static func _repace_anchors(encounters: Array, stage: Dictionary, preferred_start: int) -> void:
	if encounters.is_empty():
		return
	var minimum_spacing := int(stage.min_encounter_spacing_px)
	var last_anchor := int(stage.length) - OCCUPANCY_HEIGHT
	var required_span := minimum_spacing * maxi(encounters.size() - 1, 0)
	var first_anchor := mini(preferred_start, last_anchor - required_span)
	first_anchor = maxi(first_anchor, WARNING_LEAD)
	for index in encounters.size():
		var progress := 0.0 if encounters.size() == 1 else float(index) / float(encounters.size() - 1)
		(encounters[index] as Dictionary)["anchor"] = int(round(lerpf(float(first_anchor), float(last_anchor), progress)))

static func _fallback_stage_length(stage_number: int) -> int:
	return DEFAULT_STAGE_LENGTH if stage_number <= 9 else DEFAULT_LATE_STAGE_LENGTH

## Each variant owns a resumable RNG cursor and only the live stage window.
static func _stream_for_variant(variant: String) -> Dictionary:
	if variant not in QA_VARIANTS:
		return {}
	if _sequence_cache.has(variant):
		return _sequence_cache[variant]
	var templates := canonical_stages()
	if variant == MIRROR_VARIANT:
		for template: Dictionary in templates:
			template["witness"] = _mirror_sequence(template.witness)
			for encounter: Dictionary in template.encounters:
				encounter["witness"] = _mirror_position(encounter.witness)
				_mirror_recipe(encounter.recipe)
	var rng := RandomNumberGenerator.new()
	rng.seed = active_run_seed
	var stream := {"templates": templates, "rng": rng, "records": {}, "recent": [], "next": 1, "height": 0, "last_dead_end_time": -INF, "lane_order": [2, 1, 0] if variant == MIRROR_VARIANT else [0, 1, 2]}
	_sequence_cache[variant] = stream
	return stream

static func stages_for_variant(variant: String) -> Array:
	var stream := _stream_for_variant(variant)
	if stream.is_empty():
		return []
	if stream.records.is_empty():
		stage(Balance.STAGES_AHEAD + 1, variant)
	return stream.records.values().duplicate(true)

static func retain_from(first_stage: int, variant: String) -> void:
	var stream := _stream_for_variant(variant)
	for number in stream.get("records", {}).keys():
		if int(number) < first_stage:
			stream.records.erase(number)

static func _generate_through(stage_number: int, stream: Dictionary) -> void:
	var rng: RandomNumberGenerator = stream.rng
	var templates: Array = stream.templates
	var recent_templates: Array = stream.recent
	while int(stream.next) <= stage_number:
		var number := int(stream.next)
		var accumulated_height := int(stream.height)
		var tier := Balance.difficulty_tier_for_time(Balance.estimated_time_for_height(float(accumulated_height)))
		var template_number := number
		if number >= 4:
			var pool: Array[int] = []
			var last_template: int = [8, 14, 22, 30][tier]
			for candidate in range(4, last_template + 1):
				if not recent_templates.has(candidate):
					pool.append(candidate)
			template_number = pool[rng.randi_range(0, pool.size() - 1)]
		var stage: Dictionary = templates[template_number - 1].duplicate(true)
		stage["number"] = number
		stage["template"] = template_number
		stage["tier"] = tier
		stage["start_height"] = accumulated_height
		# Template encounter IDs repeat; runtime IDs must identify this chunk.
		for index in stage.encounters.size():
			stage.encounters[index]["id"] = "S%02d-E%02d" % [number, index + 1]
		if number >= 4:
			stage["encounters"] = _endless_encounters(stage, stream)
		stream["last_solution"] = _repair_reaction_windows(stage, stream.get("last_solution", {}))
		accumulated_height += int(stage.length)
		stage["target_height"] = accumulated_height
		# Include the authored Stage 3 forks in the persistent cadence cursor.
		for encounter: Dictionary in stage.encounters:
			for threat: Dictionary in threats_for_recipe(encounter.recipe):
				if String(threat.kind) == "FORK":
					stream.last_dead_end_time = Balance.estimated_time_for_height(float(stage.start_height) + float(encounter.anchor))
		stream.records[number] = stage
		stream.next = number + 1
		stream.height = accumulated_height
		# Also bound direct database requests that skip ahead.
		for old_number in stream.records.keys():
			if int(old_number) < number - Balance.STAGE_WINDOW_SIZE + 1:
				stream.records.erase(old_number)
		recent_templates.append(template_number)
		if recent_templates.size() > 3:
			recent_templates.pop_front()

static func _endless_encounters(stage_value: Dictionary, stream: Dictionary) -> Array:
	var rng: RandomNumberGenerator = stream.rng
	var result: Array = []
	var kinds := [["BEAN", "S", "R"], ["THORN", "K"], ["ARCH", "WEB", "M"]]
	var classes := ["LANE", "LOW", "HIGH"]
	var anchor := WARNING_LEAD
	for index in int(stage_value.encounter_count):
		var seconds := Balance.estimated_time_for_height(float(stage_value.start_height) + anchor)
		var tier := Balance.difficulty_tier_for_time(seconds)
		# Rotating class pairs also prevents a secondary class from appearing
		# in three successive encounters, including across chunk boundaries.
		var action_class := (int(stream.get("last_class", rng.randi_range(0, 2))) + 1) % 3
		stream["last_class"] = action_class
		var lane := rng.randi_range(0, 2)
		var catalog: Array = kinds[action_class]
		var threats := [_hazard(String(catalog[rng.randi_range(0, catalog.size() - 1)]), lane)]
		if tier > 0:
			var second_class := (action_class + 1) % 3
			var second_catalog: Array = kinds[second_class]
			threats.append(_hazard(String(second_catalog[rng.randi_range(0, second_catalog.size() - 1)]), (lane + 1) % 3))
			if (action_class == 0 or second_class == 0) and seconds - float(stream.last_dead_end_time) >= ENDLESS_DEAD_END_INTERVAL_SECONDS:
				threats.append({"kind": "FORK", "supports": [lane, (lane + 2) % 3]})
				stream.last_dead_end_time = seconds
		var recipe: Dictionary = threats[0] if threats.size() == 1 else {"kind": "COMBO", "threats": threats}
		var solutions := encounter_solutions(recipe)
		var chosen: Dictionary = solutions[rng.randi_range(0, solutions.size() - 1)]
		result.append({"id": "S%02d-E%02d" % [int(stage_value.number), index + 1], "anchor": anchor, "occupancy_height": 90, "recipe": recipe, "witness": int(chosen.route), "action_class": classes[action_class], "objective": "Read the threat, then breathe."})
		anchor += 90 + int(ceil(Balance.PLAYER_VERTICAL_SPEED * Balance.speed_scale_for_time(seconds) * (2.2 if tier > 0 else 1.2)))
	return result

static func _mirror_recipe(recipe: Dictionary) -> void:
	match String(recipe.kind):
		"GUIDE", "BULGE":
			recipe["x"] = 1.0 - float(recipe.x)
		"FORK":
			recipe["supports"] = _mirror_sequence(recipe.supports)
		"BEAN", "S", "R", "THORN", "ARCH", "K", "WEB", "M":
			recipe["lane"] = 2 - int(recipe.lane)
		"WALL":
			recipe["lanes"] = _mirror_sequence(recipe.lanes)
		"COMBO":
			for threat: Dictionary in recipe.threats: _mirror_recipe(threat)

static func stage(stage_number: int, variant := CANONICAL_VARIANT) -> Dictionary:
	var stream := _stream_for_variant(variant)
	if stage_number < 1 or stream.is_empty():
		return {}
	_generate_through(stage_number, stream)
	return stream.records.get(stage_number, {}).duplicate(true)

static func template_for(n: int) -> int:
	return int(stage(n).get("template", 0))

static func _mirror_sequence(values: Array) -> Array:
	var result: Array = []
	for value in values:
		result.append(_mirror_position(value))
	return result

static func _mirror_position(value: Variant) -> Variant:
	if value is int:
		return 2 - int(value)
	if value is float:
		return 1.0 - float(value)
	return value
