## CardVisual
## The visual representation of a card. Handles name-only rendering, clicks, and drag/drop.
## Attach this to a card scene (card_visual.tscn).
class_name CardVisual
extends Control

# ── References ───────────────────────────────────────────────────────────────

@onready var card_art: TextureRect = $CardArt
@onready var card_frame: Panel = $CardFrame
@onready var name_label: Label = $NameLabel
@onready var power_label: Label = $PowerLabel
@onready var type_label: Label = $TypeLabel
@onready var ability_label: RichTextLabel = $AbilityLabel
@onready var cost_label: Label = $CostLabel  # For sellary cost display
var status_label: Label = null
var state_label: Label = null
var rarity_band: ColorRect = null
var status_badges: Array[Label] = []
var face_panel: Panel = null
var face_glyph: Label = null
var show_power_chip := true

# ── State ────────────────────────────────────────────────────────────────────

var card_instance: CardInstance = null
var is_hovered: bool = false
var is_selected: bool = false
var is_pressed: bool = false
var is_dragging: bool = false
var drag_offset: Vector2 = Vector2.ZERO
var press_global_position: Vector2 = Vector2.ZERO
var original_global_position: Vector2 = Vector2.ZERO
var original_z_index: int = 0

const DRAG_THRESHOLD := 8.0
const CARD_SIZE := Vector2(150, 76)
const MAX_CARD_DISPLAY_HEIGHT := 150.0

# ── Signals ──────────────────────────────────────────────────────────────────

signal clicked(card_visual: CardVisual)
signal right_clicked(card_visual: CardVisual)
signal drag_started(card_visual: CardVisual)
signal drag_ended(card_visual: CardVisual, drop_position: Vector2)
signal hovered(card_visual: CardVisual)
signal unhovered(card_visual: CardVisual)


# ── Setup ────────────────────────────────────────────────────────────────────

func setup(inst: CardInstance) -> void:
	card_instance = inst
	custom_minimum_size = CARD_SIZE
	size = CARD_SIZE
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_ensure_overlays()
	refresh_display()


func set_card_dimensions(dimensions: Vector2) -> void:
	custom_minimum_size = dimensions
	size = dimensions
	_layout_card_chrome()


func set_detail_highlighted(enabled: bool) -> void:
	if not card_frame:
		return
	is_selected = enabled
	_apply_frame_style()


func set_draggable(enabled: bool) -> void:
	if enabled:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		modulate.a = 1.0
	else:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_ARROW
		modulate.a = 0.72


func refresh_display() -> void:
	if not card_instance:
		return
	
	var data: CardData = card_instance.data
	_ensure_overlays()
	_apply_frame_style()
	
	if name_label:
		name_label.text = data.name
		name_label.tooltip_text = data.ability_text if data.has_ability else data.name
		name_label.add_theme_font_size_override("font_size", _name_font_size(data.name))
		name_label.add_theme_color_override("font_color", Color(0.9, 0.93, 0.98))
		name_label.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name_label.clip_text = true
	if card_art:
		card_art.visible = false
	if face_panel:
		face_panel.visible = false
	if face_glyph:
		face_glyph.visible = false
	if power_label:
		var show_power: bool = card_instance.current_power > 0 or data.type == "Unit" or data.type == "Hero"
		show_power = show_power and show_power_chip
		power_label.visible = show_power
		if show_power:
			power_label.text = str(card_instance.current_power)
			power_label.add_theme_stylebox_override("normal", _chip_style(Color(0.055, 0.061, 0.078, 0.98), Color(0.28, 0.32, 0.42), 3))
			power_label.add_theme_font_size_override("font_size", 13)
			# Tint red if damaged, green if boosted
			if card_instance.current_power < data.base_power:
				power_label.add_theme_color_override("font_color", Color(1.0, 0.42, 0.38))
			elif card_instance.current_power > data.base_power:
				power_label.add_theme_color_override("font_color", Color(0.45, 1.0, 0.58))
			else:
				power_label.add_theme_color_override("font_color", Color(0.92, 0.95, 1.0))
	if type_label:
		type_label.visible = true
		type_label.text = data.type
		type_label.add_theme_font_size_override("font_size", 10)
		type_label.add_theme_color_override("font_color", _type_color(data.type))
	if ability_label:
		ability_label.visible = false
	if cost_label:
		cost_label.visible = false
	
	# Status indicators (visual cue)
	_update_status_visuals()
	_update_state_visuals()
	_consume_pending_flash()


