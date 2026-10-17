extends SceneTree

var failures := 0
var completions := 0
var finish_signals := 0

func _init() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	# A cache/lifecycle test, not a gameplay or FPS acceptance run.
	check(load("res://scenes/main.tscn") != null, "Main scene and inherited renderer compile")
	var fixture := Node2D.new()
	fixture.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(fixture)
	var stages := StageManager.new()
	stages.name = "StageManager"
	fixture.add_child(stages)
	stages.reset_run(20260923)
	stages.stage_completed.connect(func(_n: int): completions += 1)
	stages.prototype_completed.connect(func(): finish_signals += 1)
	var player := PlayerController.new()
	player.name = "Player"
	fixture.add_child(player)
	var spider := SpiderController.new()
	spider.name = "Spider"
	fixture.add_child(spider)
	var beans := BeanSpawner.new()
	fixture.add_child(beans)
	var rocks := RockManager.new()
	fixture.add_child(rocks)
	rocks.setup(player, stages)
	var storm := StormMechanics.new()
	fixture.add_child(storm)
	var economy := EconomyManager.new()
	check(economy._load_local_config(), "Economy config loads without writing a save")
	var golds := GoldManager.new()
	fixture.add_child(golds)
	golds.setup(player, stages, economy, null)

	# Independent copy of the previous selection rule; retain only its cursor.
	var rng := RandomNumberGenerator.new()
	rng.seed = stages.run_seed
	var templates := StageDatabase.canonical_stages()
	var recent: Array[int] = []
	var height := 0
	var initial := var_to_str(stages.patterns)
	var maximum_nodes := 0
	var maximum_records := 0
	var maximum_coins := 0
	var maximum_rocks := 0
	for number in range(1, 601):
		var tier := Balance.difficulty_tier_for_time(Balance.estimated_time_for_height(height))
		var chosen := number
		if number >= 4:
			var pool: Array[int] = []
			for candidate in range(4, [8, 14, 22, 30][tier] + 1):
				if not recent.has(candidate): pool.append(candidate)
			chosen = pool[rng.randi_range(0, pool.size() - 1)]
		var record: Dictionary = stages.stage_records[number]
		check(int(record.template) == chosen and int(record.tier) == tier and int(record.start_height) == height, "Legacy seeded selection/height at %d" % number)
		check(record.encounters.size() == templates[chosen - 1].encounters.size(), "Authored encounters at %d" % number)
		recent.append(chosen)
		if recent.size() > 3: recent.pop_front()
		height += int(record.length)
		player.position = Vector2(10000.0, -float(height) + 1.0)
		check(stages.stage_for_y(player.position.y) == number, "Stage lookup at %d" % number)
		golds.refresh_active_window()
		rocks.refresh_active_window()
		storm.refresh_active_window()
		beans._physics_process(0.0)
		# Exercise retirement of collected/hit/warning IDs as well as catalogs.
		for placement: Dictionary in golds.placements_by_stage.get(number, []):
			golds.collected_ids[String(placement.id)] = true
		for hazard in rocks.hazards:
			rocks.hit_ids[hazard.hazard_id] = true
			rocks.warning_ids[hazard.hazard_id] = true
		stages.set_runtime_break(number, 0, 10.0, 20.0, true)
		stages.set_runtime_web(number, 1, 10.0, 20.0, true)
		await process_frame # Drain queue_free; count live nodes, not queued ones.
		maximum_nodes = maxi(maximum_nodes, fixture.get_child_count() + golds.get_child_count() + rocks.get_child_count() + beans.get_child_count())
		maximum_records = maxi(maximum_records, stages.stage_records.size())
		maximum_coins = maxi(maximum_coins, golds.get_child_count())
		maximum_rocks = maxi(maximum_rocks, rocks.hazards.size())
		check(stages.stage_records.size() <= Balance.STAGE_WINDOW_SIZE and stages.patterns.size() <= Balance.STAGE_WINDOW_SIZE and stages.pattern_by_stage.size() <= Balance.STAGE_WINDOW_SIZE, "Bounded manager at %d" % number)
		check(StageDatabase._sequence_cache[stages.run_variant].records.size() <= Balance.STAGE_WINDOW_SIZE, "Bounded database at %d" % number)
		check(golds.placements_by_stage.size() <= 3 and golds.loaded_stages.size() <= 3 and golds.collected_ids.size() <= 120 and golds.combo_ahead_ids.size() <= 120, "Bounded coins at %d" % number)
		check(rocks.campaign_slots_by_stage.size() <= 3 and rocks.loaded_stages.size() <= 3 and rocks.hit_ids.size() <= 48 and rocks.warning_ids.size() <= 48, "Bounded rocks at %d" % number)
		check(storm.campaign_slots_by_stage.size() <= 3 and beans.spawned_keys.size() <= 96 and beans.get_child_count() <= 96, "Bounded storm/beans at %d" % number)
		check(stages.runtime_breaks.size() <= Balance.STAGE_WINDOW_SIZE and stages.runtime_webs.size() <= Balance.STAGE_WINDOW_SIZE, "Bounded runtime hazards at %d" % number)
		check(golds.get_child_count() <= 120 and rocks.hazards.size() <= 48, "Bounded live nodes at %d" % number)
		if number in [30, 240, 600]:
			print("stage=%d records=%d patterns=%d db=%d coin_catalog=%d rock_catalog=%d storm_catalog=%d beans=%d" % [number, stages.stage_records.size(), stages.patterns.size(), StageDatabase._sequence_cache[stages.run_variant].records.size(), golds.placements_by_stage.size(), rocks.campaign_slots_by_stage.size(), storm.campaign_slots_by_stage.size(), beans.spawned_keys.size()])
		stages.update_progress(-float(height))

	check(completions == 600 and stages.current_stage == 601 and finish_signals == 0, "No 240-stage ending")
	check(stages.support_segments(1, 0).is_empty() and stages.pattern_for_stage(1).is_empty() and not stages.stage_records.has(1), "Retired chunk is empty")
	check(is_equal_approx(stages.stage_bottom_y(3), -3220.0), "Fixed Stage 3 fork survives eviction")
	check(Balance.difficulty_tier_for_time(19.99) == 0 and Balance.difficulty_tier_for_time(20.0) == 1 and Balance.difficulty_tier_for_time(40.0) == 2 and Balance.difficulty_tier_for_time(60.0) == 3, "20/40/60 tiers")
	check(is_equal_approx(Balance.speed_scale_for_time(180.0), 2.0), "180-second speed ramp")
	stages.reset_run(20260923)
	check(var_to_str(stages.patterns) == initial, "Same-seed restart rewinds route")
	print("ENDLESS-WINDOW: completed=%d next=601 finish_signals=%d max_records=%d max_live_nodes=%d max_coins=%d max_rocks=%d FAIL=%d" % [completions, finish_signals, maximum_records, maximum_nodes, maximum_coins, maximum_rocks, failures])
	fixture.free()
	quit(0 if failures == 0 else 1)
