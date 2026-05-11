## MainMenu
## Handles the pre-game initialization flow per Rulebook:
##   1. Dice roll → determines first pick order
##   2. Each player picks a faction (reverse first-pick order)
##   3. Show summary → start game
class_name MainMenu
extends Control

# ── State ─────────────────────────────────────────────────────────────────────

enum Phase { TITLE, DICE_ROLL, FACTION_PICK, SUMMARY }

var _phase: Phase = Phase.TITLE
var _dice_results: Array[int] = [-1, -1]          # [p0_roll, p1_roll]
var _first_picker: int = -1                        # player_id who picks first
var _faction_choices: Array[String] = ["", ""]    # [p0_faction, p1_faction]
var _pick_order: Array[int] = []                  # order players pick factions

const GAME_SCENE := "res://scenes/main/main.tscn"

# Factions excluding Neutral
var _factions: Array[String] = []
var _book_panel: PanelContainer = null
var _book_title: Label = null
var _book_list: VBoxContainer = null
var _book_detail: RichTextLabel = null
var _book_search: LineEdit = null
var _book_filter: OptionButton = null
var _book_effect_filter: OptionButton = null
var _book_sort: OptionButton = null
var _book_faction_tabs: HBoxContainer = null
var _book_cards: Array[CardData] = []
var _book_active_faction: String = "All"
var _rulebook_panel: PanelContainer = null
var _rulebook_tabs: TabContainer = null
var _sound_button: Button = null
var _settings_panel = null
const SettingsPanelScript := preload("res://scripts/ui/settings_panel.gd")

# ── Node refs ──────────────────────────────────────────────────────────────────

@onready var title_screen: Control      = $TitleScreen
@onready var dice_screen: Control       = $DiceScreen
@onready var faction_screen: Control    = $FactionScreen
@onready var summary_screen: Control    = $SummaryScreen

# Title
@onready var start_button: Button       = $TitleScreen/VBox/StartButton
@onready var title_label: Label         = $TitleScreen/VBox/TitleLabel
@onready var subtitle_label: Label      = $TitleScreen/VBox/SubtitleLabel

# Dice
@onready var dice_label: Label          = $DiceScreen/VBox/DiceLabel
@onready var p0_die_label: Label        = $DiceScreen/VBox/DiceRow/P0Block/P0Die
@onready var p1_die_label: Label        = $DiceScreen/VBox/DiceRow/P1Block/P1Die
@onready var dice_result_label: Label   = $DiceScreen/VBox/ResultLabel
@onready var roll_button: Button        = $DiceScreen/VBox/RollButton

# Faction pick
@onready var pick_prompt: Label         = $FactionScreen/VBox/PickPrompt
@onready var faction_grid: GridContainer = $FactionScreen/VBox/FactionGrid

# Summary
@onready var summary_label: Label       = $SummaryScreen/VBox/SummaryLabel
@onready var launch_button: Button      = $SummaryScreen/VBox/LaunchButton


# ── Lifecycle ──────────────────────────────────────────────────────────────────

func _ready() -> void:
	AudioManager.set_music_context(AudioManager.MUSIC_CONTEXT_MENU)
	_factions = _get_playable_factions()
	_build_menu_actions()
	_build_settings_panel()
	_build_card_book()
	_build_rulebook()
	_apply_menu_theme()
	SettingsManager.settings_changed.connect(func(key: String, _value: Variant) -> void:
		if key == "theme":
			_apply_menu_theme()
	)
	start_button.pressed.connect(_on_start_pressed)
	roll_button.pressed.connect(_on_roll_pressed)
	launch_button.pressed.connect(_on_launch_pressed)
	_show_phase(Phase.TITLE)


# ── Phase control ─────────────────────────────────────────────────────────────

func _show_phase(phase: Phase) -> void:
	_phase = phase
	title_screen.visible   = phase == Phase.TITLE
	dice_screen.visible    = phase == Phase.DICE_ROLL
	faction_screen.visible = phase == Phase.FACTION_PICK
	summary_screen.visible = phase == Phase.SUMMARY


# ── Title ──────────────────────────────────────────────────────────────────────

func _on_start_pressed() -> void:
	AudioManager.play_ui()
	_show_phase(Phase.DICE_ROLL)
	_reset_dice_ui()