func _update_status_visuals() -> void:
	if not card_instance:
		return
	modulate = Color(1.0, 0.95, 0.55) if is_selected else Color.WHITE
	for badge in status_badges:
		badge.visible = false
	if status_label:
		status_label.visible = false
	var parts: Array[String] = []
	var part_statuses: Array[String] = []
	var keys: Array = card_instance.statuses.keys()
	keys.sort()
	for status_name in keys:
		var stacks: int = card_instance.statuses.get(status_name, 0)
		if stacks <= 0:
			continue
		var label := _status_abbrev(status_name)
		if stacks > 1:
			label += str(stacks)
		if card_instance.permanent_statuses.get(status_name, false):
			label += "*"
		parts.append(label)
		part_statuses.append(status_name)
	var card_size := _display_size()
	var visible_badges := mini(parts.size(), status_badges.size())
	var badge_width := maxf(22.0, minf(30.0, (card_size.x - 16.0 - float(maxi(visible_badges - 1, 0)) * 4.0) / float(maxi(visible_badges, 1))))
	for i in range(visible_badges):
		var badge := status_badges[i]
		badge.offset_left = 8.0 + float(i) * (badge_width + 4.0)
		badge.offset_right = badge.offset_left + badge_width
		badge.text = parts[i]
		badge.add_theme_stylebox_override("normal", _chip_style(_status_color(part_statuses[i]), Color(0.92, 0.95, 1.0, 0.22), 3))
		badge.visible = true


func _update_state_visuals() -> void:
	if not card_instance or not state_label:
		return
	var parts: Array[String] = []
	if card_instance.timer > 0:
		parts.append("T%d" % card_instance.timer)
	if card_instance.counter > 0:
		parts.append("C%d" % card_instance.counter)
	if card_instance.max_charges > 0 or card_instance.charges > 0:
		parts.append("Q%d" % card_instance.charges)
	if card_instance.block > 0:
		parts.append("B%d" % card_instance.block)
	state_label.visible = not parts.is_empty()
	state_label.text = " ".join(parts)
	if not parts.is_empty():
		state_label.offset_right = _display_size().x - 6.0
		state_label.add_theme_stylebox_override("normal", _chip_style(Color(0.07, 0.085, 0.12, 0.96), Color(0.34, 0.42, 0.62), 3))


func _ensure_overlays() -> void:
	if not face_panel:
		face_panel = Panel.new()
		face_panel.name = "CardFace"
		face_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		face_panel.visible = false
		add_child(face_panel)
		move_child(face_panel, 1)
	if not face_glyph:
		face_glyph = Label.new()
		face_glyph.name = "CardGlyph"
		face_glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		face_glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		face_glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		face_glyph.add_theme_font_size_override("font_size", 22)
		add_child(face_glyph)
		move_child(face_glyph, 2)
	if not status_label:
		status_label = Label.new()
		status_label.name = "StatusLabel"
		status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		status_label.add_theme_font_size_override("font_size", 10)
		status_label.offset_left = 6.0
		status_label.offset_top = 45.0
		status_label.offset_right = 144.0
		status_label.offset_bottom = 60.0
		add_child(status_label)
		status_label.visible = false
	if status_badges.is_empty():
		for i in range(4):
			var badge := Label.new()
			badge.name = "StatusBadge%d" % i
			badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
			badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			badge.add_theme_font_size_override("font_size", 8)
			badge.add_theme_color_override("font_color", Color(0.96, 0.98, 1.0))
			badge.offset_left = 8.0 + float(i) * 34.0
			badge.offset_top = 44.0
			badge.offset_right = badge.offset_left + 30.0
			badge.offset_bottom = 58.0
			badge.visible = false
			add_child(badge)
			status_badges.append(badge)
	if not rarity_band:
		rarity_band = ColorRect.new()
		rarity_band.name = "RarityBand"
		rarity_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rarity_band.offset_left = 0.0
		rarity_band.offset_top = 0.0
		rarity_band.offset_right = 5.0
		rarity_band.offset_bottom = 72.0
		add_child(rarity_band)
		move_child(rarity_band, 1)
	if not state_label:
		state_label = Label.new()
		state_label.name = "StateLabel"
		state_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		state_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		state_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		state_label.add_theme_font_size_override("font_size", 10)
		state_label.offset_left = 46.0
		state_label.offset_top = 4.0
		state_label.offset_right = 144.0
		state_label.offset_bottom = 18.0
		add_child(state_label)
	_layout_card_chrome()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout_card_chrome()


