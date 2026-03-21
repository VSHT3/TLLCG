## BoardVisual
## Visual representation of one player's side of the board.
## Contains 3 rows of card slots (melee: 5, ranged: 5, artillery: 3).
class_name BoardVisual
extends VBoxContainer

@export var card_visual_scene: PackedScene
@export var slot_scene: PackedScene  # A panel/container for each slot

var rows: Array = [[], [], []]  # Visual slots per row
var player_state: PlayerState = null

signal card_dropped_on_row(card: CardInstance, row_idx: int)


func setup(ps: PlayerState) -> void:
	player_state = ps
	_build_rows()
	refresh()


func _build_rows() -> void:
	"""Create visual slot containers for each row."""
	for row_idx in range(GameConstants.ROW_CAPACITIES.size()):
		var row_container := HBoxContainer.new()
		row_container.name = "Row_%s" % GameConstants.ROW_NAMES[row_idx]
		row_container.alignment = BoxContainer.ALIGNMENT_CENTER
		row_container.add_theme_constant_override("separation", 8)
		add_child(row_container)
		
		var capacity: int = GameConstants.ROW_CAPACITIES[row_idx]
		for col in range(capacity):
			var slot: Panel = _create_slot(row_idx, col)
			row_container.add_child(slot)
			rows[row_idx].append(slot)


func _create_slot(row_idx: int, col: int) -> Panel:
	"""Create a single board slot (drop target)."""
	var slot := Panel.new()
	slot.custom_minimum_size = Vector2(100, 140)
	slot.name = "Slot_%d_%d" % [row_idx, col]
	
	# Visual styling
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.15, 0.2, 0.5)
	style.border_color = Color(0.3, 0.3, 0.4)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	slot.add_theme_stylebox_override("panel", style)
	
	# Store metadata
	slot.set_meta("row", row_idx)
	slot.set_meta("col", col)
	
	return slot


func refresh() -> void:
	"""Update all card visuals from player state."""
	# Clear existing card visuals from slots
	for row in rows:
		for slot in row:
			for child in slot.get_children():
				child.queue_free()
	
	if not player_state:
		return
	
	# Place cards
	for row_idx in range(player_state.board.size()):
		for col_idx in range(player_state.board[row_idx].size()):
			var card_inst: CardInstance = player_state.board[row_idx][col_idx]
			if col_idx < rows[row_idx].size():
				var slot: Panel = rows[row_idx][col_idx]
				_place_card_in_slot(card_inst, slot)


func _place_card_in_slot(card_inst: CardInstance, slot: Panel) -> void:
	if not card_visual_scene:
		return
	var cv: CardVisual = card_visual_scene.instantiate()
	slot.add_child(cv)
	cv.setup(card_inst)
	cv.custom_minimum_size = slot.custom_minimum_size


func highlight_valid_rows(valid_rows: Array[int]) -> void:
	"""Highlight rows where a card can be placed."""
	for row_idx in range(rows.size()):
		for slot in rows[row_idx]:
			var style: StyleBoxFlat = slot.get_theme_stylebox("panel").duplicate()
			if row_idx in valid_rows:
				style.border_color = Color(0.2, 0.8, 0.2)  # Green highlight
				style.set_border_width_all(2)
			else:
				style.border_color = Color(0.3, 0.3, 0.4)
				style.set_border_width_all(1)
			slot.add_theme_stylebox_override("panel", style)


func clear_highlights() -> void:
	for row in rows:
		for slot in row:
			var style: StyleBoxFlat = slot.get_theme_stylebox("panel").duplicate()
			style.border_color = Color(0.3, 0.3, 0.4)
			style.set_border_width_all(1)
			slot.add_theme_stylebox_override("panel", style)
