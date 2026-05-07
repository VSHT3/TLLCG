extends SceneTree

const CardTestRunnerScript := preload("res://scripts/game/card_test_runner.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	var runner: RefCounted = CardTestRunnerScript.new()
	var report: Dictionary = runner.run_all()
	for line in report.get("lines", PackedStringArray()):
		print(line)
	quit(1 if int(report.get("failed", 0)) > 0 else 0)
