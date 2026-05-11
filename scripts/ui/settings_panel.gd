class_name SettingsPanel
extends Control

signal debug_visibility_requested(open: bool)

var include_gameplay_options := false
var panel: PanelContainer = null
var cog_button: Button = null
var track_label: Label = null
var jukebox_status_label: Label = null
var music_slider: HSlider = null
var sfx_slider: HSlider = null
var theme_select: OptionButton = null
var debug_check: CheckButton = null
var wave_bars: Array[ColorRect] = []
var theme_swatches: Array[ColorRect] = []
var _label_refresh_accum := 0.0


func build(cog_pos: Vector2, gameplay_options: bool) -> void:
	include_gameplay_options = gameplay_options
	cog_button = Button.new()
	cog_button.text = "⚙"
	cog_button.tooltip_text = "Settings"
	cog_button.offset_left = cog_pos.x
	cog_button.offset_top = cog_pos.y
	cog_button.offset_right = cog_pos.x + 48.0
	cog_button.offset_bottom = cog_pos.y + 40.0
	cog_button.add_theme_font_size_override("font_size", 18)
	cog_button.pressed.connect(_toggle_panel)
	add_child(cog_button)
	_style_button(cog_button)

	panel = PanelContainer.new()
	panel.name = "SettingsPanel"
	panel.visible = false
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.offset_left = cog_pos.x - 332.0
	panel.offset_top = cog_pos.y + 48.0
	panel.offset_right = cog_pos.x + 48.0
	panel.offset_bottom = cog_pos.y + (620.0 if gameplay_options else 456.0)
	panel.add_theme_stylebox_override("panel", _panel_style(SettingsManager.color("panel"), SettingsManager.color("border"), 1, 7))
	add_child(panel)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	panel.add_child(root)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	root.add_child(header)
	var title := Label.new()
	title.text = "Settings"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 19)
	title.add_theme_color_override("font_color", SettingsManager.color("accent"))
	header.add_child(title)
	var close := Button.new()
	close.text = "Close"
	close.custom_minimum_size = Vector2(78, 32)
	close.pressed.connect(func() -> void: panel.visible = false)
	header.add_child(close)
	_style_button(close)

	root.add_child(_section_label("Audio"))
	track_label = Label.new()
	track_label.text = "Now playing: %s" % AudioManager.current_track_label()
	track_label.add_theme_font_size_override("font_size", 12)
	track_label.add_theme_color_override("font_color", SettingsManager.color("muted"))
	root.add_child(track_label)
	jukebox_status_label = Label.new()
	jukebox_status_label.text = AudioManager.jukebox_status()
	jukebox_status_label.add_theme_font_size_override("font_size", 11)
	jukebox_status_label.add_theme_color_override("font_color", SettingsManager.color("accent"))
	root.add_child(jukebox_status_label)
	root.add_child(_wave_row())
	root.add_child(_toggle_row("Sound", "sound_enabled"))
	root.add_child(_toggle_row("Music", "music_enabled"))
	music_slider = _slider_row(root, "Music volume", "music_volume")
	sfx_slider = _slider_row(root, "Effects volume", "sfx_volume")
	var skip := Button.new()
	skip.text = "Skip Song"
	skip.custom_minimum_size = Vector2(0, 34)
	skip.pressed.connect(func() -> void:
		AudioManager.skip_gameplay_track()
		_refresh_from_settings()
	)
	root.add_child(skip)
	_style_button(skip)

	root.add_child(_section_label("Display"))
	theme_select = OptionButton.new()
	for theme in SettingsManager.THEME_NAMES:
		theme_select.add_item(SettingsManager.theme_label(theme))
		theme_select.set_item_metadata(theme_select.item_count - 1, theme)
	theme_select.item_selected.connect(func(idx: int) -> void:
		SettingsManager.set_value("theme", str(theme_select.get_item_metadata(idx)))
		_apply_theme()
	)
	root.add_child(_labeled_control("Color theme", theme_select))
	root.add_child(_theme_swatch_row())
	root.add_child(_toggle_row("Reduce motion", "reduced_motion"))
	if gameplay_options:
		root.add_child(_toggle_row("Action log", "action_log_enabled"))
		root.add_child(_toggle_row("Event popups", "event_popups_enabled"))
		root.add_child(_toggle_row("Ability popups", "ability_popups_enabled"))
		root.add_child(_toggle_row("Board intro", "board_intro_enabled"))
		debug_check = _toggle_row("Debug tools", "debug_enabled")
		root.add_child(debug_check)

	SettingsManager.settings_changed.connect(_on_setting_changed)
	AudioManager.track_changed.connect(_on_track_changed)
	_refresh_from_settings()
	set_process(true)


