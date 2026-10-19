class_name PlayerVisual
extends Node2D

const FRAME_ROOT := "res://assets/art/character_frames"
const EXPLORER_ROOT := "res://assets/art/character3d"
const EXPLORER_OUTFITS := preload("res://scripts/explorer_outfits.gd")
const EXPLORER_KINDS := {"M1": "erkek", "F1": "kadin"}
const EXPLORER_ANIMS := ["climb", "hang", "lane_left", "lane_right", "jump", "slide", "fall", "hit", "death", "respawn", "fly", "front"]
const WING_TEXTURE := preload("res://assets/art/character_rig/wing/time_wings.png")
const TRANSFER_LEAF_TEXTURE := preload("res://assets/art/fx/transfer_leaf.png")
const ROCK_FIRE_ATLAS := preload("res://assets/art/hazards/rock_fire_atlas.png")
const FAIRY_EFFECT := preload("res://scripts/fairy_effect.gd")
const OUTFIT_EFFECT := preload("res://scripts/outfit_effect.gd")
const OUTFIT_ROOT := "res://assets/art/outfits"
const OUTFIT_FRONT_WIDTHS := {
	"outfit_moss": 182.0, "outfit_fern": 182.0, "outfit_sky": 182.0,
	"outfit_ocean": 182.0, "outfit_plum": 182.0, "outfit_ember": 183.0,
	"outfit_clay": 191.0, "outfit_sun": 184.0, "outfit_night": 287.0,
}
const BACK_FRAME_WIDTHS := {
	"climb_left": 109.0, "climb_right": 108.0, "climb_reach": 106.0,
	"hang": 112.0, "jump": 189.0, "hurt": 129.0, "fall": 191.0, "cheer": 136.0,
}
const FRAME_NAMES := ["climb_left", "climb_right", "climb_reach", "hang"]
const SKIN_IDS := ["M1", "M2", "M3", "F1", "F2", "F3"]
const FRAME_RATE := 8.0
const ART_SCALE := 0.49
const BASE_Y := -7.2
const EXPLORER_SCALE := 238.0 * ART_SCALE / 201.0
const GAMEPLAY_VISUAL_SCALE := 4.15
const EXPLORER_FOOT_Y := BASE_Y + (269.0 - 300.0 * 0.5) * ART_SCALE
const WINGS_TARGET_WIDTH := ScaleLock.CHARACTER_WIDTH * 1.8
const TIME_WINGS_VISIBLE_RATIO := 1344.0 / 1415.0
const FIRE_WINGS_REGION_SIZE := Vector2(512, 512)
const FIRE_WINGS_VISIBLE_RATIO := 465.0 / 512.0
const FIRE_WINGS_TARGET_SCALE := WINGS_TARGET_WIDTH / (FIRE_WINGS_REGION_SIZE.x * FIRE_WINGS_VISIBLE_RATIO)
const FIRE_TRAIL_REFERENCE_SCALE := 0.32
const TIME_WINGS_REVEAL_SECONDS := 0.18
# Normalized source clasp position, independent of the texture import size.
const TIME_WING_ROOT_UV := Vector2(707.0 / 1415.0, 584.0 / 1111.0)
const FIRE_WING_ROOT := Vector2(256, 320) # Relative to the 512 x 512 atlas region.
# Original trail coordinates relative to the fire clasp at its base scale.
const FIRE_TRAIL_ROOT := Vector2(0, -12) + (FIRE_WING_ROOT - Vector2(256, 256)) * FIRE_TRAIL_REFERENCE_SCALE
const PET_PREVIEW_HEIGHT := 60.0
const PET_PREVIEW_BOUNDS := {}

var gameplay_visual_mult := 1.0
var skin_id := "M1"
var mode := "hang"
var frame_name := "hang"
var climb_time := 0.0
var hurt_remaining := 0.0
var hurt_flash_remaining := 0.0
var celebrate_remaining := 0.0
var death_offset := 0.0
var last_penalty := 0
var frame_textures: Dictionary = {}
var sprite: Sprite2D
var time_wings: Sprite2D
var fire_wings: Sprite2D
var takeoff_particles: CPUParticles2D
var transfer_trails: Array[Line2D] = []
var fire_trails: Array[Polygon2D] = []
var flash_material: ShaderMaterial
var cosmetic_sprites: Dictionary = {}
var equipped_cosmetics := {"OUTFIT": "", "PET": ""}
var cosmetic_data: Dictionary = {}
var anchor_data: Dictionary = {}
var frame_metrics: Dictionary = {}
var fairy_effect: FairyEffect
var outfit_aura: OutfitEffect
var outfit_effect: OutfitEffect
var outfit_back_sprite: Sprite2D
var outfit_front_texture: Texture2D
var outfit_frame_textures: Dictionary = {}
var pet_preview_time := 0.0
var pet_preview_scale := Vector2.ONE
var _was_transferring := false
var _transfer_trail_alpha := 0.0
var _last_transfer_direction := 1.0
var _time_wings_reveal := 0.0
var _time_wings_was_active := false
var _time_wings_target_scale := WINGS_TARGET_WIDTH / (WING_TEXTURE.get_width() * TIME_WINGS_VISIBLE_RATIO)
var _explorer_meta: Dictionary = {}
var _explorer_masks: Dictionary = {}
var _explorer_outfit := ""
var _explorer_kind := ""
var _explorer_anim_time := 0.0
var _explorer_previous_app_state := -1
var _explorer_respawning := false
var _explorer_scale := EXPLORER_SCALE