func _layout_card_chrome() -> void:
	var card_size := _display_size()
	for control in [card_frame, card_art, name_label, type_label, power_label, face_panel, face_glyph, ability_label, state_label]:
		_pin_top_left(control)
	if card_frame:
		card_frame.offset_left = 0.0
		card_frame.offset_top = 0.0
		card_frame.offset_right = card_size.x
		card_frame.offset_bottom = card_size.y
	if card_art:
		card_art.offset_left = 8.0
		card_art.offset_top = 30.0
		card_art.offset_right = card_size.x - 8.0
		card_art.offset_bottom = card_size.y - 24.0
	if face_panel:
		face_panel.offset_left = 9.0
		face_panel.offset_top = 40.0 if card_size.y > 104.0 else 30.0
		face_panel.offset_right = card_size.x - 9.0
		face_panel.offset_bottom = maxf(face_panel.offset_top + 12.0, card_size.y - 31.0)
	if ability_label:
		ability_label.offset_left = 13.0
		ability_label.offset_top = 45.0
		ability_label.offset_right = card_size.x - 13.0
		ability_label.offset_bottom = maxf(58.0, card_size.y - 34.0)
	if face_glyph:
		face_glyph.offset_left = 12.0
		face_glyph.offset_top = 24.0
		face_glyph.offset_right = card_size.x - 12.0
		face_glyph.offset_bottom = maxf(52.0, card_size.y - 28.0)
		face_glyph.add_theme_font_size_override("font_size", 34 if card_size.y > 100.0 else 20)
		face_glyph.visible = false
	if name_label:
		name_label.offset_left = 10.0
		name_label.offset_top = 10.0
		name_label.offset_right = card_size.x - 10.0
		name_label.offset_bottom = 38.0 if card_size.y > 92.0 else 30.0
	if type_label:
		type_label.offset_left = 8.0
		type_label.offset_top = card_size.y - 22.0
		type_label.offset_right = minf(82.0, card_size.x - 42.0)
		type_label.offset_bottom = card_size.y - 5.0
	if power_label:
		power_label.offset_left = card_size.x - 34.0
		power_label.offset_top = card_size.y - 24.0
		power_label.offset_right = card_size.x - 6.0
		power_label.offset_bottom = card_size.y - 5.0
	if rarity_band:
		rarity_band.offset_bottom = card_size.y
	for badge in status_badges:
		badge.offset_top = card_size.y - 30.0
		badge.offset_bottom = card_size.y - 16.0
	if state_label:
		state_label.offset_right = card_size.x - 6.0


func _display_size() -> Vector2:
	var w := custom_minimum_size.x if custom_minimum_size.x > 0.0 else CARD_SIZE.x
	var h := custom_minimum_size.y if custom_minimum_size.y > 0.0 else CARD_SIZE.y
	return Vector2(w, minf(h, MAX_CARD_DISPLAY_HEIGHT))


func _pin_top_left(control: Control) -> void:
	if not control:
		return
	control.anchor_left = 0.0
	control.anchor_top = 0.0
	control.anchor_right = 0.0
	control.anchor_bottom = 0.0


func _apply_frame_style() -> void:
	if not card_frame or not card_instance:
		return
	var style: StyleBoxFlat = card_frame.get_theme_stylebox("panel").duplicate()
	style.bg_color = _rarity_background(card_instance.data.rarity)
	style.border_color = _rarity_color(card_instance.data.rarity)
	style.set_border_width_all(2)
	style.shadow_color = _rarity_shadow(card_instance.data.rarity)
	style.shadow_size = 8 if card_instance.data.rarity in ["Epic", "Legendary", "Hero"] else 4
	style.shadow_offset = Vector2(0, 2)
	if is_selected:
		style.border_color = Color(0.9, 0.75, 0.1)
		style.set_border_width_all(3)
	card_frame.add_theme_stylebox_override("panel", style)
	if face_panel:
		face_panel.add_theme_stylebox_override("panel", _card_body_style(card_instance.data))
	if rarity_band:
		rarity_band.color = _rarity_color(card_instance.data.rarity)