func _process(delta: float) -> void:
	if not panel or not panel.visible:
		return
	_label_refresh_accum += delta
	if _label_refresh_accum >= 0.25:
		_label_refresh_accum = 0.0
		if track_label:
			track_label.text = "Now playing: %s" % AudioManager.current_track_label()
		if jukebox_status_label:
			jukebox_status_label.text = "Jukebox: %s" % AudioManager.jukebox_status()
	var levels := AudioManager.get_spectrum_bands(wave_bars.size())
	var peak := 0.0
	var floor_level := 1.0
	for level in levels:
		var value := float(level)
		peak = maxf(peak, value)
		floor_level = minf(floor_level, value)
	if peak <= 0.01 or peak - floor_level <= 0.015:
		levels = AudioManager.synthetic_music_bands(wave_bars.size())
	var volume := float(SettingsManager.get_value("music_volume", 0.4))
	var active := bool(SettingsManager.get_value("sound_enabled", true)) and bool(SettingsManager.get_value("music_enabled", true))
	for i in range(wave_bars.size()):
		var bar := wave_bars[i]
		var target := 6.0
		if active and i < levels.size():
			target += 30.0 * float(levels[i]) * volume
		var current_height := bar.size.y if bar.size.y > 0.0 else 14.0
		var next_height := lerpf(current_height, target, clampf(delta * 18.0, 0.0, 1.0))
		bar.offset_top = 36.0 - next_height
		bar.offset_bottom = 36.0


func _toggle_panel() -> void:
	panel.visible = not panel.visible
	if panel.visible:
		_refresh_from_settings()


func _toggle_row(label_text: String, key: String) -> CheckButton:
	var row := CheckButton.new()
	row.text = label_text
	row.button_pressed = bool(SettingsManager.get_value(key, true))
	row.toggled.connect(func(on: bool) -> void:
		SettingsManager.set_value(key, on)
		if key == "debug_enabled":
			debug_visibility_requested.emit(on)
	)
	_style_check(row)
	return row


func _slider_row(parent: Control, label_text: String, key: String) -> HSlider:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var label := Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", SettingsManager.color("muted"))
	box.add_child(label)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = float(SettingsManager.get_value(key, 0.5))
	slider.value_changed.connect(func(value: float) -> void:
		SettingsManager.set_value(key, value)
	)
	box.add_child(slider)
	parent.add_child(box)
	return slider


func _labeled_control(label_text: String, control: Control) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	var label := Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", SettingsManager.color("muted"))
	box.add_child(label)
	box.add_child(control)
	return box


func _section_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", SettingsManager.color("accent"))
	return label


func _wave_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.custom_minimum_size = Vector2(0, 36)
	row.add_theme_constant_override("separation", 5)
	for i in range(18):
		var slot := Control.new()
		slot.custom_minimum_size = Vector2(4, 36)
		var bar := ColorRect.new()
		bar.color = SettingsManager.color("accent")
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.offset_left = 0.0
		bar.offset_right = 4.0
		bar.offset_top = 22.0
		bar.offset_bottom = 36.0
		slot.add_child(bar)
		row.add_child(slot)
		wave_bars.append(bar)
	return row


func _refresh_from_settings() -> void:
	if track_label:
		track_label.text = "Now playing: %s" % AudioManager.current_track_label()
	if jukebox_status_label:
		jukebox_status_label.text = "Jukebox: %s" % AudioManager.jukebox_status()
	if music_slider:
		music_slider.set_value_no_signal(float(SettingsManager.get_value("music_volume", 0.42)))
	if sfx_slider:
		sfx_slider.set_value_no_signal(float(SettingsManager.get_value("sfx_volume", 0.85)))
	if theme_select:
		var current := str(SettingsManager.get_value("theme", "classic"))
		for i in range(theme_select.item_count):
			if str(theme_select.get_item_metadata(i)) == current:
				theme_select.select(i)
				break
	_update_theme_swatches()