# ── Dice Roll ──────────────────────────────────────────────────────────────────

func _reset_dice_ui() -> void:
	p0_die_label.text = "?"
	p1_die_label.text = "?"
	dice_result_label.text = "Roll to determine first faction pick."
	_dice_results = [-1, -1]
	roll_button.disabled = false


func _on_roll_pressed() -> void:
	AudioManager.play_ui()
	roll_button.disabled = true
	_animate_dice_roll()


func _animate_dice_roll() -> void:
	var tween := create_tween()
	var steps := 12
	for i in range(steps):
		tween.tween_callback(func():
			p0_die_label.text = str(randi_range(1, 20))
			p1_die_label.text = str(randi_range(1, 20))
		)
		tween.tween_interval(0.05 + i * 0.01)
	tween.tween_callback(_finish_dice_roll)


func _finish_dice_roll() -> void:
	var p0: int = randi_range(1, 20)
	var p1: int = randi_range(1, 20)
	# Reroll ties
	while p0 == p1:
		p0 = randi_range(1, 20)
		p1 = randi_range(1, 20)
	_dice_results = [p0, p1]
	p0_die_label.text = str(p0)
	p1_die_label.text = str(p1)

	_first_picker = 0 if p0 > p1 else 1
	var first_name := "Player %d" % (_first_picker + 1)
	dice_result_label.text = "%s rolled higher — picks faction first!" % first_name

	# Rulebook: faction picks happen in reverse first-pick order
	# So second-place picker picks first in faction selection
	var second_picker: int = 1 - _first_picker
	_pick_order = [second_picker, _first_picker]

	await get_tree().create_timer(1.6).timeout
	_begin_faction_picks()


# ── Faction Pick ───────────────────────────────────────────────────────────────

func _begin_faction_picks() -> void:
	_faction_choices = ["", ""]
	_show_phase(Phase.FACTION_PICK)
	_show_faction_pick_for_next()


func _show_faction_pick_for_next() -> void:
	# Find next player who hasn't picked yet (in pick order)
	var current_picker: int = -1
	for pid in _pick_order:
		if _faction_choices[pid] == "":
			current_picker = pid
			break

	if current_picker == -1:
		# Both picked
		_show_phase(Phase.SUMMARY)
		_populate_summary()
		return

	pick_prompt.text = "PLAYER %d: CHOOSE HERO FACTION" % (current_picker + 1)

	# Clear old buttons
	for child in faction_grid.get_children():
		child.queue_free()
	faction_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	faction_grid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	faction_grid.columns = 2

	var taken: Array[String] = []
	for c in _faction_choices:
		if c != "":
			taken.append(c)

	for faction in _factions:
		var btn := Button.new()
		btn.text = faction
		btn.custom_minimum_size = Vector2(280, 76)
		btn.add_theme_font_size_override("font_size", 18)
		_style_button(btn)
		btn.disabled = faction in taken
		if faction in taken:
			btn.modulate = Color(0.48, 0.48, 0.48)
		btn.pressed.connect(_on_faction_chosen.bind(current_picker, faction))
		faction_grid.add_child(btn)


func _on_faction_chosen(player_id: int, faction: String) -> void:
	AudioManager.play_ui()
	_faction_choices[player_id] = faction
	_show_faction_pick_for_next()


# ── Summary ────────────────────────────────────────────────────────────────────

func _populate_summary() -> void:
	var first_name := "Player %d" % (_first_picker + 1)
	summary_label.text = (
		"READY TO PLAY\n\n" +
		"Player 1  →  %s\n" % _faction_choices[0] +
		"Player 2  →  %s\n\n" % _faction_choices[1] +
		"%s goes first." % first_name
	)


func _on_launch_pressed() -> void:
	AudioManager.play_ui()
	# Pass choices to the game scene via global or autoload
	GameConstants.pending_faction_choices = _faction_choices
	GameConstants.first_player_id = _first_picker
	get_tree().change_scene_to_file(GAME_SCENE)


# ── Library / Rulebook ─────────────────────────────────────────────────────────