func _rarity_color(rarity: String) -> Color:
	match rarity:
		"Common":
			return Color(0.68, 0.72, 0.78)
		"Rare":
			return Color(0.24, 0.56, 0.95)
		"Epic":
			return Color(0.62, 0.35, 0.9)
		"Legendary":
			return Color(0.95, 0.62, 0.18)
		"Hero":
			return Color(0.92, 0.28, 0.22)
		_:
			return Color(0.42, 0.46, 0.55)


func _rarity_background(rarity: String) -> Color:
	match rarity:
		"Rare":
			return Color(0.075, 0.105, 0.16)
		"Epic":
			return Color(0.12, 0.095, 0.17)
		"Legendary":
			return Color(0.16, 0.115, 0.055)
		"Hero":
			return Color(0.16, 0.075, 0.072)
		_:
			return Color(0.085, 0.095, 0.122)


func _rarity_shadow(rarity: String) -> Color:
	match rarity:
		"Legendary":
			return Color(0.95, 0.62, 0.18, 0.24)
		"Epic":
			return Color(0.62, 0.35, 0.9, 0.22)
		"Hero":
			return Color(0.92, 0.28, 0.22, 0.22)
		_:
			return Color(0, 0, 0, 0.28)


func _type_color(card_type: String) -> Color:
	match card_type:
		"Unit":
			return Color(0.77, 0.86, 1.0)
		"Spell":
			return Color(0.86, 0.72, 1.0)
		"Artifact":
			return Color(0.95, 0.8, 0.42)
		"Hero":
			return Color(1.0, 0.66, 0.58)
		_:
			return Color(0.75, 0.8, 0.9)


func _card_glyph(card_type: String) -> String:
	match card_type:
		"Unit":
			return "U"
		"Spell":
			return "S"
		"Artifact":
			return "A"
		"Hero":
			return "H"
		_:
			return "C"


func _status_color(status_name: String) -> Color:
	match status_name:
		"Burn":
			return Color(0.75, 0.2, 0.12, 0.96)
		"Poison":
			return Color(0.24, 0.55, 0.2, 0.96)
		"Wither", "Cursed":
			return Color(0.42, 0.28, 0.58, 0.96)
		"Invisible":
			return Color(0.25, 0.42, 0.58, 0.96)
		"Vulnerable":
			return Color(0.7, 0.28, 0.18, 0.96)
		"Defender", "Protector":
			return Color(0.24, 0.44, 0.66, 0.96)
		"Crit":
			return Color(0.78, 0.56, 0.14, 0.96)
		"Economic Fury":
			return Color(0.2, 0.56, 0.42, 0.96)
		"Perplexed", "Drunk":
			return Color(0.48, 0.36, 0.62, 0.96)
		_:
			return Color(0.36, 0.42, 0.54, 0.96)


