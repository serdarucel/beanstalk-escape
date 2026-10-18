class_name MetaShopUI
extends Control

signal closed
signal run_started

const SLOTS := ["CHARACTERS", "OUTFIT", "PET"]

static func _device_pixels_per_unit(item: CanvasItem) -> float:
	var screen := item.get_screen_transform()
	var screen_scale := maxf(screen.x.length(), screen.y.length())
	# Headless windows omit stretch from get_screen_transform(). Keep the
	# physical window / logical viewport ratio as an independent lower bound.
	var window := item.get_window()
	var viewport_size := window.get_visible_rect().size
	var pixels := Vector2(window.size) / viewport_size.max(Vector2.ONE)
	var canvas := item.get_global_transform_with_canvas()
	return maxf(screen_scale, maxf((canvas.x * pixels).length(), (canvas.y * pixels).length()))

class PortraitSlot:
	extends Control

	var portrait := TextureRect.new()

	func _ready() -> void:
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		add_child(portrait)
		_fit()

	func _process(_delta: float) -> void:
		_fit()

	func _fit() -> void:
		if portrait.texture == null:
			return
		# Screen transform includes viewport stretch, card scaling and device pixels.
		var pixels_per_unit := MetaShopUI._device_pixels_per_unit(self)
		var limit := portrait.texture.get_size() * 2.0 / maxf(pixels_per_unit, 0.001)
		portrait.size = Vector2(minf(size.x, limit.x), minf(size.y, limit.y))
		portrait.position = (size - portrait.size) * 0.5

class TurnIcon:
	extends Control

	func _draw() -> void:
		var center := Vector2(9, 9)
		var radius := 5.5
		var end_angle := TAU - 0.55
		var color := Color("f2d06b")
		draw_arc(center, radius, 0.35, end_angle, 24, color, 2.0, true)
		var radial := Vector2(cos(end_angle), sin(end_angle))
		var tangent := Vector2(-radial.y, radial.x)
		var tip := center + radial * 7.0
		draw_colored_polygon(PackedVector2Array([
			tip,
			center + radial * 3.2 + tangent * 2.8,
			center + radial * 3.2 - tangent * 2.8,
		]), color)

var economy: EconomyManager
var platform_services: Node
var player_visual: PlayerVisual
var mode := "SHOP"
var active_tab := "CHARACTERS"
var preview_character_id := ""
var preview_item: Dictionary = {}
var panel: Panel
var title_label: Label
var tabs: HBoxContainer
var grid: GridContainer
var scroll: ScrollContainer
var preview_host: Control
var preview: PlayerVisual
var view_toggle_button: Button
var footer: HBoxContainer
var gold_label: Label
var start_button: Button
var double_treasure_button: Button
var pending_double_gold := 0
var preview_back := false
var _last_preview_tab := ""

func setup(manager: EconomyManager, gameplay_visual: PlayerVisual, services: Node = null) -> void:
	economy = manager
	platform_services = services
	player_visual = gameplay_visual
	_build()
	economy.changed.connect(func(_snapshot): refresh())
	refresh()

func open_shop() -> void:
	mode = "SHOP"
	active_tab = "CHARACTERS"
	preview_character_id = ""
	preview_item = {}
	visible = true
	refresh()

func open_character_select() -> void:
	mode = "SELECT"
	preview_back = false
	visible = true
	refresh()
	call_deferred("_focus_start_button")

func open_map() -> void:
	mode = "MAP"
	pending_double_gold = 0
	visible = true
	refresh()
	call_deferred("_focus_first_map_action")

func close() -> void:
	preview_character_id = ""
	preview_item = {}
	preview_back = false
	_apply_preview()
	visible = false
	closed.emit()

func _process(delta: float) -> void:
	if visible and preview != null:
		preview.preview_tick(delta)
		_fit_preview()

