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
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_ensure_overlays()
	refresh_display()


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
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		mouse_default_cursor_shape = Control.CURSOR_ARROW
		modulate.a = 0.5


func refresh_display() -> void:
	if not card_instance:
		return
	
	var data: CardData = card_instance.data
	_ensure_overlays()
	_apply_frame_style()
	
	if name_label:
		name_label.text = data.name
		name_label.tooltip_text = data.ability_text if data.has_ability else data.name
	if card_art:
		card_art.visible = false
	if power_label:
		var show_power: bool = card_instance.current_power > 0 or data.type == "Unit" or data.type == "Hero"
		power_label.visible = show_power
		if show_power:
			power_label.text = str(card_instance.current_power)
			# Tint red if damaged, green if boosted
			if card_instance.current_power < data.base_power:
				power_label.modulate = Color(1.0, 0.4, 0.4)
			elif card_instance.current_power > data.base_power:
				power_label.modulate = Color(0.4, 1.0, 0.4)
			else:
				power_label.modulate = Color.WHITE
	if type_label:
		type_label.visible = true
		type_label.text = data.type
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
	if not status_label:
		return
	var parts: Array[String] = []
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
	status_label.visible = not parts.is_empty()
	status_label.text = " ".join(parts)


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


func _ensure_overlays() -> void:
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


func _apply_frame_style() -> void:
	if not card_frame or not card_instance:
		return
	var style: StyleBoxFlat = card_frame.get_theme_stylebox("panel").duplicate()
	style.bg_color = Color(0.095, 0.105, 0.135)
	style.border_color = _rarity_color(card_instance.data.rarity)
	style.set_border_width_all(2)
	style.shadow_color = Color(0, 0, 0, 0.28)
	style.shadow_size = 4
	style.shadow_offset = Vector2(0, 2)
	if is_selected:
		style.border_color = Color(0.9, 0.75, 0.1)
		style.set_border_width_all(3)
	card_frame.add_theme_stylebox_override("panel", style)
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
	if not card_instance or not card_instance.ability_state.has("ui_flash_color"):
		return
	var color: Color = card_instance.ability_state.get("ui_flash_color", Color(1, 1, 1))
	card_instance.ability_state.erase("ui_flash_color")
	call_deferred("pulse_event", color)


func pulse_event(color: Color = Color(1.0, 0.72, 0.24)) -> void:
	if not card_frame:
		return
	var original_scale := scale
	var tween := create_tween()
	tween.tween_property(self, "scale", original_scale * 1.06, 0.08)
	tween.parallel().tween_property(card_frame, "modulate", color, 0.08)
	tween.tween_property(self, "scale", original_scale, 0.18)
	tween.parallel().tween_property(card_frame, "modulate", Color.WHITE, 0.18)


# ── Input ────────────────────────────────────────────────────────────────────

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			accept_event()
			right_clicked.emit(self)
			EventBus.card_detail_requested.emit(self)
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
	scale = Vector2(1.04, 1.04)


func _end_drag_visual() -> void:
	is_dragging = false
	global_position = original_global_position
	top_level = false
	z_index = original_z_index
	scale = Vector2.ONE


func _on_mouse_entered() -> void:
	is_hovered = true
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector2(1.04, 1.04), 0.08)
	hovered.emit(self)
	EventBus.card_hovered.emit(card_instance)


func _on_mouse_exited() -> void:
	is_hovered = false
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.08)
	unhovered.emit(self)


func set_selected(selected: bool) -> void:
	is_selected = selected
	_update_status_visuals()
