extends Node

signal settings_changed(key: String, value: Variant)

const SETTINGS_PATH := "user://settings.cfg"

const DEFAULTS := {
	"theme": "classic",
	"sound_enabled": true,
	"music_enabled": true,
	"music_volume": 0.42,
	"sfx_volume": 0.85,
	"action_log_enabled": true,
	"event_popups_enabled": true,
	"ability_popups_enabled": true,
	"debug_enabled": false,
	"reduced_motion": false,
	"board_intro_enabled": true,
}

const THEME_NAMES := ["classic", "ember", "midnight", "verdant"]
const THEME_LABELS := {
	"classic": "Classic Table",
	"ember": "Ember Hall",
	"midnight": "Midnight Blue",
	"verdant": "Verdant Felt",
}

var values: Dictionary = DEFAULTS.duplicate(true)


func _ready() -> void:
	load_settings()


func get_value(key: String, fallback: Variant = null) -> Variant:
	return values.get(key, fallback if fallback != null else DEFAULTS.get(key))


func set_value(key: String, value: Variant, save_now: bool = true) -> void:
	if not DEFAULTS.has(key):
		return
	if values.get(key) == value:
		return
	values[key] = value
	settings_changed.emit(key, value)
	if save_now:
		save_settings()


func toggle(key: String) -> bool:
	var next := not bool(get_value(key, false))
	set_value(key, next)
	return next


func load_settings() -> void:
	values = DEFAULTS.duplicate(true)
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	for key in DEFAULTS.keys():
		if cfg.has_section_key("settings", key):
			values[key] = cfg.get_value("settings", key, DEFAULTS[key])


func save_settings() -> void:
	var cfg := ConfigFile.new()
	for key in values.keys():
		cfg.set_value("settings", key, values[key])
	cfg.save(SETTINGS_PATH)


func theme_label(theme: String) -> String:
	return str(THEME_LABELS.get(theme, theme.capitalize()))


func color(role: String) -> Color:
	var theme := str(get_value("theme", "classic"))
	var palette := _palette(theme)
	return palette.get(role, _palette("classic").get(role, Color(0.1, 0.1, 0.12)))


func _palette(theme: String) -> Dictionary:
	match theme:
		"ember":
			return {
				"background": Color(0.052, 0.037, 0.033),
				"rail": Color(0.062, 0.044, 0.04),
				"panel": Color(0.105, 0.075, 0.064, 0.97),
				"panel_soft": Color(0.075, 0.055, 0.05, 0.88),
				"border": Color(0.44, 0.24, 0.16),
				"accent": Color(0.98, 0.58, 0.25),
				"text": Color(0.93, 0.89, 0.84),
				"muted": Color(0.7, 0.62, 0.58),
			}
		"midnight":
			return {
				"background": Color(0.027, 0.034, 0.054),
				"rail": Color(0.034, 0.043, 0.066),
				"panel": Color(0.06, 0.075, 0.115, 0.97),
				"panel_soft": Color(0.04, 0.052, 0.08, 0.88),
				"border": Color(0.18, 0.32, 0.56),
				"accent": Color(0.39, 0.63, 1.0),
				"text": Color(0.88, 0.92, 0.98),
				"muted": Color(0.58, 0.68, 0.82),
			}
		"verdant":
			return {
				"background": Color(0.028, 0.047, 0.039),
				"rail": Color(0.034, 0.058, 0.048),
				"panel": Color(0.055, 0.087, 0.073, 0.97),
				"panel_soft": Color(0.035, 0.065, 0.053, 0.88),
				"border": Color(0.2, 0.43, 0.32),
				"accent": Color(0.58, 0.86, 0.48),
				"text": Color(0.88, 0.94, 0.89),
				"muted": Color(0.62, 0.74, 0.65),
			}
		_:
			return {
				"background": Color(0.028, 0.034, 0.045),
				"rail": Color(0.034, 0.039, 0.052),
				"panel": Color(0.075, 0.085, 0.112, 0.97),
				"panel_soft": Color(0.045, 0.053, 0.068, 0.9),
				"border": Color(0.28, 0.31, 0.4),
				"accent": Color(0.95, 0.72, 0.28),
				"text": Color(0.86, 0.89, 0.95),
				"muted": Color(0.63, 0.68, 0.76),
			}