func _build_menu_actions() -> void:
	var actions := HBoxContainer.new()
	actions.name = "LibraryActions"
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 12)
	start_button.get_parent().add_child(actions)

	var book_button := _menu_button("CARD BOOK", Vector2(180, 48))
	book_button.pressed.connect(func():
		AudioManager.play_ui()
		_open_card_book()
	)
	actions.add_child(book_button)

	var rules_button := _menu_button("RULEBOOK", Vector2(180, 48))
	rules_button.pressed.connect(func():
		AudioManager.play_ui()
		_open_rulebook()
	)
	actions.add_child(rules_button)

	_sound_button = _menu_button("SOUND ON", Vector2(150, 48))
	_sound_button.pressed.connect(_toggle_sound)
	actions.add_child(_sound_button)
	_update_sound_button()

	var quit_button := _menu_button("QUIT GAME", Vector2(150, 48))
	quit_button.pressed.connect(func():
		AudioManager.play_ui()
		get_tree().quit()
	)
	actions.add_child(quit_button)


func _build_settings_panel() -> void:
	_settings_panel = SettingsPanelScript.new()
	_settings_panel.name = "MenuSettings"
	_settings_panel.build(Vector2(1766, 70), false)
	add_child(_settings_panel)


func _apply_menu_theme() -> void:
	var background := get_node_or_null("Background") as ColorRect
	if background:
		background.color = SettingsManager.color("background")
	for label in [title_label, subtitle_label, dice_label, dice_result_label, pick_prompt, summary_label]:
		if label:
			label.add_theme_color_override("font_color", SettingsManager.color("text"))
	if title_label:
		title_label.add_theme_color_override("font_color", SettingsManager.color("accent"))
	for button in [start_button, roll_button, launch_button]:
		_style_button(button)
	if faction_screen:
		faction_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if faction_grid:
		faction_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		faction_grid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		faction_grid.add_theme_constant_override("h_separation", 18)
		faction_grid.add_theme_constant_override("v_separation", 14)
	_style_control_tree(self)


func _style_control_tree(node: Node) -> void:
	if node is Button:
		_style_button(node)
	for child in node.get_children():
		_style_control_tree(child)


func _style_button(button: Button) -> void:
	if not button:
		return
	button.add_theme_stylebox_override("normal", _panel_style(SettingsManager.color("panel_soft"), SettingsManager.color("border"), 1))
	button.add_theme_stylebox_override("hover", _panel_style(SettingsManager.color("panel"), SettingsManager.color("accent"), 1))
	button.add_theme_stylebox_override("pressed", _panel_style(SettingsManager.color("rail"), SettingsManager.color("accent"), 1))
	button.add_theme_color_override("font_color", SettingsManager.color("text"))
	_wire_button_motion(button)


func _wire_button_motion(button: Button) -> void:
	if button.has_meta("motion_wired"):
		return
	button.set_meta("motion_wired", true)
	button.mouse_entered.connect(func() -> void:
		_tween_button_scale(button, Vector2(1.025, 1.025), 0.11)
	)
	button.mouse_exited.connect(func() -> void:
		_tween_button_scale(button, Vector2.ONE, 0.14)
	)
	button.button_down.connect(func() -> void:
		_tween_button_scale(button, Vector2(0.985, 0.985), 0.06)
	)
	button.button_up.connect(func() -> void:
		_tween_button_scale(button, Vector2(1.025, 1.025) if button.is_hovered() else Vector2.ONE, 0.12)
	)


func _tween_button_scale(button: Button, target: Vector2, duration: float) -> void:
	button.pivot_offset = button.size * 0.5
	if bool(SettingsManager.get_value("reduced_motion", false)):
		button.scale = target
		return
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tween.tween_property(button, "scale", target, duration)


func _menu_button(text: String, min_size: Vector2) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = min_size
	button.add_theme_font_size_override("font_size", 16)
	_style_button(button)
	return button


func _toggle_sound() -> void:
	AudioManager.toggle_enabled()
	_update_sound_button()


func _update_sound_button() -> void:
	if _sound_button and AudioManager:
		_sound_button.text = "SOUND ON" if AudioManager.enabled else "SOUND OFF"