func _on_setting_changed(key: String, _value: Variant) -> void:
	if key == "theme":
		_apply_theme()
	_refresh_from_settings()


func _on_track_changed(_label: String) -> void:
	_refresh_from_settings()


func _apply_theme() -> void:
	if panel:
		panel.add_theme_stylebox_override("panel", _panel_style(SettingsManager.color("panel"), SettingsManager.color("border"), 1, 7))
	if track_label:
		track_label.add_theme_color_override("font_color", SettingsManager.color("muted"))
	if jukebox_status_label:
		jukebox_status_label.add_theme_color_override("font_color", SettingsManager.color("accent"))
	if cog_button:
		_style_button(cog_button)
	for bar in wave_bars:
		bar.color = SettingsManager.color("accent")
	_update_theme_swatches()


func _theme_swatch_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.custom_minimum_size = Vector2(0, 20)
	row.add_theme_constant_override("separation", 6)
	for i in range(6):
		var swatch := ColorRect.new()
		swatch.custom_minimum_size = Vector2(44, 12)
		row.add_child(swatch)
		theme_swatches.append(swatch)
	_update_theme_swatches()
	return row


func _update_theme_swatches() -> void:
	var roles := ["background", "rail", "panel", "panel_soft", "border", "accent"]
	for i in range(mini(theme_swatches.size(), roles.size())):
		theme_swatches[i].color = SettingsManager.color(roles[i])


func _style_button(button: Button) -> void:
	button.add_theme_stylebox_override("normal", _button_style(SettingsManager.color("panel_soft"), SettingsManager.color("border"), 1, 5))
	button.add_theme_stylebox_override("hover", _button_style(_hover_bg(), SettingsManager.color("accent"), 2, 5))
	button.add_theme_stylebox_override("pressed", _button_style(SettingsManager.color("accent").darkened(0.28), SettingsManager.color("accent").lightened(0.12), 2, 5))
	button.add_theme_stylebox_override("focus", _button_style(_hover_bg(), SettingsManager.color("accent"), 2, 5))
	button.add_theme_color_override("font_color", SettingsManager.color("text"))
	button.add_theme_color_override("font_hover_color", SettingsManager.color("text"))
	button.add_theme_color_override("font_pressed_color", SettingsManager.color("text"))
	button.add_theme_color_override("font_focus_color", SettingsManager.color("text"))
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


func _style_check(check: CheckButton) -> void:
	check.add_theme_color_override("font_color", SettingsManager.color("text"))
	check.add_theme_color_override("font_hover_color", SettingsManager.color("text"))
	check.add_theme_color_override("font_pressed_color", SettingsManager.color("text"))
	check.add_theme_color_override("font_focus_color", SettingsManager.color("text"))
	check.add_theme_font_size_override("font_size", 13)
	check.add_theme_stylebox_override("normal", _button_style(SettingsManager.color("panel_soft"), SettingsManager.color("border"), 1, 5))
	check.add_theme_stylebox_override("hover", _button_style(_hover_bg(), SettingsManager.color("accent"), 2, 5))
	check.add_theme_stylebox_override("pressed", _button_style(SettingsManager.color("accent").darkened(0.28), SettingsManager.color("accent").lightened(0.12), 2, 5))
	check.add_theme_stylebox_override("focus", _button_style(_hover_bg(), SettingsManager.color("accent"), 2, 5))
	_wire_button_motion(check)


func _panel_style(bg: Color, border: Color, border_width: int, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 12
	style.content_margin_top = 10
	style.content_margin_right = 12
	style.content_margin_bottom = 10
	return style


func _button_style(bg: Color, border: Color, border_width: int, radius: int) -> StyleBoxFlat:
	var style := _panel_style(bg, border, border_width, radius)
	style.shadow_size = 8 if border_width > 1 else 4
	style.shadow_color = Color(SettingsManager.color("accent"), 0.18 if border_width > 1 else 0.08)
	return style


func _hover_bg() -> Color:
	return SettingsManager.color("panel").lerp(SettingsManager.color("accent"), 0.18)
