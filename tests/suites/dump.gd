@tool
extends EditorScript

func _run() -> void:
	print("\n".join(run()["output"]))

static func run() -> Dictionary:
	var out: Array[String] = []
	var all_passed = true
	var files_passed = test_files(out)
	if !files_passed:
		all_passed = false

	out.append("")
	out.append("--- Round Trip Stress Test ---")
	var stress_test_passed = stress_test(out)
	if !stress_test_passed:
		all_passed = false

	return {"success": all_passed, "output": out}


static func test_files(out: Array[String]):
	var files = [
		"res://tests/yamls/advanced/test_01.yaml",
		"res://tests/yamls/advanced/test_02.yaml",
		"res://tests/yamls/advanced/test_03.yaml",
		"res://tests/yamls/advanced/test_04.yaml",
		"res://tests/yamls/advanced/test_05.yaml",
		"res://tests/yamls/advanced/test_06.yaml",
		"res://tests/yamls/basic/test_01.yaml",
		"res://tests/yamls/basic/test_02.yaml",
		"res://tests/yamls/basic/test_03.yaml",
		"res://tests/yamls/basic/test_04.yaml",
		"res://tests/yamls/basic/test_05.yaml",
		"res://tests/yamls/multiline/test_01.yaml",
		"res://tests/yamls/multiline/test_02.yaml",
		"res://tests/yamls/multiline/test_03.yaml",
		"res://tests/yamls/multiline/test_04.yaml",
		"res://tests/yamls/multiline/test_05.yaml",
	]
	var all_passed = true
	for f in files:
		var passed = _test_dump_and_read(f, out)
		if not passed:
			all_passed = false

	return all_passed

static func _test_dump_and_read(file_path:String, out: Array[String], save_to_file:bool=false) -> bool:
	if not FileAccess.file_exists(file_path):
		return false
	
	var text = FileAccess.get_file_as_string(file_path)
	var file_data = YAMLTest.parse_data(text)
	
	var dumped = YAMLParser.dump(file_data)
	var reparsed_data = YAMLTest.parse_data(dumped)
	
	var passed = file_data == reparsed_data
	if passed:
		out.append(str("PASSED: ", file_path))
	else:
		out.append(str("FAILED: ", file_path))
		out.append("")
		out.append("--- Expected ---")
		out.append(str(file_data))
		out.append("")
		out.append("--- Parsed ---")
		out.append(str(reparsed_data))
	
	if not save_to_file:
		return passed
	
	var new_path = "res://.godot".path_join(file_path.get_base_dir().get_file()).path_join(file_path.get_file())
	DirAccess.make_dir_recursive_absolute(new_path.get_base_dir())
	var f = FileAccess.open(new_path, FileAccess.WRITE)
	f.store_string(dumped)
	
	return passed


static func stress_test(out: Array[String]) -> bool:
	var stress_test_data = get_yaml_stress_test()
	var yaml_dump = YAMLParser.dump(stress_test_data)
	
	var yaml_dump_parsed = YAMLTest.parse_data(yaml_dump)
	
	var passed = stress_test_data == yaml_dump_parsed
	if passed:
		out.append("PASSED")
	else:
		out.append("FAILED")
		out.append("")
		out.append("--- Expected ---")
		out.append(str(stress_test_data))
		out.append("")
		out.append("--- Parsed ---")
		out.append(str(yaml_dump_parsed))
	
	return passed

static func get_yaml_stress_test() -> Dictionary:
	return {
		# Basic Data Types
		"standard_string": "Hello World",
		"standard_int": 42,
		"standard_float": 3.14159,
		"standard_bool_true": true,
		"standard_bool_false": false,
		"standard_null": null,

		# String Coercion Traps (Strings that parsers often mistake for other types)
		"string_int": "42",
		"string_float": "3.14159",
		"string_bool_true": "true",
		"string_bool_false": "False",
		"string_null": "null",
		"string_yes": "yes",
		"string_no": "no",

		# Special Characters and Whitespace
		"empty_string": "",
		"leading_space": "  indented string",
		"trailing_space": "trailing string  ",
		"multiline_string": "Line 1\nLine 2\nLine 3",
		"quotes_inside": 'The user typed "Hello" and \\ or /',
		"comment_trap": "This string has a # character",
		"colon_trap": "This: has a colon",
		"yaml_anchors": "&anchor *alias",

		# Tricky Keys (Keys that need to be quoted)
		"key:with_colon": "value",
		" key_with_leading_space": "value",
		"true": "key is the string 'true'",
		"123": "key is the string '123'",

		# Empty Structures
		"empty_dict": {},
		"empty_array": [],

		# Nested Arrays
		"simple_array": [1, 2, 3],
		"mixed_array": [1, "two", 3.0, false, null, "42"],
		"array_of_arrays": [
			[1, 2],
			[],
			[3, 4]
		],

		# Nested Dictionaries
		"deeply_nested_dict": {
			"level_1": {
				"level_2": {
					"level_3": "bottom of the rabbit hole",
					"sibling_empty": {}
				}
			}
		},

		# Complex Mixing (Arrays of Dicts, Dicts in Arrays)
		"array_of_dicts": [
			{ "id": 1, "name": "Alice", "active": true },
			{},
			{ "id": 2, "name": "Bob", "active": false }
		],
		"dict_with_arrays_of_dicts": {
			"enemies": [
				{
					"type": "goblin",
					"loot": ["gold", "dagger", "null"]
				},
				{
					"type": "dragon",
					"loot": []
				}
			]
		}
	}