func _ready() -> void:
	if get_parent() is PlayerController:
		gameplay_visual_mult = GAMEPLAY_VISUAL_SCALE
	_build_visual()
	_load_skin(OS.get_environment("BEANSTALK_SKIN"))
	_set_frame("hang")

func _process(delta: float) -> void:
	var player := get_parent() as PlayerController
	if player == null:
		return
	var penalty_count := player.bean_penalty_count + player.rock_penalty_count
	if penalty_count != last_penalty:
		last_penalty = penalty_count
		hurt_remaining = 0.32
		hurt_flash_remaining = 0.12
	hurt_remaining = maxf(hurt_remaining - delta, 0.0)
	hurt_flash_remaining = maxf(hurt_flash_remaining - delta, 0.0)
	celebrate_remaining = maxf(celebrate_remaining - delta, 0.0)
	if player.time_wings_active and not _time_wings_was_active:
		_time_wings_reveal = 0.0
	if player.time_wings_active:
		_time_wings_reveal = minf(_time_wings_reveal + delta / TIME_WINGS_REVEAL_SECONDS, 1.0)
		var reveal := smoothstep(0.0, 1.0, _time_wings_reveal)
		var wing_pulse := sin(Time.get_ticks_msec() * 0.010) * 0.01
		var reveal_scale := _time_wings_target_scale * gameplay_visual_mult * lerpf(0.70, 1.0, reveal)
		time_wings.scale = reveal_scale * Vector2(1.0 + wing_pulse, 1.0 - wing_pulse * 0.5)
		time_wings.modulate.a = reveal
		time_wings.visible = true
	else:
		_time_wings_reveal = 0.0
		time_wings.modulate.a = 0.0
		time_wings.visible = false
	_time_wings_was_active = player.time_wings_active
	fire_wings.visible = player.fire_wings_active
	for trail in fire_trails: trail.visible = player.fire_wings_active
	if fire_wings.visible:
		var fire_pulse := sin(Time.get_ticks_msec() * 0.014) * 0.01
		fire_wings.scale = FIRE_WINGS_TARGET_SCALE * gameplay_visual_mult * Vector2(1.0 + fire_pulse, 1.0 - fire_pulse * 0.35)
		for index in fire_trails.size():
			fire_trails[index].scale = fire_wings.scale / FIRE_TRAIL_REFERENCE_SCALE
			fire_trails[index].modulate.a = 0.55 + 0.18 * sin(Time.get_ticks_msec() * 0.018 + float(index) * PI)
	_update_mode(player, delta)
	flash_material.set_shader_parameter("flash_amount", 0.45 if hurt_flash_remaining > 0.0 else 0.0)
	_update_cosmetic_anchors()

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.physical_keycode == KEY_1:
		set_skin("M1")
	elif event.physical_keycode == KEY_2:
		set_skin("F1")

func _update_mode(player: PlayerController, delta: float) -> void:
	var game := player.get_parent()
	var app_state := int(game.get("app_state")) if game != null else GameManager.AppState.MENU
	if app_state == GameManager.AppState.PAUSED:
		return
	if _is_explorer():
		_update_explorer_mode(player, app_state, delta)
		return
	if app_state in [GameManager.AppState.MENU, GameManager.AppState.INTRO, GameManager.AppState.SHOP, GameManager.AppState.CHARACTER_SELECT, GameManager.AppState.MAP, GameManager.AppState.CREDITS]:
		_set_mode("menu", "hang")
	elif app_state == GameManager.AppState.PLAYER_DEAD:
		if mode != "death":
			death_offset = 0.0
		death_offset = minf(death_offset + delta * 76.0, 92.0)
		_set_mode("death", "fall")
		sprite.position = Vector2(0.0, BASE_Y + death_offset)
	elif player.support_state == PlayerController.SupportState.TRANSFERRING:
		var direction := signf(Balance.ROUTE_X[player.transition_to] - Balance.ROUTE_X[player.transition_from])
		scale.x = absf(scale.x) * (-1.0 if direction < 0.0 else 1.0)
		_last_transfer_direction = direction
		if not _was_transferring:
			takeoff_particles.restart()
			takeoff_particles.emitting = true
		_was_transferring = true
		_set_mode("jump", "jump")
	elif app_state == GameManager.AppState.GAME_COMPLETE or (app_state != GameManager.AppState.PLAYING and celebrate_remaining > 0.0):
		_set_mode("celebrate", "cheer")
	elif hurt_remaining > 0.0:
		_set_mode("hurt", "hurt")
	elif player.support_state == PlayerController.SupportState.FALLING_RECOVERY:
		_set_mode("fall", "fall")
	else:
		mode = "climb"
		climb_time += delta * FRAME_RATE
		var frame_index := int(floor(climb_time)) % FRAME_NAMES.size()
		_set_frame(FRAME_NAMES[frame_index])
		# A full alternating hand cycle yields a clearly readable 3.5 px body lift.
		sprite.position = Vector2(0.0, BASE_Y - 3.5 * absf(sin(climb_time * PI * 0.5)))
	if player.support_state != PlayerController.SupportState.TRANSFERRING:
		scale.x = absf(scale.x)
		_was_transferring = false
	_update_transfer_trails(player.support_state == PlayerController.SupportState.TRANSFERRING, delta)