func _input(event: InputEvent) -> void:
	if not visible or mode != "SELECT" or not event.is_pressed() or event.is_echo():
		return
	if event.is_action_pressed("move_left"):
		_cycle_character(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_right"):
		_cycle_character(1)
		get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_instance_valid(panel):
		_layout()

func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	panel = Panel.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var backdrop := StyleBoxFlat.new()
	backdrop.bg_color = Color("102d27")
	backdrop.border_color = Color("d0a83c")
	backdrop.set_border_width_all(3)
	panel.add_theme_stylebox_override("panel", backdrop)
	add_child(panel)
	title_label = Label.new()
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 26)
	panel.add_child(title_label)
	tabs = HBoxContainer.new()
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(tabs)
	preview_host = Control.new()
	preview_host.clip_contents = true
	panel.add_child(preview_host)
	preview = PlayerVisual.new()
	preview.name = "LivePreview"
	preview.z_index = 5
	preview.scale = Vector2.ONE * 1.45
	preview_host.add_child(preview)
	view_toggle_button = Button.new()
	view_toggle_button.text = "TURN"
	view_toggle_button.custom_minimum_size = Vector2(110, 34)
	var turn_style := StyleBoxFlat.new()
	turn_style.bg_color = Color("173d32")
	turn_style.border_color = Color("d0a83c")
	turn_style.set_border_width_all(2)
	turn_style.set_corner_radius_all(8)
	var turn_hover_style := turn_style.duplicate() as StyleBoxFlat
	turn_hover_style.bg_color = Color("245244")
	var turn_pressed_style := turn_style.duplicate() as StyleBoxFlat
	turn_pressed_style.bg_color = Color("0d2822")
	view_toggle_button.add_theme_stylebox_override("normal", turn_style)
	view_toggle_button.add_theme_stylebox_override("hover", turn_hover_style)
	view_toggle_button.add_theme_stylebox_override("pressed", turn_pressed_style)
	var turn_icon := TurnIcon.new()
	turn_icon.name = "TurnIcon"
	turn_icon.position = Vector2(10, 8)
	turn_icon.size = Vector2(18, 18)
	turn_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view_toggle_button.add_child(turn_icon)
	view_toggle_button.pressed.connect(_toggle_preview_view)
	panel.add_child(view_toggle_button)
	scroll = ScrollContainer.new()
	panel.add_child(scroll)
	grid = GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)
	grid.minimum_size_changed.connect(func(): _layout.call_deferred())
	grid.child_entered_tree.connect(func(_child): _layout.call_deferred())
	# ScrollContainer resets its child's transform when sorting after a resize.
	scroll.sort_children.connect(func():
		grid.set_deferred("scale", Vector2.ONE * float(grid.get_meta("card_scale", 1.0))))
	footer = HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(footer)
	gold_label = Label.new()
	gold_label.custom_minimum_size = Vector2(190, 40)
	gold_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	footer.add_child(gold_label)
	double_treasure_button = Button.new()
	double_treasure_button.text = "DOUBLE TREASURE (AD)"
	double_treasure_button.custom_minimum_size = Vector2(210, 40)
	double_treasure_button.pressed.connect(_double_treasure)
	footer.add_child(double_treasure_button)
	var back := Button.new()
	back.text = "BACK"
	back.custom_minimum_size = Vector2(130, 40)
	back.pressed.connect(close)
	footer.add_child(back)
	start_button = Button.new()
	start_button.text = "START"
	start_button.custom_minimum_size = Vector2(150, 40)
	start_button.pressed.connect(_start_run)
	footer.add_child(start_button)
	_layout()

