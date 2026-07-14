## Test entry point for YAML Parser.
##
## CI:      godot --headless --script res://tests/ci_test.gd
## Console: test --add res://tests/test_run.gd   (once)
##          test run --verbose

const SUITES: Array[String] = [
	"res://tests/suites/basic.gd",
	"res://tests/suites/advanced.gd",
	"res://tests/suites/multiline.gd",
	"res://tests/suites/dump.gd",
	]
const AUTORUN_DIR := "res://tests/autorun/"


static func run_tests() -> Dictionary:
	var output: Array[String] = []
	var all_passed := true

	output.append("YAML Parser Tests")
	for path in SUITES:
		output.append("")
		output.append(" --- Running Test: %s ---" % path.get_file())
		var script = load(path)
		var result = script.run()
		output.append_array(result["output"])
		if not result["success"]:
			all_passed = false

	output.append("")
	output.append("--- Autorun tests ---")
	for path in _get_files_in_dir(AUTORUN_DIR):
		var script = load(path)
		var base_script = script.get_base_script()
		if not is_instance_valid(base_script) or base_script != YAMLTest:
			output.append("Not a YAMLTest: %s" % path)
			continue
		var test = script.new()
		output.append("")
		output.append("Run: %s" % test.get_test_name())
		var passed = test.run()
		output.append_array(test.output)
		if passed:
			output.append("✅ PASSED")
		else:
			all_passed = false
			output.append("❌ FAILED")

	output.append("")
	if all_passed:
		output.append("✅ ALL TESTS PASSED")
	else:
		output.append("❌ SOME TESTS FAILED")

	return {"success": all_passed, "output": output}


static func _get_files_in_dir(dir:String):
	var files = []
	var dir_access = DirAccess.open(dir)
	for f in dir_access.get_files():
		var path = dir.path_join(f)
		if f.get_extension() == "gd":
			files.append(path)

	for d in dir_access.get_directories():
		var path = dir.path_join(d)
		files.append_array(_get_files_in_dir(path))

	return files