func _is_explorer() -> bool:
	return EXPLORER_KINDS.has(skin_id)

func _sprite_base_position() -> Vector2:
	return Vector2(0.0, EXPLORER_FOOT_Y if _is_explorer() else BASE_Y)

func _update_explorer_mode(player: PlayerController, app_state: int, delta: float) -> void:
	var menu_states := [GameManager.AppState.MENU, GameManager.AppState.INTRO, GameManager.AppState.SHOP, GameManager.AppState.CHARACTER_SELECT, GameManager.AppState.MAP, GameManager.AppState.CREDITS]
	if app_state == GameManager.AppState.PLAYING and (_explorer_previous_app_state == -1 or _explorer_previous_app_state == GameManager.AppState.PLAYER_DEAD or _explorer_previous_app_state in menu_states):
		_explorer_respawning = true
		_explorer_anim_time = 0.0
		hurt_remaining = 0.0
	_explorer_previous_app_state = app_state
	scale.x = absf(scale.x)
	sprite.position = _sprite_base_position()
	var transferring := false
	if app_state in menu_states:
		_explorer_respawning = false
		mode = "menu"
		_animate_explorer("hang", delta)
	elif app_state == GameManager.AppState.PLAYER_DEAD:
		_explorer_respawning = false
		if mode != "death":
			death_offset = 0.0
		mode = "death"
		death_offset = minf(death_offset + delta * 76.0, 92.0)
		sprite.position.y += death_offset
		_animate_explorer("death", delta)
	elif player.support_state == PlayerController.SupportState.TRANSFERRING:
		_explorer_respawning = false
		transferring = true
		var direction := signf(Balance.ROUTE_X[player.transition_to] - Balance.ROUTE_X[player.transition_from])
		_last_transfer_direction = -1.0 if direction < 0.0 else 1.0
		takeoff_particles.scale.x = _last_transfer_direction
		if not _was_transferring:
			takeoff_particles.restart()
			takeoff_particles.emitting = true
		mode = "jump"
		var animation := "lane_left" if direction < 0.0 else "lane_right"
		var frames := int(_explorer_meta["anims"][animation]["frames"])
		_set_explorer_frame(animation, int(clampf(player.transition_progress, 0.0, 1.0) * float(frames - 1)))
	elif hurt_remaining > 0.0:
		_explorer_respawning = false
		mode = "hurt"
		_animate_explorer("hit", delta)
	elif player.support_state == PlayerController.SupportState.FALLING_RECOVERY:
		_explorer_respawning = false
		mode = "fall"
		_animate_explorer("fall", delta)
	elif _explorer_respawning:
		mode = "respawn"
		_animate_explorer("respawn", delta)
		var respawn: Dictionary = _explorer_meta["anims"]["respawn"]
		if _explorer_anim_time >= float(respawn["frames"]) / float(respawn["fps"]):
			_explorer_respawning = false
			mode = "climb"
			_animate_explorer("climb", 0.0)
	elif player.is_airborne():
		mode = "jump"
		var frames := int(_explorer_meta["anims"]["jump"]["frames"])
		var progress := clampf(1.0 - player.action_remaining / maxf(player.action_total, 0.00001), 0.0, 1.0)
		_set_explorer_frame("jump", int(progress * float(frames - 1)))
	elif player.is_hugging():
		mode = "slide"
		var frames := int(_explorer_meta["anims"]["slide"]["frames"])
		var progress := clampf(1.0 - player.action_remaining / maxf(player.action_total, 0.00001), 0.0, 1.0)
		_set_explorer_frame("slide", int(progress * float(frames - 1)))
	elif player.time_wings_active or player.fire_wings_active:
		mode = "fly"
		_animate_explorer("fly", delta)
	else:
		mode = "climb"
		_animate_explorer("climb", delta)
	# Manual jump/slide follow action progress; lane transfers and hit keep priority.
	_was_transferring = transferring
	_update_transfer_trails(transferring, delta)

func _animate_explorer(animation: String, delta: float) -> void:
	if frame_name != animation:
		_explorer_anim_time = 0.0
	else:
		_explorer_anim_time += delta
	var data: Dictionary = _explorer_meta["anims"][animation]
	var frames := int(data["frames"])
	var index := int(floor(_explorer_anim_time * float(data.get("fps", 1.0))))
	index = index % frames if bool(data.get("loop", false)) else mini(index, frames - 1)
	_set_explorer_frame(animation, index)