func _layout() -> void:
	var width := maxf(size.x, 320.0)
	var height := maxf(size.y, 320.0)
	grid.scale = Vector2.ONE
	grid.set_meta("card_scale", 1.0)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	title_label.position = Vector2(12, 8)
	title_label.size = Vector2(width - 24, 36)
	tabs.position = Vector2(8, 48)
	tabs.size = Vector2(width - 16, 38)
	var footer_y := height - 48.0
	footer.position = Vector2(8, footer_y)
	footer.size = Vector2(width - 16, 42)
	var preview_width := clampf(width * 0.27, 190.0, 260.0)
	var map_mode := mode == "MAP"
	preview_host.position = Vector2(8, 92)
	preview_host.size = Vector2(preview_width, maxf(footer_y - 128.0, 120.0))
	view_toggle_button.position = Vector2(8.0 + (preview_width - 110.0) * 0.5, preview_host.position.y + preview_host.size.y + 4.0)
	view_toggle_button.size = Vector2(110, 34)
	view_toggle_button.visible = not map_mode
	preview.scale = Vector2.ONE * (2.90 if preview_back else 1.45)
	preview.position = Vector2(preview_width * (0.5 if preview_back or active_tab == "OUTFIT" else 0.262), preview_host.size.y * 0.52)
	preview_host.visible = not map_mode
	scroll.position = Vector2(8, 56) if map_mode else Vector2(preview_width + 16, 92)
	scroll.size = Vector2(width - 16 if map_mode else width - preview_width - 24, maxf(footer_y - scroll.position.y - 6.0, 120.0))
	grid.columns = (6 if scroll.size.x >= 720.0 else 3) if map_mode else (3 if scroll.size.x >= 450.0 else 2)
	if mode == "SELECT" or (mode == "SHOP" and active_tab == "CHARACTERS"):
		grid.columns = maxi(economy.character_catalog().size(), 1)
		# Keep the approved desktop type; wide phones use the HUD's device-pixel floor.
		var window_size := Vector2(get_tree().root.size)
		var pixel_scale := window_size.x / maxf(get_viewport_rect().size.x, 1.0)
		var minimum_font := ceili(28.0 * minf(window_size.x, window_size.y) / 1080.0 / maxf(pixel_scale, 0.001))
		var card_font := maxi(12, minimum_font) if width / height > 2.0 else 12
		for card in grid.get_children():
			if card is PanelContainer:
				for label in card.find_children("*", "Label", true, false):
					label.add_theme_font_size_override("font_size", card_font)
		var minimum := grid.get_combined_minimum_size()
		if minimum.x <= 0.0 or minimum.y <= 0.0:
			return
		var portrait := height > width and mode == "SHOP"
		var available_width := width - 32.0 if portrait else scroll.size.x
		var available_height := footer_y - 104.0
		var card_scale := minf(available_width / minimum.x, available_height / minimum.y)
		if portrait:
			# Fill the portrait screen with a centered preview, then cards and shield.
			card_scale = minf(card_scale, available_height * 0.5 / minimum.y)
		else:
			card_scale = minf(card_scale, 1.0)
		grid.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		grid.set_meta("card_scale", card_scale)
		grid.scale = Vector2.ONE * card_scale
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.scroll_horizontal = 0
		scroll.scroll_vertical = 0
		var cards_size := minimum * card_scale
		if portrait:
			preview_host.position = Vector2(16, 92)
			preview_host.size = Vector2(width - 32.0, available_height - cards_size.y - 12.0)
			preview.scale *= minf(preview_host.size.y / 240.0, preview_host.size.x / 240.0)
			preview.position = preview_host.size * 0.5
			scroll.position = Vector2((width - cards_size.x) * 0.5, preview_host.position.y + preview_host.size.y + 12.0)
			# TURN shares the bottom row with GOLD and BACK.
			view_toggle_button.position = Vector2(16, footer_y + 3.0)
			footer.position.x = 134.0
			footer.size.x = width - 142.0
		else:
			scroll.position.x += (scroll.size.x - cards_size.x) * 0.5
		scroll.size = cards_size
	tabs.size = Vector2(width - 16, 38)
	_fit_preview()

func _fit_preview() -> void:
	if preview.sprite == null or preview.sprite.texture == null:
		return
	var sprite := preview.sprite
	var pixels_per_unit := _device_pixels_per_unit(preview_host)
	var source_scale := maxf(absf(sprite.scale.x), absf(sprite.scale.y))
	var source_rect := sprite.get_rect()
	var body_size := source_rect.size * source_scale
	var fit := minf(preview_host.size.x / maxf(body_size.x, 1.0), preview_host.size.y / maxf(body_size.y + 10.0, 1.0))
	var limit := 2.0 / maxf(source_scale * pixels_per_unit, 0.001)
	preview.scale = Vector2.ONE * minf(preview.scale.y, minf(fit, limit))
	var center := source_rect.get_center()
	if not preview_back:
		center.y += 15.0 # Visible front bounds: (59, 42) to (197, 244).
	preview.position = preview_host.size * 0.5 - (sprite.position + center * sprite.scale) * preview.scale

func refresh() -> void:
	_sync_preview_tab(active_tab)
	if economy == null:
		return
	title_label.text = "STAGE MAP" if mode == "MAP" else ("CHARACTER SELECT" if mode == "SELECT" else "SHOP")
	gold_label.text = "GOLD %d" % economy.gold
	start_button.visible = mode == "SELECT"
	double_treasure_button.visible = mode == "MAP" and pending_double_gold > 0 and platform_services != null and platform_services.is_rewarded_supported()
	if double_treasure_button.visible:
		double_treasure_button.text = "DOUBLE +%d (AD)" % pending_double_gold
	_rebuild_tabs()
	_rebuild_cards()
	_apply_preview()
	_layout()

func _sync_preview_tab(next_tab: String) -> void:
	if next_tab != _last_preview_tab:
		preview_back = false
		_last_preview_tab = next_tab

func _focus_start_button() -> void:
	if visible and mode == "SELECT" and start_button.visible and not start_button.disabled:
		start_button.grab_focus()

func _cycle_character(direction: int) -> void:
	var candidates: Array[String] = []
	for character_id_value in economy.character_catalog():
		var character_id := str(character_id_value)
		if economy.character_available(character_id):
			candidates.append(character_id)
	if candidates.is_empty():
		return
	var current := candidates.find(str(economy.shop.selected_character))
	var next_index := posmod((0 if current < 0 else current) + direction, candidates.size())
	economy.select_character(candidates[next_index])
	refresh()
	call_deferred("_focus_start_button")