func _build_card_book() -> void:
	_book_panel = PanelContainer.new()
	_book_panel.name = "CardBook"
	_book_panel.visible = false
	_book_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_book_panel.set_anchors_preset(Control.PRESET_CENTER)
	_book_panel.offset_left = -760.0
	_book_panel.offset_top = -430.0
	_book_panel.offset_right = 760.0
	_book_panel.offset_bottom = 430.0
	add_child(_book_panel)
	_book_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.105, 0.115, 0.145), Color(0.55, 0.48, 0.26), 2))

	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 10)
	_book_panel.add_child(root)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	root.add_child(header)

	_book_title = Label.new()
	_book_title.text = "Card Book"
	_book_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_book_title.add_theme_font_size_override("font_size", 24)
	_book_title.add_theme_color_override("font_color", Color(0.95, 0.84, 0.48))
	header.add_child(_book_title)

	var close := _menu_button("Close", Vector2(96, 36))
	close.pressed.connect(func():
		_book_panel.visible = false
	)
	header.add_child(close)

	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 8)
	root.add_child(tools)

	_book_search = LineEdit.new()
	_book_search.placeholder_text = "Search cards"
	_book_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_book_search.text_changed.connect(func(_text: String):
		_refresh_card_book_list()
	)
	tools.add_child(_book_search)

	_book_filter = OptionButton.new()
	_book_filter.custom_minimum_size = Vector2(260, 36)
	_book_filter.item_selected.connect(func(_idx: int):
		_refresh_card_book_list()
	)
	tools.add_child(_book_filter)

	_book_effect_filter = OptionButton.new()
	_book_effect_filter.custom_minimum_size = Vector2(210, 36)
	_book_effect_filter.item_selected.connect(func(_idx: int):
		_refresh_card_book_list()
	)
	tools.add_child(_book_effect_filter)

	_book_sort = OptionButton.new()
	_book_sort.custom_minimum_size = Vector2(190, 36)
	_book_sort.item_selected.connect(func(_idx: int):
		_refresh_card_book_list()
	)
	tools.add_child(_book_sort)

	_book_faction_tabs = HBoxContainer.new()
	_book_faction_tabs.add_theme_constant_override("separation", 6)
	root.add_child(_book_faction_tabs)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)

	var list_panel := PanelContainer.new()
	list_panel.custom_minimum_size = Vector2(470, 0)
	list_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.075, 0.085, 0.11), Color(0.24, 0.27, 0.35), 1))
	body.add_child(list_panel)

	var list_scroll := ScrollContainer.new()
	list_panel.add_child(list_scroll)

	_book_list = VBoxContainer.new()
	_book_list.add_theme_constant_override("separation", 4)
	list_scroll.add_child(_book_list)

	var detail_panel := PanelContainer.new()
	detail_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.08, 0.09, 0.12), Color(0.24, 0.27, 0.35), 1))
	body.add_child(detail_panel)

	_book_detail = RichTextLabel.new()
	_book_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_book_detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_book_detail.custom_minimum_size = Vector2(840, 640)
	_book_detail.bbcode_enabled = true
	_book_detail.fit_content = false
	_book_detail.scroll_active = true
	_book_detail.add_theme_font_size_override("normal_font_size", 15)
	detail_panel.add_child(_book_detail)


func _open_card_book() -> void:
	_populate_card_book_filters()
	_refresh_card_book_list()
	_book_panel.visible = true
	_rulebook_panel.visible = false
	_animate_panel_open(_book_panel)


func _populate_card_book_filters() -> void:
	_book_filter.clear()
	_book_filter.add_item("All cards")
	for rarity in ["Common", "Rare", "Epic", "Legendary", "Hero", "Unknown"]:
		_book_filter.add_item("Rarity: %s" % rarity)
	for card_type in ["Unit", "Spell", "Artifact", "Hero", "Unknown"]:
		_book_filter.add_item("Type: %s" % card_type)
	for faction in _sorted_strings(_collect_factions_from_cards()):
		_book_filter.add_item("Faction: %s" % faction)
	for category in _sorted_strings(_collect_categories_from_cards()):
		_book_filter.add_item("Category: %s" % category)

	_book_effect_filter.clear()
	_book_effect_filter.add_item("Any effect")
	for key in _sorted_strings(_collect_effect_filters()):
		_book_effect_filter.add_item(key)

	_book_sort.clear()
	for mode in ["Sort: Name", "Sort: Rarity", "Sort: Type", "Sort: Faction", "Sort: Effects"]:
		_book_sort.add_item(mode)

	for child in _book_faction_tabs.get_children():
		child.queue_free()
	for faction in ["All"] + _sorted_strings(_collect_factions_from_cards()):
		var button := _menu_button(faction, Vector2(0, 32))
		button.toggle_mode = true
		button.button_pressed = faction == _book_active_faction
		button.pressed.connect(Callable(self, "_on_book_faction_tab_pressed").bind(str(faction)))
		_book_faction_tabs.add_child(button)