func _set_explorer_frame(animation: String, index: int) -> void:
	if frame_name != animation:
		_explorer_anim_time = 0.0
	frame_name = animation
	var data: Dictionary = _explorer_meta["anims"][animation]
	var texture := frame_textures[animation] as Texture2D
	if sprite.texture != texture:
		sprite.frame = 0
		sprite.hframes = 1
		sprite.vframes = 1
		sprite.texture = texture
		sprite.hframes = int(data.get("cols", data["frames"]))
		sprite.vframes = int(data.get("rows", 1))
		EXPLORER_OUTFITS.configure(flash_material, _explorer_outfit, _explorer_masks.get(animation) as Texture2D)
	var cell: Array = data.get("cell", [_explorer_meta.get("frame_w", 256), _explorer_meta.get("frame_h", 256)])
	var pivot: Array = data.get("pivot", _explorer_meta.get("pivot", [128, 240]))
	sprite.offset = Vector2(float(cell[0]), float(cell[1])) * 0.5 - Vector2(float(pivot[0]), float(pivot[1]))
	sprite.frame = clampi(index, 0, int(data["frames"]) - 1)
	# Cropped grids have only 8px gutters: keep the enlarged soft shadow in its cell.
	var uv_rect := Vector4(0.0, 0.0, 1.0, 1.0)
	if data.has("cell"):
		var col := sprite.frame % sprite.hframes
		var row := floori(float(sprite.frame) / float(sprite.hframes))
		uv_rect = Vector4(float(col) / sprite.hframes, float(row) / sprite.vframes, float(col + 1) / sprite.hframes, float(row + 1) / sprite.vframes)
	flash_material.set_shader_parameter("frame_uv_rect", uv_rect)

func _update_transfer_trails(transferring: bool, delta: float) -> void:
	if transferring:
		_transfer_trail_alpha = 1.0
	else:
		_transfer_trail_alpha = maxf(_transfer_trail_alpha - delta / 0.28, 0.0)
	for trail in transfer_trails:
		# The whole body is mirrored in flight. Preserve that world-space side
		# while the residual trail fades after the body returns to +X scale.
		trail.scale.x = _last_transfer_direction if _is_explorer() or not transferring else 1.0
		trail.modulate.a = _transfer_trail_alpha
		trail.visible = _transfer_trail_alpha > 0.0

func _set_mode(new_mode: String, requested_frame: String) -> void:
	if mode != new_mode:
		mode = new_mode
		sprite.position = Vector2(0.0, BASE_Y)
	_set_frame(requested_frame)

func _set_frame(requested_frame: String) -> void:
	if _is_explorer():
		_set_explorer_frame(requested_frame if frame_textures.has(requested_frame) else "hang", 0)
		_update_cosmetic_anchors()
		return
	var requested_texture := frame_textures.get(requested_frame) as Texture2D
	if requested_frame == "front" and outfit_front_texture != null:
		requested_texture = outfit_front_texture
	elif outfit_frame_textures.has(requested_frame):
		requested_texture = outfit_frame_textures[requested_frame] as Texture2D
	if frame_name == requested_frame and sprite.texture == requested_texture:
		return
	frame_name = requested_frame
	sprite.texture = requested_texture
	_update_cosmetic_anchors()

func set_skin(requested_skin: String) -> bool:
	var normalized := requested_skin.to_upper()
	if normalized not in SKIN_IDS or not _skin_exists(normalized):
		return false
	_load_skin(normalized)
	return true

func _load_skin(requested_skin: String) -> void:
	var normalized := requested_skin.to_upper()
	skin_id = normalized if normalized in SKIN_IDS and _skin_exists(normalized) else "M1"
	frame_metrics.clear()
	if _is_explorer():
		_explorer_previous_app_state = -1
		_load_outfit_art()
		var current := frame_name
		frame_name = ""
		_set_frame(current)
		return
	flash_material.set_shader_parameter("outline_source_px", 4.1)
	flash_material.set_shader_parameter("shadow_source_offset", Vector2(0.0, 7.0))
	flash_material.set_shader_parameter("shadow_source_blur", 3.0)
	flash_material.set_shader_parameter("frame_uv_rect", Vector4(0.0, 0.0, 1.0, 1.0))
	EXPLORER_OUTFITS.configure(flash_material, "", null)
	_explorer_masks.clear()
	frame_textures.clear()
	if not _explorer_kind.is_empty():
		sprite.frame = 0
		sprite.hframes = 1
		sprite.vframes = 1
		sprite.offset = Vector2.ZERO
		sprite.scale = Vector2.ONE * ART_SCALE
		sprite.position = _sprite_base_position()
		takeoff_particles.scale.x = 1.0
	_explorer_meta.clear()
	_explorer_kind = ""
	_explorer_outfit = ""
	for requested_frame in ["climb_left", "climb_right", "climb_reach", "jump", "hurt", "fall", "cheer", "hang", "front"]:
		var frame_texture := load("%s/%s/%s.png" % [FRAME_ROOT, skin_id.to_lower(), requested_frame]) as Texture2D
		frame_textures[requested_frame] = frame_texture
		# Keep the WebGL path GPU-only: texture readback emits INVALID_OPERATION on
		# some compatibility renderers while the shop preview is being rebuilt.
		var texture_size := frame_texture.get_size()
		frame_metrics[requested_frame] = {
			"texture_size": texture_size,
			"used": Rect2i(Vector2i.ZERO, Vector2i(int(texture_size.x), int(texture_size.y * 0.75))),
		}
	_load_anchors()
	_load_outfit_art()
	var current := frame_name
	frame_name = ""
	_set_frame(current)