func _rebuild_tabs() -> void:
	for child in tabs.get_children():
		tabs.remove_child(child)
		child.queue_free()
	tabs.visible = mode == "SHOP"
	if mode != "SHOP":
		return
	for slot in SLOTS:
		var button := Button.new()
		button.text = slot
		button.toggle_mode = true
		button.button_pressed = active_tab == slot
		button.custom_minimum_size = Vector2(92, 36)
		button.add_theme_font_size_override("font_size", 12)
		button.pressed.connect(func(): active_tab = slot; refresh())
		tabs.add_child(button)

func _rebuild_cards() -> void:
	for child in grid.get_children():
		grid.remove_child(child)
		child.queue_free()
	if mode == "MAP":
		for stage_number in range(1, 31):
			grid.add_child(_map_node_card(stage_number))
	elif mode == "SELECT":
		for character_id in economy.character_catalog():
			var data: Dictionary = economy.character_catalog()[character_id]
			grid.add_child(_character_card(character_id, data))
	else:
		if active_tab == "CHARACTERS":
			for character_id in economy.character_catalog():
				grid.add_child(_character_card(character_id, economy.character_catalog()[character_id]))
		else:
			var items := economy.cosmetic_catalog(active_tab)
			if items.is_empty() and active_tab == "PET":
				var coming := Label.new()
				coming.text = "COMING SOON"
				coming.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				coming.custom_minimum_size = Vector2(320, 120)
				grid.add_child(coming)
			for item in items:
				grid.add_child(_cosmetic_card(item))

func _map_node_card(stage_number: int) -> Control:
	var progression := economy.progression_snapshot()
	var completed: Array = progression.completed_stages
	var skipped: Array = progression.skipped_stages
	var claimed: Array = progression.treasures_claimed
	var is_summit := stage_number % 5 == 0
	var status := "COMPLETED" if completed.has(stage_number) else ("SKIPPED" if skipped.has(stage_number) else "LOCKED")
	if status == "LOCKED" and (stage_number == 1 or completed.has(stage_number - 1)):
		status = "OPEN"
	var card := _base_card("%s %02d" % ["TREASURE" if is_summit else "STAGE", stage_number], status)
	card.custom_minimum_size = Vector2(120, 108)
	var body := _card_body(card)
	var button := Button.new()
	button.custom_minimum_size.y = 34
	if is_summit and claimed.has(stage_number):
		button.text = "CLAIMED"
		button.disabled = true
	elif is_summit and completed.has(stage_number):
		button.text = "CLAIM"
		button.pressed.connect(_claim_treasure.bind(stage_number))
	else:
		button.text = status
		button.disabled = true
	body.add_child(button)
	return card

func _claim_treasure(stage_number: int) -> void:
	var reward := economy.claim_map_treasure(stage_number)
	if reward.is_empty():
		return
	pending_double_gold = int(reward.get("amount", 0)) if str(reward.get("type", "")) == "gold" else 0
	refresh()

func _double_treasure() -> void:
	if pending_double_gold <= 0 or platform_services == null:
		return
	var reward := pending_double_gold
	pending_double_gold = 0
	platform_services.show_rewarded("double_treasure", func(): economy.grant_gold(reward); refresh())
	refresh()

func _focus_first_map_action() -> void:
	if not visible or mode != "MAP":
		return
	for card in grid.get_children():
		for node in card.find_children("*", "Button", true, false):
			var button := node as Button
			if not button.disabled:
				button.grab_focus()
				return

func _base_card(title: String, subtitle: String) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(168, 220)
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color("183c32")
	card_style.border_color = Color("cda944")
	card_style.set_border_width_all(2)
	card_style.set_corner_radius_all(8)
	card_style.content_margin_left = 8.0
	card_style.content_margin_right = 8.0
	card_style.content_margin_top = 6.0
	card_style.content_margin_bottom = 6.0
	card.add_theme_stylebox_override("panel", card_style)
	var body := VBoxContainer.new()
	card.add_child(body)
	var name_label := Label.new()
	name_label.text = title
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_WORD_ELLIPSIS
	name_label.max_lines_visible = 2
	name_label.add_theme_font_size_override("font_size", 12)
	name_label.custom_minimum_size.y = 40
	body.add_child(name_label)
	var sub := Label.new()
	sub.text = subtitle
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 12)
	sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	body.add_child(sub)
	return card

func _card_body(card: PanelContainer) -> VBoxContainer:
	return card.get_child(0) as VBoxContainer

