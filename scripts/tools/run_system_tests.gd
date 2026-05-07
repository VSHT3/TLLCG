extends Node

var _tests_run := 0
var _tests_failed := 0
var _next_target: CardInstance = null
var _choice_accept := true
var _resolver: EffectResolver = null
var _event_bus: Node = null
var _constants: Node = null
var _audio_manager: Node = null


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	await get_tree().process_frame
	_event_bus = get_tree().root.get_node("EventBus")
	_constants = get_tree().root.get_node("GameConstants")
	_audio_manager = get_tree().root.get_node_or_null("AudioManager")
	if _audio_manager:
		_audio_manager.enabled = false
	_event_bus.target_requested.connect(_on_target_requested)
	_event_bus.choice_requested.connect(_on_choice_requested)
	_run_test("deploy_profit", _test_deploy_profit)
	_run_test("tribute_pay_profit", _test_tribute_pay_profit)
	_run_test("tribute_skip", _test_tribute_skip)
	_run_test("pay_cost", _test_pay_cost)
	_run_test("order_charges", _test_order_charges)
	_run_test("hoard_threshold", _test_hoard_threshold)
	_run_test("upkeep_income", _test_upkeep_income)
	_run_test("timer_end_turn", _test_timer_end_turn)
	_run_test("last_word_destroy", _test_last_word_destroy)
	_run_test("banish_no_last_word", _test_banish_no_last_word)
	_run_test("devour_target", _test_devour_target)
	_run_test("status_damage_and_diminish", _test_status_damage_and_diminish)
	_run_test("block_and_cleanse", _test_block_and_cleanse)
	_run_test("seize", _test_seize)
	_run_test("spot_67", _test_spot_67)
	_run_test("board_visual_instantiates_cards", _test_board_visual_instantiates_cards)
	_run_test("rulebook_has_content", _test_rulebook_has_content)
	_run_test("all_playable_cards_smoke", _test_all_playable_cards_smoke)
	_run_test("main_event_banner_queues", _test_main_event_banner_queues)
	_run_test("ability_panel_shows_items", _test_ability_panel_shows_items)
	print("System tests complete: %d run, %d failed." % [_tests_run, _tests_failed])
	if _resolver and is_instance_valid(_resolver):
		_resolver.queue_free()
		await get_tree().process_frame
	get_tree().quit(1 if _tests_failed > 0 else 0)


func _run_test(test_name: String, callback: Callable) -> void:
	_tests_run += 1
	_choice_accept = true
	_next_target = null
	var ok := bool(callback.call())
	if ok:
		print("PASS %s" % test_name)
	else:
		_tests_failed += 1
		print("FAIL %s" % test_name)


func _new_game() -> GameState:
	var gs := GameState.new()
	if not _resolver:
		_resolver = EffectResolver.new()
		get_tree().root.add_child(_resolver)
	_resolver.setup(gs)
	gs.setup_game(["Sir Can", "The Plague"], 0)
	for player in gs.players:
		player.hand.clear()
		player.board = [[], [], []]
		player.graveyard.clear()
		player.banished.clear()
		player.faction_deck.clear()
		player.sellary = 0
		if player.hero:
			player.hero.current_power = player.hero.data.base_power
			player.hero.zone = "board"
	gs.neutral_deck.clear()
	gs.current_player_idx = 0
	gs.turn_number = 1
	gs.current_phase = int(_constants.TurnPhase.PLAY_CARDS)
	gs.game_over = false
	return gs


func _card_data(id: String, type: String = "Unit", power: int = 3, effects: Array = []) -> CardData:
	var data := CardData.new()
	data.id = id
	data.name = id.capitalize()
	data.type = type
	data.rarity = "Common"
	data.factions = ["Neutral"]
	data.base_power = power
	data.has_ability = not effects.is_empty()
	data.ability_text = "test"
	data.effects = effects
	return data


