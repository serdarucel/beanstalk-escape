class_name MissionManager
extends Node

signal mission_completed(text: String)
signal mission_set_completed

const MISSIONS_PATH := "res://config/missions.json"
const MISSION_TYPES := ["jump", "hug", "clear_low", "clear_high", "lane_change", "coins", "meters", "powerups", "magnet_coins", "no_stumble_seconds"]

var save_manager: RefCounted
var sets: Array = []
var set_index := 0
var progress: Dictionary = {}
var _multiplier := 1

func initialize(save: RefCounted) -> bool:
	var file := FileAccess.open(MISSIONS_PATH, FileAccess.READ)
	if file == null or save == null:
		return false
	var data: Variant = JSON.parse_string(file.get_as_text())
	if data is not Dictionary or data.get("sets") is not Array:
		return false
	var loaded: Array = data.sets
	var ids := {}
	for entry in loaded:
		if entry is not Dictionary or entry.get("missions") is not Array or entry.missions.size() != 3:
			return false
		for mission in entry.missions:
			if mission is not Dictionary:
				return false
			if str(mission.get("id", "")).is_empty() or ids.has(mission.id) or mission.get("type", "") not in MISSION_TYPES:
				return false
			if mission.get("scope", "") not in ["run", "total"] or str(mission.get("text", "")).is_empty():
				return false
			var target: Variant = mission.get("target", 0)
			if (target is not int and target is not float) or not is_finite(float(target)) or float(target) <= 0.0:
				return false
			ids[mission.id] = true
	sets = loaded.duplicate(true)
	if save_manager != null and save_manager.profile_loaded.is_connected(_on_profile_loaded):
		save_manager.profile_loaded.disconnect(_on_profile_loaded)
	save_manager = save
	save_manager.profile_loaded.connect(_on_profile_loaded)
	_restore()
	return not sets.is_empty()

func _on_profile_loaded(_profile: Dictionary) -> void:
	_restore()

func _restore() -> void:
	var state: Dictionary = save_manager.missions_snapshot()
	set_index = clampi(int(state.set_index), 0, sets.size())
	progress = state.progress.duplicate(true)
	_multiplier = clampi(int(state.multiplier), 1, 30)

func active_missions() -> Array:
	if set_index >= sets.size():
		return []
	return sets[set_index].missions.duplicate(true)

func begin_run() -> void:
	for mission in active_missions():
		if mission.scope == "run":
			progress[mission.id] = 0.0
	_persist()

func end_run() -> void:
	_persist()

# Amount is an event delta, including meters and clean elapsed seconds.
# A zero no_stumble_seconds notification resets the current clean streak.
func notify(type: String, amount: float = 1.0) -> void:
	var delta := float(amount)
	if save_manager == null or not is_finite(delta) or delta < 0.0:
		return
	var completed_texts: Array[String] = []
	var changed := false
	for mission in active_missions():
		if mission.type != type:
			continue
		var previous := float(progress.get(mission.id, 0.0))
		var target := float(mission.target)
		if previous >= target:
			continue
		var current := 0.0 if type == "no_stumble_seconds" and delta == 0.0 else minf(previous + delta, target)
		progress[mission.id] = current
		changed = changed or current != previous
		if current >= target:
			completed_texts.append(str(mission.text))
	if not changed:
		return
	var all_completed := not active_missions().is_empty()
	for mission in active_missions():
		all_completed = all_completed and float(progress.get(mission.id, 0.0)) >= float(mission.target)
	if all_completed:
		set_index += 1
		_multiplier = mini(_multiplier + 1, 30)
		progress = {}
	_persist()
	for text in completed_texts:
		mission_completed.emit(text)
	if all_completed:
		mission_set_completed.emit()

func score_multiplier() -> int:
	return _multiplier

func _persist() -> void:
	if save_manager != null:
		save_manager.write_missions({"set_index": set_index, "progress": progress, "multiplier": _multiplier})
