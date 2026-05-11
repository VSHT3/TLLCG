## BoardVisual
## Visual representation of one player's side of the board.
## Contains 3 rows of card slots (melee: 5, ranged: 5, artillery: 3).
class_name BoardVisual
extends VBoxContainer

@export var card_visual_scene: PackedScene
@export var slot_scene: PackedScene  # A panel/container for each slot

var rows: Array = [[], [], []]  # Visual slots per row
var player_state: PlayerState = null
var _target_mode: bool = false
var _valid_targets: Array = []
var _highlighted_slots: Array[Panel] = []

signal card_dropped_on_row(card: CardInstance, row_idx: int)
signal row_selected(row_idx: int, col_idx: int)
signal target_card_clicked(card: CardInstance)
signal inspect_card_clicked(card: CardInstance)
signal ability_card_clicked(card: CardInstance)


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
	slot.custom_minimum_size = Vector2(170, 82)
	slot.name = "Slot_%d_%d" % [row_idx, col]
	slot.mouse_filter = Control.MOUSE_FILTER_STOP
	slot.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	
	# Visual styling
	_apply_slot_idle_style(slot)
	
	# Store metadata
	slot.set_meta("row", row_idx)
	slot.set_meta("col", col)
	slot.gui_input.connect(_on_slot_gui_input.bind(row_idx, col))
	
	return slot


func _on_slot_gui_input(event: InputEvent, row_idx: int, col_idx: int) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			row_selected.emit(row_idx, col_idx)


func refresh() -> void:
	"""Update all card visuals from player state."""
	# Clear existing card visuals from slots
	for row in rows:
		for slot in row:
			for child in slot.get_children():
				child.queue_free()
	
	if not player_state:
		return
	
	# Place cards using stored board_position so cards stay in their original slot
	for row_idx in range(player_state.board.size()):
		for card_inst in player_state.board[row_idx]:
			var col_idx: int = card_inst.board_position.get("col", 0)
			if col_idx < rows[row_idx].size():
				var slot: Panel = rows[row_idx][col_idx]
				_place_card_in_slot(card_inst, slot)

	if _target_mode:
		_apply_target_highlights()


func enter_target_mode(valid_targets: Array) -> void:
	_target_mode = true
	_valid_targets = valid_targets
	_apply_target_highlights()


func exit_target_mode() -> void:
	_target_mode = false
	_valid_targets = []
	_apply_target_highlights()


func _apply_target_highlights() -> void:
	for row in rows:
		for slot in row:
			for child in slot.get_children():
				if child is CardVisual:
					var inst: CardInstance = child.card_instance
					if _target_mode and inst in _valid_targets:
						child.modulate = SettingsManager.color("accent")
						child.set_detail_highlighted(true)
						child.pulse_event(SettingsManager.color("accent"))
					else:
						child.modulate = Color.WHITE
						child.set_detail_highlighted(false)
					# Always keep MOUSE_FILTER_STOP so right-click detail works
					child.mouse_filter = Control.MOUSE_FILTER_STOP


func _place_card_in_slot(card_inst: CardInstance, slot: Panel) -> void:
	if not card_visual_scene:
		return
	var cv: CardVisual = card_visual_scene.instantiate()
	slot.add_child(cv)
	cv.setup(card_inst)
	cv.set_card_dimensions(slot.custom_minimum_size)
	# Always accept input so right-click detail works; left-click gated inside handler
	cv.mouse_filter = Control.MOUSE_FILTER_STOP
	cv.clicked.connect(_on_board_card_clicked)
	cv.right_clicked.connect(_on_board_card_right_clicked)


func pulse_card(card: CardInstance, color: Color = Color(1.0, 0.72, 0.24)) -> void:
	for row in rows:
		for slot in row:
			for child in slot.get_children():
				if child is CardVisual and child.card_instance == card:
					child.pulse_event(color)
					return


func float_card_text(card: CardInstance, text: String, color: Color) -> void:
	for row in rows:
		for slot in row:
			for child in slot.get_children():
				if child is CardVisual and child.card_instance == card:
					child.float_text(text, color)
					return


func _on_board_card_clicked(cv: CardVisual) -> void:
	if _target_mode and cv.card_instance in _valid_targets:
		target_card_clicked.emit(cv.card_instance)
	elif not _target_mode:
		inspect_card_clicked.emit(cv.card_instance)


func _on_board_card_right_clicked(cv: CardVisual) -> void:
	if not _target_mode:
		ability_card_clicked.emit(cv.card_instance)


func get_row_at_global_position(pos: Vector2) -> int:
	for row_idx in range(rows.size()):
		for slot in rows[row_idx]:
			if slot.get_global_rect().has_point(pos):
				return row_idx
	return -1


func get_slot_at_global_position(pos: Vector2) -> Dictionary:
	for row_idx in range(rows.size()):
		for col_idx in range(rows[row_idx].size()):
			if rows[row_idx][col_idx].get_global_rect().has_point(pos):
				return {"row": row_idx, "col": col_idx}
	return {"row": -1, "col": -1}


func highlight_valid_rows(valid_rows: Array[int]) -> void:
	"""Highlight empty slots in valid rows."""
	for row_idx in range(rows.size()):
		for col_idx in range(rows[row_idx].size()):
			var slot: Panel = rows[row_idx][col_idx]
			var occupied: bool = player_state and player_state.is_slot_occupied(row_idx, col_idx)
			if row_idx in valid_rows and not occupied:
				slot.add_theme_stylebox_override("panel", _slot_style(Color(0.07, 0.17, 0.105, 0.96), Color(0.54, 0.92, 0.46), 3))
				_pulse_slot(slot)
			else:
				_apply_slot_idle_style(slot)


func clear_highlights() -> void:
	for row in rows:
		for slot in row:
			_apply_slot_idle_style(slot)
			slot.modulate = Color.WHITE
	_highlighted_slots.clear()


func _apply_slot_idle_style(slot: Panel) -> void:
	slot.add_theme_stylebox_override("panel", _slot_style(SettingsManager.color("panel_soft") * Color(0.82, 0.86, 0.92, 0.76), SettingsManager.color("border"), 1))


func _pulse_slot(slot: Panel) -> void:
	if slot in _highlighted_slots:
		return
	_highlighted_slots.append(slot)
	if bool(SettingsManager.get_value("reduced_motion", false)):
		return
	slot.pivot_offset = slot.size * 0.5
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tween.tween_property(slot, "scale", Vector2(1.025, 1.025), 0.1)
	tween.parallel().tween_property(slot, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.1)
	tween.tween_property(slot, "scale", Vector2.ONE, 0.18)


func _slot_style(bg: Color, border: Color, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(4)
	style.shadow_color = Color(0, 0, 0, 0.16)
	style.shadow_size = 3
	style.shadow_offset = Vector2(0, 2)
	return style