func _on_book_faction_tab_pressed(faction: String) -> void:
	_book_active_faction = faction
	_refresh_faction_tab_state()
	_refresh_card_book_list()


func _refresh_faction_tab_state() -> void:
	for child in _book_faction_tabs.get_children():
		if child is Button:
			child.button_pressed = child.text == _book_active_faction


func _refresh_card_book_list() -> void:
	for child in _book_list.get_children():
		child.queue_free()
	_book_cards = _filtered_cards()
	for card in _book_cards:
		var button := Button.new()
		button.text = "%s  [%s / %s]" % [card.name, card.type, card.rarity]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size = Vector2(0, 34)
		button.add_theme_color_override("font_color", _rarity_color(card.rarity))
		_style_button(button)
		button.pressed.connect(Callable(self, "_show_book_card").bind(card))
		_book_list.add_child(button)
	if _book_cards.is_empty():
		_book_detail.text = "[center]No cards match the filter.[/center]"
	else:
		_show_book_card(_book_cards[0])


func _filtered_cards() -> Array[CardData]:
	var query := _book_search.text.strip_edges().to_lower() if _book_search else ""
	var filter := _book_filter.get_item_text(_book_filter.selected) if _book_filter and _book_filter.item_count > 0 else "All cards"
	var effect_filter := _book_effect_filter.get_item_text(_book_effect_filter.selected) if _book_effect_filter and _book_effect_filter.item_count > 0 else "Any effect"
	var result: Array[CardData] = []
	for card in CardDatabase.cards.values():
		if query != "" and not (query in card.name.to_lower() or query in card.id.to_lower() or query in card.ability_text.to_lower()):
			continue
		if _book_active_faction != "All" and not (_book_active_faction in card.factions):
			continue
		if not _card_matches_filter(card, filter):
			continue
		if not _card_matches_effect_filter(card, effect_filter):
			continue
		result.append(card)
	_sort_book_cards(result)
	return result


func _sort_book_cards(cards: Array[CardData]) -> void:
	var mode := _book_sort.get_item_text(_book_sort.selected) if _book_sort and _book_sort.item_count > 0 else "Sort: Name"
	match mode:
		"Sort: Rarity":
			cards.sort_custom(func(a: CardData, b: CardData) -> bool:
				var ra := _rarity_rank(a.rarity)
				var rb := _rarity_rank(b.rarity)
				return ra < rb if ra != rb else a.name.naturalnocasecmp_to(b.name) < 0
			)
		"Sort: Type":
			cards.sort_custom(func(a: CardData, b: CardData) -> bool:
				return a.type.naturalnocasecmp_to(b.type) < 0 if a.type != b.type else a.name.naturalnocasecmp_to(b.name) < 0
			)
		"Sort: Faction":
			cards.sort_custom(func(a: CardData, b: CardData) -> bool:
				var fa: String = str(a.factions[0]) if not a.factions.is_empty() else ""
				var fb: String = str(b.factions[0]) if not b.factions.is_empty() else ""
				return fa.naturalnocasecmp_to(fb) < 0 if fa != fb else a.name.naturalnocasecmp_to(b.name) < 0
			)
		"Sort: Effects":
			cards.sort_custom(func(a: CardData, b: CardData) -> bool:
				return a.effects.size() < b.effects.size() if a.effects.size() != b.effects.size() else a.name.naturalnocasecmp_to(b.name) < 0
			)
		_:
			cards.sort_custom(func(a: CardData, b: CardData) -> bool:
				return a.name.naturalnocasecmp_to(b.name) < 0
			)


func _card_matches_filter(card: CardData, filter: String) -> bool:
	if filter == "All cards":
		return true
	if filter.begins_with("Rarity: "):
		return card.rarity == filter.trim_prefix("Rarity: ")
	if filter.begins_with("Type: "):
		return card.type == filter.trim_prefix("Type: ")
	if filter.begins_with("Faction: "):
		return filter.trim_prefix("Faction: ") in card.factions
	if filter.begins_with("Category: "):
		return filter.trim_prefix("Category: ") in card.categories
	return true