func _effect(type: String, trigger: String, value: int = 0, opts: Dictionary = {}) -> CardEffect:
	var effect := CardEffect.new()
	effect.type = type
	effect.trigger = trigger
	effect.value = value
	effect.stacks = opts.get("stacks", 0)
	effect.timer_value = opts.get("timer_value", 0)
	effect.upkeep_cost = opts.get("upkeep_cost", 0)
	effect.tribute_cost = opts.get("tribute_cost", 0)
	effect.hoard_threshold = opts.get("hoard_threshold", 0)
	effect.pay_cost = opts.get("pay_cost", 0)
	effect.initial_charges = opts.get("initial_charges", 0)
	effect.charges = opts.get("charges", 0)
	effect.max_charges = opts.get("max_charges", 0)
	effect.status = opts.get("status", "")
	effect.permanent_status = opts.get("permanent_status", false)
	effect.target_scope = opts.get("target_scope", "self")
	effect.target_kind = opts.get("target_kind", "unit")
	effect.area = opts.get("area", false)
	effect.requires_target = opts.get("requires_target", false)
	return effect


func _hand(player: PlayerState, data: CardData) -> CardInstance:
	var card := CardInstance.create(data, player.player_id)
	player.add_to_hand(card)
	return card


func _board(player: PlayerState, data: CardData, row: int = 0, col: int = 0) -> CardInstance:
	var card := CardInstance.create(data, player.player_id)
	player.place_on_board(card, row, col)
	return card


func _test_deploy_profit() -> bool:
	var gs := _new_game()
	var player := gs.players[0]
	var card := _hand(player, _card_data("deploy_profit", "Unit", 3, [_effect("profit", "deploy", 3)]))
	return gs.play_card(player, card, 0, 0) and player.sellary == 3 and card.zone == "board"


func _test_tribute_pay_profit() -> bool:
	var gs := _new_game()
	var player := gs.players[0]
	player.sellary = 4
	_choice_accept = true
	var card := _hand(player, _card_data("tribute_profit", "Unit", 3, [_effect("profit", "tribute", 5, {"tribute_cost": 2})]))
	return gs.play_card(player, card, 0, 0) and player.sellary == 7


func _test_tribute_skip() -> bool:
	var gs := _new_game()
	var player := gs.players[0]
	player.sellary = 4
	_choice_accept = false
	var card := _hand(player, _card_data("tribute_skip", "Unit", 3, [_effect("profit", "tribute", 5, {"tribute_cost": 2})]))
	return gs.play_card(player, card, 0, 0) and player.sellary == 4


func _test_pay_cost() -> bool:
	var gs := _new_game()
	var player := gs.players[0]
	player.sellary = 5
	var card := _board(player, _card_data("pay_profit", "Unit", 3, [_effect("profit", "pay", 4, {"pay_cost": 2})]))
	return gs.activate_pay(card) and player.sellary == 7


func _test_order_charges() -> bool:
	var gs := _new_game()
	var player := gs.players[0]
	var card := _board(player, _card_data("order_profit", "Unit", 3, [_effect("profit", "order", 2, {"initial_charges": 2, "max_charges": 2, "charges": 1})]))
	return card.charges == 2 and gs.activate_order(card) and player.sellary == 2 and card.charges == 1 and not gs.activate_order(card)


func _test_hoard_threshold() -> bool:
	var gs := _new_game()
	var player := gs.players[0]
	player.sellary = 5
	var card := _board(player, _card_data("hoard_profit", "Unit", 3, [_effect("profit", "hoard", 2, {"hoard_threshold": 6})]))
	gs._trigger_hoard(player)
	if player.sellary != 5:
		return false
	player.sellary = 6
	gs._trigger_hoard(player)
	return player.sellary == 8 and card.zone == "board"


func _test_upkeep_income() -> bool:
	var gs := _new_game()
	var player := gs.players[0]
	player.sellary = 2
	_board(player, _card_data("upkeep_income", "Unit", 3, [_effect("income", "upkeep", 4, {"upkeep_cost": 2})]))
	gs._trigger_start_of_turn(player)
	return player.sellary == 4


func _test_timer_end_turn() -> bool:
	var gs := _new_game()
	var player := gs.players[0]
	var card := _board(player, _card_data("timer_profit", "Unit", 3, [_effect("profit", "timer", 3, {"timer_value": 1})]))
	gs._trigger_end_of_turn(player)
	return card.timer == 0 and player.sellary == 3


func _test_last_word_destroy() -> bool:
	var gs := _new_game()
	var player := gs.players[0]
	var card := _board(player, _card_data("last_word", "Unit", 1, [_effect("profit", "last_word", 3)]))
	gs._destroy_card(card, player)
	return player.sellary == 3 and card in player.graveyard


