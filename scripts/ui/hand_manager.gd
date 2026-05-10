## HandManager
## Manages the visual layout of cards in a player's hand.
## Fans cards out along the bottom of the screen with hover/drag interaction.
class_name HandManager
extends HBoxContainer

@export var card_visual_scene: PackedScene
@export var max_card_width: float = 132.0
@export var min_card_width: float = 104.0
@export var fan_curve: float = 0.0  # Keep zero for stable two-player readability

var card_visuals: Array[CardVisual] = []
var player_state: PlayerState = null
var can_play_func: Callable = Callable()  # set by Main; receives CardInstance → bool

signal card_drag_started(card: CardInstance)
signal card_dropped(card: CardInstance, drop_position: Vector2)
signal card_right_clicked(card: CardInstance)


func setup(ps: PlayerState) -> void:
	player_state = ps
	alignment = BoxContainer.ALIGNMENT_CENTER
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
		cv.right_clicked.connect(_on_card_right_clicked)
		cv.drag_started.connect(_on_card_drag_started)
		cv.drag_ended.connect(_on_card_drag_ended)
		card_visuals.append(cv)
		_apply_draggable(cv)

	_layout_cards()
	call_deferred("_layout_cards")


func _layout_cards() -> void:
	"""Arrange cards in a fan pattern."""
	var count: int = card_visuals.size()
	if count == 0:
		return
	var available_width: float = max(size.x, custom_minimum_size.x)
	if available_width <= 0.0:
		available_width = 1400.0
	var separation := 8
	add_theme_constant_override("separation", separation)
	var target_width: float = floor((available_width - float(separation * maxi(count - 1, 0))) / float(count))
	target_width = clampf(target_width, min_card_width, max_card_width)
	for i in range(count):
		var cv: CardVisual = card_visuals[i]
		cv.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		cv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		cv.set_card_dimensions(Vector2(target_width, 150.0))
		cv.rotation_degrees = 0.0
		cv.position.y = 0.0


func _on_card_clicked(cv: CardVisual) -> void:
	for card_visual in card_visuals:
		card_visual.set_selected(card_visual == cv)
	EventBus.card_selected.emit(cv.card_instance)


func _on_card_right_clicked(cv: CardVisual) -> void:
	card_right_clicked.emit(cv.card_instance)


func _on_card_drag_started(cv: CardVisual) -> void:
	for card_visual in card_visuals:
		card_visual.set_selected(card_visual == cv)
	card_drag_started.emit(cv.card_instance)


func _on_card_drag_ended(cv: CardVisual, drop_position: Vector2) -> void:
	card_dropped.emit(cv.card_instance, drop_position)


func clear_selection() -> void:
	for card_visual in card_visuals:
		card_visual.set_selected(false)


func _apply_draggable(cv: CardVisual) -> void:
	if can_play_func.is_valid():
		cv.set_draggable(can_play_func.call(cv.card_instance))
	else:
		cv.set_draggable(true)


func refresh_draggable() -> void:
	for cv in card_visuals:
		_apply_draggable(cv)


func add_card(card_inst: CardInstance) -> void:
	"""Add a newly drawn card to the visual hand."""
	if not card_visual_scene:
		return
	var cv: CardVisual = card_visual_scene.instantiate()
	add_child(cv)
	cv.setup(card_inst)
	cv.clicked.connect(_on_card_clicked)
	cv.right_clicked.connect(_on_card_right_clicked)
	cv.drag_started.connect(_on_card_drag_started)
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


func play_deal_intro(from_top: bool = false) -> void:
	var delay := 0.0
	for cv in card_visuals:
		cv.modulate.a = 0.0
		cv.position.y = -34.0 if from_top else 34.0
		var tween := create_tween()
		tween.tween_interval(delay)
		tween.tween_property(cv, "modulate:a", 1.0, 0.16)
		tween.parallel().tween_property(cv, "position:y", 0.0, 0.18)
		delay += 0.045