func _card_matches_effect_filter(card: CardData, filter: String) -> bool:
	if filter == "Any effect":
		return true
	for effect in card.effects:
		if filter.begins_with("Trigger: ") and effect.trigger == filter.trim_prefix("Trigger: "):
			return true
		if filter.begins_with("Effect: ") and effect.type == filter.trim_prefix("Effect: "):
			return true
		if filter.begins_with("Status: ") and effect.status == filter.trim_prefix("Status: "):
			return true
	return false


func _show_book_card(card: CardData) -> void:
	var factions := ", ".join(card.factions) if not card.factions.is_empty() else "None"
	var categories := ", ".join(card.categories) if not card.categories.is_empty() else "None"
	var lines: Array[String] = [
		"[font_size=24][color=%s]%s[/color][/font_size]" % [_rarity_color(card.rarity).to_html(false), card.name],
		"[color=9aa3b5]%s · %s · %s[/color]" % [card.type, card.rarity, factions],
		"Categories: %s" % categories,
	]
	if card.type in ["Unit", "Hero"]:
		lines.append("Power: %d" % card.base_power)
	if not card.effects.is_empty():
		lines.append("")
		lines.append("[b]Parsed Effects[/b]")
		for effect in card.effects:
			lines.append("- %s: %s" % [effect.trigger, effect.describe()])
	if card.ability_text != "":
		lines.append("")
		lines.append("[b]Ability[/b]")
		lines.append(CardDatabase.resolve_ability_text(card.ability_text))
	else:
		lines.append("")
		lines.append("No ability text.")
	_book_detail.text = "\n".join(lines)


func _build_rulebook() -> void:
	_rulebook_panel = PanelContainer.new()
	_rulebook_panel.name = "Rulebook"
	_rulebook_panel.visible = false
	_rulebook_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_rulebook_panel.set_anchors_preset(Control.PRESET_CENTER)
	_rulebook_panel.offset_left = -690.0
	_rulebook_panel.offset_top = -400.0
	_rulebook_panel.offset_right = 690.0
	_rulebook_panel.offset_bottom = 400.0
	add_child(_rulebook_panel)
	_rulebook_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.105, 0.115, 0.145), Color(0.55, 0.48, 0.26), 2))

	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 10)
	_rulebook_panel.add_child(root)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	root.add_child(header)
	var title := Label.new()
	title.text = "Rulebook"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.95, 0.84, 0.48))
	header.add_child(title)
	var close := _menu_button("Close", Vector2(96, 36))
	close.pressed.connect(func():
		_rulebook_panel.visible = false
	)
	header.add_child(close)

	_rulebook_tabs = TabContainer.new()
	_rulebook_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rulebook_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_rulebook_tabs.custom_minimum_size = Vector2(1340, 690)
	root.add_child(_rulebook_tabs)
	_rulebook_tabs.add_child(_rulebook_text_page("RULES", _rules_text()))
	_rulebook_tabs.add_child(_rulebook_text_page("KEYWORDS", _keywords_text()))
	_rulebook_tabs.add_child(_rulebook_text_page("STATUS EFFECTS", _statuses_text()))


func _open_rulebook() -> void:
	_rulebook_panel.visible = true
	_book_panel.visible = false
	_animate_panel_open(_rulebook_panel)


func _rulebook_text_page(title: String, text: String) -> Control:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var rich := RichTextLabel.new()
	rich.custom_minimum_size = Vector2(1280, 620)
	rich.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rich.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rich.bbcode_enabled = true
	rich.fit_content = false
	rich.scroll_active = true
	rich.add_theme_font_size_override("normal_font_size", 16)
	rich.add_theme_color_override("default_color", Color(0.88, 0.91, 0.96))
	rich.text = text
	scroll.add_child(rich)
	return scroll


