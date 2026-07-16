extends SceneTree

const TestRun = preload("res://tests/main_test.gd")

func _init() -> void:
	var result = TestRun.run_tests()
	print("\n".join(result["output"]))
	quit(0 if result["success"] else 1)