func _test_banish_no_last_word() -> bool:
	var gs := _new_game()
	var player := gs.players[0]
	var target := _board(player, _card_data("banish_target", "Unit", 1, [_effect("profit", "last_word", 3)]))
	var source := _board(player, _card_data("banisher", "Unit", 2, [_effect("banish", "deploy", 0, {"target_scope": "ally", "requires_target": true})]), 0, 1)
	_next_target = target
	_event_bus.ability_triggered.emit(source, source.data.effects[0])
	return player.sellary == 0 and target in player.banished and not (target in player.graveyard)


func _test_devour_target() -> bool:
	var gs := _new_game()
	var player := gs.players[0]
	var eater := _board(player, _card_data("eater", "Unit", 2, [_effect("devour", "order", 0)]))
	var food := _board(player, _card_data("food", "Unit", 4, []), 0, 1)
	_next_target = food
	_event_bus.ability_triggered.emit(eater, eater.data.effects[0])
	return eater.current_power == 6 and food in player.graveyard


func _test_status_damage_and_diminish() -> bool:
	var gs := _new_game()
	var player := gs.players[0]
	var card := _board(player, _card_data("status_target", "Unit", 5, []))
	card.apply_status("Poison", 2)
	gs._trigger_statuses(player)
	gs._diminish_statuses(player)
	return card.current_power == 3 and card.get_status_stacks("Poison") == 1


func _test_block_and_cleanse() -> bool:
	var gs := _new_game()
	var player := gs.players[0]
	var enemy := gs.players[1]
	var blocker := _board(player, _card_data("blocker", "Unit", 5, [_effect("block", "deploy", 2), _effect("cleanse", "order", 0, {"target_scope": "self"})]))
	var attacker := _board(enemy, _card_data("attacker", "Unit", 2, [_effect("damage", "deploy", 4, {"target_scope": "enemy", "requires_target": true})]))
	_event_bus.ability_triggered.emit(blocker, blocker.data.effects[0])
	blocker.apply_status("Burn", 1)
	_next_target = blocker
	_event_bus.ability_triggered.emit(attacker, attacker.data.effects[0])
	if blocker.current_power != 3:
		return false
	_event_bus.ability_triggered.emit(blocker, blocker.data.effects[1])
	return not blocker.has_status("Burn")


func _test_seize() -> bool:
	var gs := _new_game()
	var player := gs.players[0]
	var enemy := gs.players[1]
	player.sellary = 1
	enemy.sellary = 4
	var card := _board(player, _card_data("seizer", "Unit", 2, [_effect("seize", "deploy", 3, {"target_scope": "enemy"})]))
	_event_bus.ability_triggered.emit(card, card.data.effects[0])
	return player.sellary == 4 and enemy.sellary == 1


func _test_spot_67() -> bool:
	var gs := _new_game()
	var player := gs.players[0]
	var six := _board(player, _card_data("6", "Unit", 2, []), 0, 0)
	_board(player, _card_data("7", "Unit", 2, []), 0, 1)
	var spotter := _board(player, _card_data("spotter", "Artifact", 0, [_effect("profit", "spot_67", 3)]), 1, 0)
	gs._trigger_spot_67_all()
	return six.zone == "board" and spotter.zone == "board" and player.sellary == 3


func _test_board_visual_instantiates_cards() -> bool:
	var scene: PackedScene = load("res://scenes/card/card_visual.tscn")
	var board := BoardVisual.new()
	board.card_visual_scene = scene
	add_child(board)
	var player := PlayerState.create(0, "Sir Can")
	player.hand.clear()
	player.board = [[], [], []]
	_board(player, _card_data("visible_board_card", "Unit", 3, []), 0, 0)
	board.setup(player)
	var found := _count_card_visuals(board) > 0
	board.queue_free()
	return found


func _test_rulebook_has_content() -> bool:
	var scene: PackedScene = load("res://scenes/menus/main_menu.tscn")
	var menu: MainMenu = scene.instantiate()
	add_child(menu)
	await_frame_flush()
	menu._open_rulebook()
	var found_text := false
	for rich in _find_rich_text_labels(menu):
		if rich.text.length() > 40:
			found_text = true
			break
	menu.queue_free()
	return found_text