func _character_card(character_id: String, data: Dictionary) -> Control:
	var card := _base_card("%s · %s" % [character_id, data.name], "%d GOLD" % int(data.price))
	var body := _card_body(card)
	var slot := PortraitSlot.new()
	slot.custom_minimum_size = Vector2(112, 104)
	var outfit := str(economy.shop.equipped.get("OUTFIT", "")).trim_prefix("outfit_")
	var kind := str(PlayerVisual.EXPLORER_KINDS.get(character_id, "erkek"))
	var path := "%s/%s/%s/front.png" % [PlayerVisual.EXPLORER_ROOT, kind, "base" if outfit.is_empty() else outfit]
	if not ResourceLoader.exists(path):
		path = "%s/%s/base/front.png" % [PlayerVisual.EXPLORER_ROOT, kind]
	slot.portrait.texture = load(path)
	body.add_child(slot)
	var button := Button.new()
	button.custom_minimum_size.y = 36
	var owned: bool = economy.shop.owned.has(character_id)
	var reason := economy.locked_reason(character_id)
	if owned and economy.character_available(character_id):
		button.text = "SELECTED" if str(economy.shop.selected_character) == character_id else "SELECT"
		button.disabled = str(economy.shop.selected_character) == character_id
		button.pressed.connect(func(): economy.select_character(character_id); refresh())
	elif reason.is_empty():
		button.text = "BUY · %d" % int(data.price)
		button.pressed.connect(func(): economy.buy(character_id); refresh())
	else:
		button.text = _lock_text(reason)
		button.disabled = true
	body.add_child(button)
	card.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed:
			_preview_character(character_id))
	button.focus_entered.connect(func(): _preview_character(character_id))
	return card

func _cosmetic_card(item: Dictionary) -> Control:
	var source := str(item.get("source", ""))
	var slot := str(item.get("slot", ""))
	var is_pet := slot == "PET"
	var is_outfit := slot == "OUTFIT"
	var price_text := source if is_outfit and not source.is_empty() else "%d GOLD" % int(item.price)
	var subtitle := "%s\n%s" % [str(item.get("effect_name", "")), price_text] if is_pet or is_outfit else (source if not source.is_empty() else str(item.rarity))
	var card := _base_card(str(item.name), subtitle)
	var body := _card_body(card)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(112, 88 if is_pet else 104)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if is_pet:
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var art_folder := "pets" if is_pet else ("outfits/icons" if is_outfit else "cosmetics")
	icon.texture = load("res://assets/art/%s/%s" % [art_folder, item.image])
	body.add_child(icon)
	var button := Button.new()
	button.custom_minimum_size.y = 36
	var item_id := str(item.id)
	var owned: bool = economy.shop.owned.has(item_id)
	var reason := economy.locked_reason(item_id)
	if owned:
		var equipped: bool = str(economy.shop.equipped.get(item.slot, "")) == item_id
		button.text = "UNEQUIP" if equipped else "EQUIP"
		button.pressed.connect(func(): economy.equip(item_id); refresh())
	elif reason.is_empty():
		button.text = "BUY · %d" % int(item.price)
		button.pressed.connect(func(): economy.buy(item_id); refresh())
	else:
		button.text = _lock_text(reason)
		button.disabled = true
	body.add_child(button)
	card.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed:
			_preview_item(item))
	button.focus_entered.connect(func(): _preview_item(item))
	return card

func _lock_text(reason: String) -> String:
	return "LOCKED" if reason.begins_with("LV ") else reason

func _preview_character(character_id: String) -> void:
	preview_character_id = character_id
	preview_item = {}
	_apply_preview()

func _preview_item(item: Dictionary) -> void:
	preview_item = item.duplicate(true)
	_apply_preview()

func _apply_preview() -> void:
	preview.set_skin(preview_character_id if not preview_character_id.is_empty() else str(economy.shop.selected_character))
	preview.set_cosmetics(economy.shop.equipped, economy.cosmetic_catalog())
	if not preview_item.is_empty():
		preview.preview_cosmetic(preview_item)
	if preview_back:
		preview.show_back_preview()
	else:
		preview.show_front_preview()
	_fit_preview()
	view_toggle_button.text = "TURN"
	if player_visual != null:
		player_visual.set_skin(str(economy.shop.selected_character))
		player_visual.set_cosmetics(economy.shop.equipped, economy.cosmetic_catalog())

func _toggle_preview_view() -> void:
	preview_back = not preview_back
	_apply_preview()
	_layout()

func _start_run() -> void:
	_apply_preview()
	visible = false
	run_started.emit()