func _skin_exists(requested_skin: String) -> bool:
	if EXPLORER_KINDS.has(requested_skin):
		return ResourceLoader.exists("%s/%s/base/hang.png" % [EXPLORER_ROOT, EXPLORER_KINDS[requested_skin]])
	return ResourceLoader.exists("%s/%s/hang.png" % [FRAME_ROOT, requested_skin.to_lower()])

func _load_anchors() -> void:
	anchor_data.clear()
	var path := "%s/%s/anchors.json" % [FRAME_ROOT, skin_id.to_lower()]
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		anchor_data = (parsed as Dictionary).get("frames", {}).duplicate(true)

func set_cosmetics(equipped: Dictionary, catalog: Array) -> void:
	equipped_cosmetics = equipped.duplicate(true)
	cosmetic_data.clear()
	for item in catalog:
		cosmetic_data[str(item.get("id", ""))] = item
	for slot in ["PET"]:
		var item_id := str(equipped_cosmetics.get(slot, ""))
		var layer := cosmetic_sprites.get(slot) as Sprite2D
		if layer == null:
			continue
		layer.visible = not item_id.is_empty() and cosmetic_data.has(item_id)
		if layer.visible:
			var image_name := str(cosmetic_data[item_id].get("image", ""))
			var art_folder := "pets"
			var art_path := "res://assets/art/%s/%s" % [art_folder, image_name]
			layer.texture = load(art_path)
			if slot == "PET" and layer.texture != null:
				var preview_bounds: Rect2 = PET_PREVIEW_BOUNDS.get(image_name, Rect2(Vector2.ZERO, layer.texture.get_size()))
				var pet_scale := PET_PREVIEW_HEIGHT / maxf(preview_bounds.size.y, 1.0)
				layer.scale = Vector2.ONE * pet_scale
				pet_preview_scale = layer.scale
	if fairy_effect != null:
		var pet_id := str(equipped_cosmetics.get("PET", ""))
		fairy_effect.configure(cosmetic_data.get(pet_id, {}))
	_load_outfit_art()
	var current := frame_name
	frame_name = ""
	_set_frame(current)

func preview_cosmetic(item: Dictionary) -> void:
	var preview := equipped_cosmetics.duplicate(true)
	if not item.is_empty():
		preview[str(item.get("slot", ""))] = str(item.get("id", ""))
	set_cosmetics(preview, cosmetic_data.values())

func _update_cosmetic_anchors() -> void:
	if sprite.texture == null:
		return
	if _is_explorer():
		_update_explorer_anchors()
		return
	var metrics: Dictionary = frame_metrics.get(frame_name, {})
	var used: Rect2i = metrics.get("used", Rect2i())
	if used.size == Vector2i.ZERO:
		return
	var texture_size := Vector2(metrics.get("texture_size", sprite.texture.get_size()))
	var frame_anchor: Dictionary = anchor_data.get(frame_name, {})
	var center_data: Array = frame_anchor.get("head_center", [float(used.get_center().x), float(used.position.y) + float(used.size.y) * 0.25])
	var head_center := Vector2(float(center_data[0]), float(center_data[1]))
	var head_width := float(frame_anchor.get("head_width", float(used.size.x) * 0.42))
	var source_to_local := func(source_point: Vector2) -> Vector2:
		return sprite.position + (source_point - texture_size * 0.5) * ART_SCALE
	var wing_anchor_data: Array = frame_anchor.get("outfit_back", [head_center.x, head_center.y + head_width * 0.38])
	var wing_anchor: Vector2 = source_to_local.call(Vector2(float(wing_anchor_data[0]), float(wing_anchor_data[1]) + 14.0))
	var back_view := str(frame_anchor.get("face_view", "back")) == "back"
	time_wings.z_index = 1 if back_view else -1
	fire_wings.z_index = 1 if back_view else -1
	time_wings.position = wing_anchor
	fire_wings.position = wing_anchor
	for trail in fire_trails:
		trail.position = wing_anchor
		trail.z_index = 1 if back_view else -2
	var pet := cosmetic_sprites.get("PET") as Sprite2D
	var pet_data: Array = frame_anchor.get("pet_anchor", [])
	if frame_name == "front" and pet_data.size() == 2 and pet.texture != null:
		var pet_bottom_left: Vector2 = source_to_local.call(Vector2(float(pet_data[0]), float(pet_data[1])))
		var pet_id := str(equipped_cosmetics.get("PET", ""))
		var image_name := str(cosmetic_data.get(pet_id, {}).get("image", ""))
		var preview_bounds: Rect2 = PET_PREVIEW_BOUNDS.get(image_name, Rect2(Vector2.ZERO, pet.texture.get_size()))
		var visible_top_left_offset := (preview_bounds.position - pet.texture.get_size() * 0.5) * pet.scale
		pet.position = pet_bottom_left - Vector2(0.0, preview_bounds.size.y * pet.scale.y) - visible_top_left_offset
	else:
		pet.position = source_to_local.call(Vector2(head_center.x + head_width * 1.65, head_center.y + head_width * 1.75))
	pet.visible = pet.texture != null and not str(equipped_cosmetics.get("PET", "")).is_empty() and frame_name == "front"
	if fairy_effect != null:
		fairy_effect.position = pet.position
		fairy_effect.visible = pet.visible and not fairy_effect.effect_name.is_empty()
	if outfit_back_sprite != null:
		outfit_back_sprite.visible = false
	var outfit_id := str(equipped_cosmetics.get("OUTFIT", ""))
	var effect_width := float(OUTFIT_FRONT_WIDTHS.get(outfit_id, head_width * 1.65)) if frame_name == "front" else float(BACK_FRAME_WIDTHS.get(frame_name, head_width * 1.65))
	var effect_size := Vector2(effect_width * ART_SCALE, (482.0 if frame_name == "front" else texture_size.y * 0.79) * ART_SCALE)
	if outfit_aura != null:
		outfit_aura.position = sprite.position
		outfit_aura.set_body_box(effect_size)
		outfit_aura.visible = not outfit_aura.effect_name.is_empty() and outfit_aura.effect_name == "SUN RAYS"
	if outfit_effect != null:
		outfit_effect.position = sprite.position
		outfit_effect.set_body_box(effect_size)
		outfit_effect.visible = not outfit_effect.effect_name.is_empty()

