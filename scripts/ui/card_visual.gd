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
	refresh_display()


func set_detail_highlighted(enabled: bool) -> void:
	if not card_frame:
		return
	var style: StyleBoxFlat = card_frame.get_theme_stylebox("panel").duplicate()
	if enabled:
		style.border_color = Color(0.9, 0.75, 0.1)
		style.set_border_width_all(3)
	else:
		style.border_color = Color(0.42, 0.46, 0.55, 1)
		style.set_border_width_all(1)
	card_frame.add_theme_stylebox_override("panel", style)


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


func _update_status_visuals() -> void:
	if not card_instance:
		return
	if is_selected:
		modulate = Color(1.0, 0.95, 0.55)
		return
	# TODO: Add status icons/overlays
	# For now, modulate color as a hint
	if card_instance.has_status("Burn"):
		modulate = Color(1.0, 0.7, 0.5)
	elif card_instance.has_status("Poison"):
		modulate = Color(0.7, 1.0, 0.5)
	elif card_instance.has_status("Cursed"):
		modulate = Color(0.7, 0.5, 0.7)
	else:
		modulate = Color.WHITE


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
