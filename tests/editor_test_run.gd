@tool
extends EditorScript

const TestRun = preload("res://tests/main_test.gd")

func _run() -> void:
	print("\n".join(TestRun.run_tests()["output"]))