func play_celebration() -> void:
	if _is_explorer():
		return
	celebrate_remaining = 0.75

func preview_tick(delta: float) -> void:
	if outfit_aura != null:
		outfit_aura.set_preview_mode(true)
	if outfit_effect != null:
		outfit_effect.set_preview_mode(true)
	if fairy_effect != null:
		fairy_effect.set_preview_mode(true)
	pet_preview_time += delta
	var preview_bob := sin(pet_preview_time * 3.2) * 5.0
	sprite.position = _sprite_base_position() + Vector2(0.0, preview_bob)
	_update_cosmetic_anchors()
	var pet := cosmetic_sprites.get("PET") as Sprite2D
	if pet != null and pet.visible:
		var bob := sin(pet_preview_time * 4.8) * 2.5
		var wing_pulse := sin(pet_preview_time * 16.0) * 0.045
		pet.position.y += bob
		pet.scale = pet_preview_scale * Vector2(1.0 + wing_pulse, 1.0 - wing_pulse * 0.55)
		fairy_effect.position = pet.position

func show_front_preview() -> void:
	_set_frame("front")
	sprite.position = _sprite_base_position()
	_update_cosmetic_anchors()

func show_back_preview() -> void:
	_set_frame("hang")
	sprite.position = _sprite_base_position()
	_update_cosmetic_anchors()

func _load_outfit_art() -> void:
	outfit_front_texture = null
	outfit_frame_textures.clear()
	if outfit_back_sprite != null:
		outfit_back_sprite.texture = null
		outfit_back_sprite.visible = false
	var outfit_id := str(equipped_cosmetics.get("OUTFIT", ""))
	if _is_explorer():
		_load_explorer_art(outfit_id)
	elif not outfit_id.is_empty():
		var outfit_name := outfit_id.trim_prefix("outfit_")
		for pose in frame_textures:
			if pose == "front":
				continue
			var pose_path := "%s/%s/outfits/%s/%s.png" % [FRAME_ROOT, skin_id.to_lower(), outfit_name, pose]
			if ResourceLoader.exists(pose_path):
				var pose_texture := load(pose_path) as Texture2D
				if pose_texture != null:
					outfit_frame_textures[pose] = pose_texture
	var item: Dictionary = cosmetic_data.get(outfit_id, {})
	if outfit_id.is_empty() or item.is_empty():
		if outfit_aura != null:
			outfit_aura.configure({}, true)
		if outfit_effect != null:
			outfit_effect.configure({})
		return
	var front_path := "%s/front/%s/%s.png" % [OUTFIT_ROOT, skin_id.to_lower(), outfit_id]
	if not _is_explorer() and ResourceLoader.exists(front_path):
		outfit_front_texture = load(front_path) as Texture2D
	if outfit_effect != null:
		outfit_effect.configure(item)
	if outfit_aura != null:
		outfit_aura.configure(item, true)

func _load_explorer_art(outfit_id: String) -> void:
	var kind: String = EXPLORER_KINDS[skin_id]
	var outfit := outfit_id.trim_prefix("outfit_")
	if _explorer_kind == kind and _explorer_outfit == outfit:
		return
	var folder := "%s/%s/base" % [EXPLORER_ROOT, kind]
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("%s/meta.json" % folder))
	_explorer_meta = parsed as Dictionary
	_explorer_kind = kind
	_explorer_outfit = outfit
	frame_textures.clear()
	_explorer_masks.clear()
	anchor_data.clear()
	for animation in EXPLORER_ANIMS:
		var texture_animation := str(_explorer_meta["anims"][animation].get("alias", animation))
		frame_textures[animation] = load("%s/%s.png" % [folder, texture_animation]) as Texture2D
		var mask_path := "%s/%s_mask.png" % [folder, texture_animation]
		if ResourceLoader.exists(mask_path):
			_explorer_masks[animation] = load(mask_path) as Texture2D
	# All outfits share the calibrated Mixamo geometry, grid and anchors.
	_explorer_scale = float(_explorer_meta.get("visual_scale", EXPLORER_SCALE))
	var source_scale := float(_explorer_meta.get("source_scale", 1.0))
	flash_material.set_shader_parameter("outline_source_px", 0.0)
	flash_material.set_shader_parameter("shadow_source_offset", Vector2(0.0, 7.0) * source_scale)
	flash_material.set_shader_parameter("shadow_source_blur", 3.0 * source_scale)
	sprite.scale = Vector2.ONE * _explorer_scale * gameplay_visual_mult
	sprite.position = _sprite_base_position()
	EXPLORER_OUTFITS.configure(flash_material, _explorer_outfit, _explorer_masks.get(frame_name) as Texture2D)

