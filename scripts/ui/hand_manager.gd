## HandManager
## Manages the visual layout of cards in a player's hand.
## Fans cards out along the bottom of the screen with hover/drag interaction.
class_name HandManager
extends HBoxContainer

@export var card_visual_scene: PackedScene
@export var max_card_width: float = 120.0
@export var fan_curve: float = 5.0  # Degrees of rotation for fan effect

var card_visuals: Array[CardVisual] = []
var player_state: PlayerState = null


func setup(ps: PlayerState) -> void:
	player_state = ps
	refresh()


func refresh() -> void:
	"""Rebuild hand display from player state."""
	# Clear old
	for cv in card_visuals:
		cv.queue_free()
	card_visuals.clear()
	
	if not player_state:
		return
	
	# Create card visuals
	for card_inst in player_state.hand:
		var cv: CardVisual = card_visual_scene.instantiate()
		add_child(cv)
		cv.setup(card_inst)
		cv.clicked.connect(_on_card_clicked)
		cv.drag_ended.connect(_on_card_drag_ended)
		card_visuals.append(cv)
	
	_layout_cards()


func _layout_cards() -> void:
	"""Arrange cards in a fan pattern."""
	var count: int = card_visuals.size()
	if count == 0:
		return
	
	for i in range(count):
		var cv: CardVisual = card_visuals[i]
		# Calculate fan rotation
		var center_offset := float(i) - float(count - 1) / 2.0
		cv.rotation_degrees = center_offset * fan_curve
		# Slight Y offset for arc effect
		cv.position.y = abs(center_offset) * 5.0


func _on_card_clicked(cv: CardVisual) -> void:
	EventBus.card_selected.emit(cv.card_instance)


func _on_card_drag_ended(cv: CardVisual, drop_pos: Vector2) -> void:
	# Check if dropped on board area (handled by the game scene)
	# For now, return to hand
	cv.return_to_original()


func add_card(card_inst: CardInstance) -> void:
	"""Add a newly drawn card to the visual hand."""
	if not card_visual_scene:
		return
	var cv: CardVisual = card_visual_scene.instantiate()
	add_child(cv)
	cv.setup(card_inst)
	cv.clicked.connect(_on_card_clicked)
	cv.drag_ended.connect(_on_card_drag_ended)
	card_visuals.append(cv)
	_layout_cards()


func remove_card(card_inst: CardInstance) -> void:
	"""Remove a card from the visual hand (when played/discarded)."""
	for i in range(card_visuals.size()):
		if card_visuals[i].card_instance == card_inst:
			card_visuals[i].queue_free()
			card_visuals.remove_at(i)
			_layout_cards()
			return