func _test_main_event_banner_queues() -> bool:
	_constants.set("pending_faction_choices", ["Sir Can", "The Plague"])
	_constants.set("first_player_id", 0)
	var scene: PackedScene = load("res://scenes/main/main.tscn")
	var main: Node = scene.instantiate()
	add_child(main)
	main.call("_queue_game_event", "Test Trigger", "Ability feedback visible", Color(0.95, 0.82, 0.35), 0.1)
	var panel: PanelContainer = main.get("event_panel")
	var title_label: Label = main.get("event_title_label")
	var ok := panel != null and title_label != null and (panel.visible or bool(main.get("event_showing"))) and title_label.text == "Test Trigger"
	main.queue_free()
	return ok


func _test_ability_panel_shows_items() -> bool:
	_constants.set("pending_faction_choices", ["Sir Can", "The Plague"])
	_constants.set("first_player_id", 0)
	var scene: PackedScene = load("res://scenes/main/main.tscn")
	var main: Node = scene.instantiate()
	add_child(main)
	var item := {"title": "Neutral Draw", "detail": "Top card revealed."}
	main.call("_show_ability_panel", "Inspect top 3", [item])
	var panel: PanelContainer = main.get("ability_panel")
	var title_label: Label = main.get("ability_title_label")
	var items: VBoxContainer = main.get("ability_items")
	var ok := panel != null and title_label != null and items != null and panel.visible and title_label.text == "Inspect top 3" and items.get_child_count() == 1
	main.queue_free()
	return ok


func await_frame_flush() -> void:
	pass


func _count_card_visuals(node: Node) -> int:
	var count := 0
	if node is CardVisual:
		count += 1
	for child in node.get_children():
		count += _count_card_visuals(child)
	return count


func _find_rich_text_labels(node: Node) -> Array[RichTextLabel]:
	var result: Array[RichTextLabel] = []
	if node is RichTextLabel:
		result.append(node)
	for child in node.get_children():
		result.append_array(_find_rich_text_labels(child))
	return result


func _test_all_playable_cards_smoke() -> bool:
	var failures: Array[String] = []
	var tested := 0
	for data in CardDatabase.cards.values():
		var card_data: CardData = data
		if card_data.type == "Hero":
			continue
		if not card_data.type in ["Unit", "Artifact", "Spell"]:
			failures.append("%s has unplayable type %s" % [card_data.id, card_data.type])
			continue
		var gs := _new_game()
		var player := gs.players[0]
		var enemy := gs.players[1]
		player.sellary = 50
		enemy.sellary = 50
		_board(player, _card_data("ally_dummy_%s" % card_data.id, "Unit", 8, []), 0, 0)
		_board(enemy, _card_data("enemy_dummy_%s" % card_data.id, "Unit", 8, []), 0, 0)
		gs.neutral_deck.append(CardInstance.create(_card_data("neutral_draw_%s" % card_data.id, "Unit", 1, []), -1))
		player.faction_deck.append(CardInstance.create(_card_data("faction_draw_%s" % card_data.id, "Unit", 1, []), player.player_id))
		var card := _hand(player, card_data)
		_choice_accept = true
		_next_target = null
		var played := false
		match card_data.type:
			"Unit", "Artifact":
				played = gs.play_card(player, card, 0, 1)
			"Spell":
				played = gs.play_card(player, card)
		if not played:
			failures.append("%s could not be played" % card_data.id)
		tested += 1
	if not failures.is_empty():
		for failure in failures.slice(0, 20):
			print("CARD SMOKE FAIL %s" % failure)
		if failures.size() > 20:
			print("CARD SMOKE FAIL ... %d more" % (failures.size() - 20))
		return false
	print("Card smoke tested %d non-hero cards." % tested)
	return true


func _on_target_requested(valid_targets: Array, callback: Callable) -> void:
	if _next_target and _next_target in valid_targets:
		callback.call(_next_target)
	elif not valid_targets.is_empty():
		callback.call(valid_targets[0])


func _on_choice_requested(_prompt: String, _options: Array, callback: Callable) -> void:
	if _options.is_empty():
		callback.call(_choice_accept)
		return
	var selected = _options[0]
	if not _choice_accept:
		for option in _options:
			var option_value = option.get("value", option) if option is Dictionary else option
			if option_value == false:
				selected = option
				break
	var value = selected.get("value", selected) if selected is Dictionary else selected
	callback.call(value)