func _explorer_pivot() -> Array:
	var data: Dictionary = _explorer_meta["anims"][frame_name]
	return data.get("pivot", _explorer_meta.get("pivot", [128, 240]))

func _explorer_source_to_local(point: Vector2) -> Vector2:
	var pivot := _explorer_pivot()
	return sprite.position + (point - Vector2(float(pivot[0]), float(pivot[1]))) * _explorer_scale * gameplay_visual_mult

func _update_explorer_anchors() -> void:
	var frames: Array = _explorer_meta["anchors"][frame_name]
	var anchor: Dictionary = frames[mini(sprite.frame, frames.size() - 1)]
	var back: Array = anchor["back"]
	var head: Array = anchor["head"]
	var head_center := Vector2(float(head[0]), float(head[1]))
	var head_width := float(anchor["head_w"])
	var wing_anchor := _explorer_source_to_local(Vector2(float(back[0]), float(back[1])))
	var back_view := frame_name != "front"
	time_wings.position = wing_anchor
	fire_wings.position = wing_anchor
	time_wings.z_index = 1 if back_view else -1
	fire_wings.z_index = 1 if back_view else -1
	for trail in fire_trails:
		trail.position = wing_anchor
		trail.z_index = 1 if back_view else -2
	var pet := cosmetic_sprites.get("PET") as Sprite2D
	pet.position = _explorer_source_to_local(head_center + Vector2(head_width * 1.65, head_width * 1.75))
	pet.visible = pet.texture != null and not str(equipped_cosmetics.get("PET", "")).is_empty() and not back_view
	if fairy_effect != null:
		fairy_effect.position = pet.position
		fairy_effect.visible = pet.visible and not fairy_effect.effect_name.is_empty()
	if outfit_back_sprite != null:
		outfit_back_sprite.visible = false
	var pivot := _explorer_pivot()
	var body_top := head_center.y - head_width * 0.5
	var body_height := maxf(float(pivot[1]) - body_top, head_width)
	var effect_size := Vector2(head_width * 1.65, body_height) * _explorer_scale * gameplay_visual_mult
	var effect_center := _explorer_source_to_local(Vector2(head_center.x, body_top + body_height * 0.5))
	if outfit_aura != null:
		outfit_aura.position = effect_center
		outfit_aura.set_body_box(effect_size)
		outfit_aura.visible = outfit_aura.effect_name == "SUN RAYS"
	if outfit_effect != null:
		outfit_effect.position = effect_center
		outfit_effect.set_body_box(effect_size)
		outfit_effect.visible = not outfit_effect.effect_name.is_empty()

func visual_snapshot() -> Dictionary:
	if _is_explorer():
		return {"mode": mode, "frame": "%s:%d" % [frame_name, sprite.frame], "skin": skin_id, "art": "3d", "outfit": _explorer_outfit}
	return {"mode": mode, "frame": frame_name, "skin": skin_id}

