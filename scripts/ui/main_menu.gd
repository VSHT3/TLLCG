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
	_factions = _get_playable_factions()
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

	pick_prompt.text = "Player %d — choose your faction:" % (current_picker + 1)

	# Clear old buttons
	for child in faction_grid.get_children():
		child.queue_free()

	var taken: Array[String] = []
	for c in _faction_choices:
		if c != "":
			taken.append(c)

	for faction in _factions:
		var btn := Button.new()
		btn.text = faction
		btn.custom_minimum_size = Vector2(220, 60)
		btn.disabled = faction in taken
		if faction in taken:
			btn.modulate = Color(0.4, 0.4, 0.4)
		btn.pressed.connect(_on_faction_chosen.bind(current_picker, faction))
		faction_grid.add_child(btn)


func _on_faction_chosen(player_id: int, faction: String) -> void:
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
	# Pass choices to the game scene via global or autoload
	GameConstants.pending_faction_choices = _faction_choices
	GameConstants.first_player_id = _first_picker
	get_tree().change_scene_to_file(GAME_SCENE)


# ── Helpers ────────────────────────────────────────────────────────────────────

func _get_playable_factions() -> Array[String]:
	var result: Array[String] = []
	for f in CardDatabase.factions.values():
		if f.get("name", "") != "Neutral" and f.get("hero") != null:
			result.append(f["name"])
	return result
