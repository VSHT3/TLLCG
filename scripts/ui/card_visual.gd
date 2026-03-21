## CardVisual
## The visual representation of a card. Handles rendering, hover, click, drag.
## Attach this to a card scene (card_visual.tscn).
class_name CardVisual
extends Control

# ── References ───────────────────────────────────────────────────────────────

@onready var card_art: TextureRect = $CardArt
@onready var card_frame: NinePatchRect = $CardFrame
@onready var name_label: Label = $NameLabel
@onready var power_label: Label = $PowerLabel
@onready var type_label: Label = $TypeLabel
@onready var ability_label: RichTextLabel = $AbilityLabel
@onready var cost_label: Label = $CostLabel  # For sellary cost display

# ── State ────────────────────────────────────────────────────────────────────

var card_instance: CardInstance = null
var is_dragging: bool = false
var is_hovered: bool = false
var drag_offset: Vector2 = Vector2.ZERO
var original_position: Vector2 = Vector2.ZERO

# ── Signals ──────────────────────────────────────────────────────────────────

signal clicked(card_visual: CardVisual)
signal drag_started(card_visual: CardVisual)
signal drag_ended(card_visual: CardVisual, drop_position: Vector2)
signal hovered(card_visual: CardVisual)
signal unhovered(card_visual: CardVisual)


# ── Setup ────────────────────────────────────────────────────────────────────

func setup(inst: CardInstance) -> void:
	card_instance = inst
	refresh_display()


func refresh_display() -> void:
	if not card_instance:
		return
	
	var data: CardData = card_instance.data
	
	# Name
	if name_label:
		name_label.text = data.name
	
	# Power (show current, highlight if different from base)
	if power_label:
		if data.is_boardable():
			power_label.text = str(card_instance.current_power)
			if card_instance.current_power > data.base_power:
				power_label.add_theme_color_override("font_color", Color.GREEN)
			elif card_instance.current_power < data.base_power:
				power_label.add_theme_color_override("font_color", Color.RED)
			else:
				power_label.add_theme_color_override("font_color", Color.WHITE)
			power_label.visible = true
		else:
			power_label.visible = false
	
	# Type indicator
	if type_label:
		type_label.text = data.type
	
	# Ability text
	if ability_label:
		if data.has_ability and data.ability_text:
			ability_label.text = data.ability_text
			ability_label.visible = true
		else:
			ability_label.visible = false
	
	# Artwork
	if card_art and data.artwork_path:
		var art_path: String = "res://assets/artworks/" + data.artwork_path
		if ResourceLoader.exists(art_path):
			card_art.texture = load(art_path)
	
	# Status indicators (visual cue)
	_update_status_visuals()


func _update_status_visuals() -> void:
	if not card_instance:
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
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				clicked.emit(self)
				# Start drag
				is_dragging = true
				drag_offset = global_position - event.global_position
				original_position = global_position
				drag_started.emit(self)
			else:
				if is_dragging:
					is_dragging = false
					drag_ended.emit(self, event.global_position)
	
	if event is InputEventMouseMotion and is_dragging:
		global_position = event.global_position + drag_offset


func _on_mouse_entered() -> void:
	is_hovered = true
	# Scale up slightly for hover effect
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector2(1.1, 1.1), 0.1)
	hovered.emit(self)
	EventBus.card_hovered.emit(card_instance)


func _on_mouse_exited() -> void:
	is_hovered = false
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.1)
	unhovered.emit(self)


func snap_to_position(pos: Vector2, duration: float = 0.2) -> void:
	var tween := create_tween()
	tween.tween_property(self, "global_position", pos, duration).set_ease(Tween.EASE_OUT)


func return_to_original() -> void:
	snap_to_position(original_position)