func _build_visual() -> void:
	takeoff_particles = CPUParticles2D.new()
	takeoff_particles.name = "TransferTakeoffTrail"
	takeoff_particles.amount = 7
	takeoff_particles.lifetime = maxf(Balance.BRANCH_TRANSITION_SECONDS, 0.30)
	takeoff_particles.one_shot = true
	takeoff_particles.explosiveness = 0.92
	takeoff_particles.local_coords = false
	takeoff_particles.texture = TRANSFER_LEAF_TEXTURE
	takeoff_particles.direction = Vector2(-1.0, -0.15)
	takeoff_particles.spread = 20.0
	takeoff_particles.gravity = Vector2(0.0, 24.0)
	takeoff_particles.initial_velocity_min = 58.0
	takeoff_particles.initial_velocity_max = 82.0
	takeoff_particles.scale_amount_min = 0.04
	takeoff_particles.scale_amount_max = 0.055
	takeoff_particles.angle_min = -28.0
	takeoff_particles.angle_max = 28.0
	takeoff_particles.angular_velocity_min = -160.0
	takeoff_particles.angular_velocity_max = 160.0
	takeoff_particles.color = Color(0.56, 0.82, 0.31, 0.92)
	takeoff_particles.position = Vector2(-5.0, 23.0)
	takeoff_particles.z_index = -3
	takeoff_particles.emitting = false
	add_child(takeoff_particles)
	_build_transfer_motion_trails()
	fire_wings = Sprite2D.new()
	fire_wings.name = "FireWings"
	var fire_texture := AtlasTexture.new()
	fire_texture.atlas = ROCK_FIRE_ATLAS
	fire_texture.region = Rect2(Vector2(1024, 512), FIRE_WINGS_REGION_SIZE)
	fire_wings.texture = fire_texture
	fire_wings.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	fire_wings.offset = fire_texture.get_size() * 0.5 - FIRE_WING_ROOT
	fire_wings.scale = Vector2.ONE * FIRE_WINGS_TARGET_SCALE
	fire_wings.z_index = -1
	fire_wings.visible = false
	add_child(fire_wings)
	for side in [-1.0, 1.0]:
		var trail := Polygon2D.new()
		var points := PackedVector2Array([Vector2(side * 22.0, -19.0), Vector2(side * 58.0, -7.0), Vector2(side * 30.0, 5.0), Vector2(side * 16.0, 2.0)])
		for index in points.size():
			points[index] -= FIRE_TRAIL_ROOT
		trail.polygon = points
		trail.scale = Vector2.ONE * FIRE_WINGS_TARGET_SCALE / FIRE_TRAIL_REFERENCE_SCALE
		trail.color = Color("ff8a24")
		trail.modulate.a = 0.65
		trail.z_index = -2
		trail.visible = false
		add_child(trail)
		fire_trails.append(trail)
	time_wings = Sprite2D.new()
	time_wings.name = "TimeWings"
	time_wings.texture = WING_TEXTURE
	time_wings.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	time_wings.offset = WING_TEXTURE.get_size() * (Vector2(0.5, 0.5) - TIME_WING_ROOT_UV)
	time_wings.scale = Vector2.ONE * _time_wings_target_scale * 0.70
	time_wings.z_index = -1
	time_wings.modulate.a = 0.0
	time_wings.visible = false
	add_child(time_wings)
	sprite = Sprite2D.new()
	sprite.name = "FullBodyFrame"
	sprite.position = Vector2(0.0, BASE_Y)
	sprite.scale = Vector2.ONE * ART_SCALE
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	flash_material = ShaderMaterial.new()
	flash_material.shader = EXPLORER_OUTFITS.SHADER
	flash_material.set_shader_parameter("flash_color", Color(1.0, 0.35, 0.30))
	sprite.material = flash_material
	add_child(sprite)
	outfit_back_sprite = Sprite2D.new()
	outfit_back_sprite.name = "OutfitBack"
	outfit_back_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	outfit_back_sprite.z_index = 1
	outfit_back_sprite.visible = false
	add_child(outfit_back_sprite)
	# At z=1, back-facing wings follow the outfit and precede cosmetic effects.
	for trail in fire_trails:
		move_child(trail, get_child_count() - 1)
	move_child(fire_wings, get_child_count() - 1)
	move_child(time_wings, get_child_count() - 1)
	for slot in ["PET"]:
		var layer := Sprite2D.new()
		layer.name = "%sCosmetic" % slot.capitalize()
		layer.centered = true
		layer.scale = Vector2.ONE * 0.17
		layer.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		layer.z_index = 2
		layer.visible = false
		add_child(layer)
		cosmetic_sprites[slot] = layer
	fairy_effect = FAIRY_EFFECT.new()
	fairy_effect.name = "FairyEffect"
	fairy_effect.z_index = 1
	fairy_effect.visible = false
	add_child(fairy_effect)
	outfit_aura = OUTFIT_EFFECT.new()
	outfit_aura.name = "OutfitAura"
	outfit_aura.z_index = -1
	outfit_aura.visible = false
	add_child(outfit_aura)
	outfit_effect = OUTFIT_EFFECT.new()
	outfit_effect.name = "OutfitEffect"
	outfit_effect.z_index = 2
	outfit_effect.visible = false
	add_child(outfit_effect)
	for slot in ["PET"]:
		(cosmetic_sprites[slot] as Sprite2D).z_index = 3

func _build_transfer_motion_trails() -> void:
	var paths := [
		PackedVector2Array([Vector2(-7, 5), Vector2(-22, 1), Vector2(-39, 8), Vector2(-57, 3)]),
		PackedVector2Array([Vector2(-8, 15), Vector2(-23, 11), Vector2(-37, 17), Vector2(-52, 13)]),
		PackedVector2Array([Vector2(-6, 25), Vector2(-18, 21), Vector2(-31, 26), Vector2(-46, 22)]),
	]
	var colors := [Color(0.94, 1.0, 0.88, 0.94), Color(0.78, 0.94, 0.61, 0.92), Color(0.90, 1.0, 0.80, 0.88)]
	for index in paths.size():
		var trail := Line2D.new()
		trail.name = "TransferMotionTrail%d" % (index + 1)
		trail.points = paths[index]
		trail.width = 4.0 - float(index) * 0.4
		trail.default_color = colors[index]
		trail.begin_cap_mode = Line2D.LINE_CAP_ROUND
		trail.end_cap_mode = Line2D.LINE_CAP_ROUND
		trail.joint_mode = Line2D.LINE_JOINT_ROUND
		trail.antialiased = true
		trail.z_index = -4
		trail.visible = false
		add_child(trail)
		transfer_trails.append(trail)