func _rules_text() -> String:
	var r := CardDatabase.rules
	return "\n".join([
		"[font_size=22][b]Core Rules[/b][/font_size]",
		"Hero HP: %s" % r.get("hero_base_hp", 30),
		"Base sellary each turn: %s" % r.get("base_sellary_per_turn", 5),
		"Cards played per turn: %s" % r.get("max_cards_per_turn", 2),
		"Max hand size: %s" % r.get("max_hand_size", 10),
		"Neutral draw cost: %s, then +%s each draw" % [r.get("neutral_draw_base_cost", 3), r.get("neutral_draw_extra_cost", 1)],
		"Faction draw cost: %s, then +%s each draw" % [r.get("faction_draw_base_cost", 4), r.get("faction_draw_extra_cost", 1)],
		"Board rows: melee 5, ranged 5, artillery 3.",
		"Activation order: melee to artillery, left to right.",
		"",
		"[b]Turn Flow[/b]",
		"Sellary -> start-of-turn abilities -> play cards -> discard/draw cleanup -> end-of-turn abilities -> status triggers -> status diminish.",
		"",
		"[b]Setup[/b]",
		"Players roll d20. Higher roll is first player. Faction picking happens in reverse pick order, then the first player starts.",
	])


func _keywords_text() -> String:
	var lines: Array[String] = ["[font_size=22][b]Keywords[/b][/font_size]"]
	var entries: Array = CardDatabase.keywords.values()
	entries.sort_custom(func(a, b) -> bool:
		return str(a.get("name", "")).naturalnocasecmp_to(str(b.get("name", ""))) < 0
	)
	for keyword in entries:
		lines.append("")
		lines.append("[b]%s[/b]" % keyword.get("name", keyword.get("id", "")))
		lines.append(str(keyword.get("description", "No description.")))
	return "\n".join(lines)


func _statuses_text() -> String:
	var lines: Array[String] = ["[font_size=22][b]Status Effects[/b][/font_size]"]
	var entries: Array = CardDatabase.statuses.values()
	entries.sort_custom(func(a, b) -> bool:
		return str(a.get("name", "")).naturalnocasecmp_to(str(b.get("name", ""))) < 0
	)
	for status in entries:
		lines.append("")
		lines.append("[b]%s[/b]" % status.get("name", status.get("id", "")))
		lines.append(str(status.get("description", "No description.")))
	return "\n".join(lines)


func _collect_factions_from_cards() -> Array[String]:
	var result: Array[String] = []
	for card in CardDatabase.cards.values():
		for faction in card.factions:
			if faction not in result:
				result.append(faction)
	return result


func _collect_categories_from_cards() -> Array[String]:
	var result: Array[String] = []
	for category in CardDatabase.categories.values():
		var name := str(category.get("name", ""))
		if name != "" and name not in result:
			result.append(name)
	for card in CardDatabase.cards.values():
		for category in card.categories:
			if category not in result:
				result.append(category)
	return result


func _collect_effect_filters() -> Array[String]:
	var result: Array[String] = []
	for card in CardDatabase.cards.values():
		for effect in card.effects:
			var trigger := "Trigger: %s" % effect.trigger
			var effect_type := "Effect: %s" % effect.type
			if trigger not in result:
				result.append(trigger)
			if effect_type not in result:
				result.append(effect_type)
			if effect.status != "":
				var status := "Status: %s" % effect.status
				if status not in result:
					result.append(status)
	return result


func _sorted_strings(values: Array[String]) -> Array[String]:
	values.sort_custom(func(a: String, b: String) -> bool:
		return a.naturalnocasecmp_to(b) < 0
	)
	return values


func _panel_style(bg: Color, border: Color, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(6)
	style.content_margin_left = 14
	style.content_margin_top = 12
	style.content_margin_right = 14
	style.content_margin_bottom = 12
	return style


func _animate_panel_open(panel: Control) -> void:
	if not panel:
		return
	panel.pivot_offset = panel.size * 0.5
	panel.scale = Vector2(0.98, 0.98)
	panel.modulate.a = 0.0
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tween.tween_property(panel, "scale", Vector2.ONE, 0.12)
	tween.parallel().tween_property(panel, "modulate:a", 1.0, 0.12)


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
			return Color(0.72, 0.75, 0.82)


func _rarity_rank(rarity: String) -> int:
	match rarity:
		"Hero":
			return 0
		"Legendary":
			return 1
		"Epic":
			return 2
		"Rare":
			return 3
		"Common":
			return 4
		_:
			return 5


# ── Helpers ────────────────────────────────────────────────────────────────────

func _get_playable_factions() -> Array[String]:
	var result: Array[String] = []
	for f in CardDatabase.factions.values():
		if f.get("name", "") != "Neutral" and f.get("hero") != null:
			result.append(f["name"])
	return result
