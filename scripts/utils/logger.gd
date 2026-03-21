## GameLogger
## Simple logging utility with levels and optional file output.
## Renamed from Logger to avoid conflict with Godot 4.6+ native Logger class.
class_name GameLogger
extends RefCounted

enum Level { DEBUG, INFO, WARN, ERROR }

static var log_level: int = Level.DEBUG
static var log_to_file: bool = false
static var log_file_path: String = "user://game.log"


static func debug(msg: String, context: String = "") -> void:
	_log(Level.DEBUG, msg, context)

static func info(msg: String, context: String = "") -> void:
	_log(Level.INFO, msg, context)

static func warn(msg: String, context: String = "") -> void:
	_log(Level.WARN, msg, context)

static func error(msg: String, context: String = "") -> void:
	_log(Level.ERROR, msg, context)


static func _log(level: int, msg: String, context: String) -> void:
	if level < log_level:
		return
	
	var level_names: Array[String] = ["DBG", "INF", "WRN", "ERR"]
	var prefix: String = level_names[level]
	var ctx: String = "[%s] " % context if context else ""
	var full_msg: String = "[%s] %s%s" % [prefix, ctx, msg]
	
	match level:
		Level.DEBUG:
			print(full_msg)
		Level.INFO:
			print(full_msg)
		Level.WARN:
			push_warning(full_msg)
		Level.ERROR:
			push_error(full_msg)
	
	if log_to_file:
		var file := FileAccess.open(log_file_path, FileAccess.WRITE)
		if file:
			file.store_string(full_msg + "\n")
			file.close()