func _chip_style(bg: Color, border: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 3
	style.content_margin_right = 3
	return style


func _card_body_style(data: CardData) -> StyleBoxFlat:
	var tint := _type_color(data.type)
	var bg := _rarity_background(data.rarity).lerp(tint, 0.08)
	bg.a = 0.88
	var border := tint
	border.a = 0.18
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 5
	style.content_margin_right = 5
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	return style


func _name_font_size(text: String) -> int:
	if text.length() > 24:
		return 10
	if text.length() > 16:
		return 11
	return 12


func _rules_font_size(text: String) -> int:
	if text.length() > 120:
		return 8
	if text.length() > 70:
		return 9
	return 10


func _compact_rules_text(data: CardData) -> String:
	var text := data.ability_text.strip_edges().replace("\n", " ")
	text = text.replace("At the start of your turn,", "Start:")
	text = text.replace("At the end of your turn,", "End:")
	text = text.replace("When played,", "Deploy:")
	text = text.replace("This unit", "This")
	var limit := 88
	if text.length() > limit:
		text = text.substr(0, limit - 1).strip_edges() + "..."
	return text


func _status_abbrev(status_name: String) -> String:
	match status_name:
		"Burn":
			return "BRN"
		"Poison":
			return "PSN"
		"Wither":
			return "WTH"
		"Cursed":
			return "CRS"
		"Invisible":
			return "INV"
		"Vulnerable":
			return "VUL"
		"Defender":
			return "DEF"
		"Protector":
			return "PRT"
		"Crit":
			return "CRT"
		"Economic Fury":
			return "ECO"
		"Perplexed":
			return "PRX"
		"Drunk":
			return "DRK"
		_:
			return status_name.substr(0, mini(3, status_name.length())).to_upper()


func _consume_pending_flash() -> void:
	if not card_instance:
		return
	if card_instance.ability_state.has("ui_flash_color"):
		var color: Color = card_instance.ability_state.get("ui_flash_color", Color(1, 1, 1))
		card_instance.ability_state.erase("ui_flash_color")
		call_deferred("pulse_event", color)
	if card_instance.ability_state.has("ui_float_text"):
		var text: String = str(card_instance.ability_state.get("ui_float_text", ""))
		var float_color: Color = card_instance.ability_state.get("ui_float_color", Color(1, 1, 1))
		card_instance.ability_state.erase("ui_float_text")
		card_instance.ability_state.erase("ui_float_color")
		call_deferred("float_text", text, float_color)


func pulse_event(color: Color = Color(1.0, 0.72, 0.24)) -> void:
	if not card_frame:
		return
	if bool(SettingsManager.get_value("reduced_motion", false)):
		card_frame.modulate = color
		await get_tree().process_frame
		card_frame.modulate = Color.WHITE
		return
	var original_scale := scale
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", original_scale * 1.06, 0.08)
	tween.parallel().tween_property(card_frame, "modulate", color, 0.08)
	tween.tween_property(self, "scale", original_scale, 0.18)
	tween.parallel().tween_property(card_frame, "modulate", Color.WHITE, 0.18)


func float_text(text: String, color: Color) -> void:
	var label := Label.new()
	label.name = "FloatText"
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0.02, 0.025, 0.035, 0.9))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.offset_left = 12.0
	label.offset_top = 20.0
	label.offset_right = size.x - 12.0
	label.offset_bottom = 42.0
	label.z_index = 20
	add_child(label)
	if bool(SettingsManager.get_value("reduced_motion", false)):
		await get_tree().create_timer(0.18).timeout
		label.queue_free()
		return
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "position:y", label.position.y - 22.0, 0.42)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.42)
	tween.tween_callback(label.queue_free)


# ── Input ────────────────────────────────────────────────────────────────────

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			accept_event()
			right_clicked.emit(self)
			return
		if event.button_index != MOUSE_BUTTON_LEFT:
			return
		accept_event()
		if event.pressed:
			is_pressed = true
			is_dragging = false
			press_global_position = event.global_position
			original_global_position = global_position
			original_z_index = z_index
			drag_offset = global_position - event.global_position
		else:
			if is_dragging:
				var drop_position: Vector2 = event.global_position
				_end_drag_visual()
				drag_ended.emit(self, drop_position)
			else:
				clicked.emit(self)
			is_pressed = false
	
	if event is InputEventMouseMotion and is_pressed:
		if not is_dragging and event.global_position.distance_to(press_global_position) >= DRAG_THRESHOLD:
			_start_drag_visual()
			drag_started.emit(self)
		if is_dragging:
			accept_event()
			global_position = event.global_position + drag_offset


func _start_drag_visual() -> void:
	is_dragging = true
	top_level = true
	global_position = original_global_position
	z_index = 100
	_tween_scale(Vector2(1.065, 1.065), 0.08)


func _end_drag_visual() -> void:
	is_dragging = false
	global_position = original_global_position
	top_level = false
	z_index = original_z_index
	_tween_scale(Vector2.ONE, 0.12)


func _on_mouse_entered() -> void:
	is_hovered = true
	_tween_scale(Vector2(1.04, 1.04), 0.1)
	hovered.emit(self)
	EventBus.card_hovered.emit(card_instance)


func _on_mouse_exited() -> void:
	is_hovered = false
	if not is_dragging:
		_tween_scale(Vector2.ONE, 0.14)
	unhovered.emit(self)


func set_selected(selected: bool) -> void:
	is_selected = selected
	_update_status_visuals()
	if selected:
		pulse_event(Color(1.0, 0.82, 0.36))


func _tween_scale(target: Vector2, duration: float) -> void:
	pivot_offset = size * 0.5
	if bool(SettingsManager.get_value("reduced_motion", false)):
		scale = target
		return
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", target, duration)
