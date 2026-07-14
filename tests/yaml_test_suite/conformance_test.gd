extends SceneTree

## Entry point for the yaml-test-suite scoreboard. Unlike ci_test.gd this always exits 0:
## it reports where the parser stands, it does not gate anything.
##
##     godot --headless --script res://tests/yaml_test_suite/conformance_test.gd

const Conformance = preload("res://tests/yaml_test_suite/conformance.gd")

func _init() -> void:
	var result = Conformance.run()
	print("\n".join(result["output"]))
	quit(0)
