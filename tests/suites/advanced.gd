
# Test advanced YAML features
static func run() -> Dictionary:
	var out: Array[String] = []
	var test_count = 0
	var success_count = 0
	var f_tmp

	# Test 1: Complex nested structure
	f_tmp = FileAccess.open(
		"res://tests/yamls/advanced/test_01.yaml",
		FileAccess.READ)
	var yaml1 = f_tmp.get_as_text()
	f_tmp.close()

	var expected1 = {
		"player": {
			"name": "Hero",
			"stats": {
				"health": 100,
				"mana": 50
			},
			"inventory": [
				"sword",
				"shield",
				{
					"name": "Health Potion",
					"value": 25
				}
			]
		}
	}
	test_count += 1
	var result1 = YAMLTest.parse_data(yaml1)
	if result1 == expected1:
		success_count += 1
		out.append("Test 1: PASSED - Complex nested structure")
	else:
		out.append("Test 1: FAILED")
		out.append(str("Expected: ", expected1))
		out.append(str("Got: ", result1))

	# Test 2: Multiple levels of nesting
	f_tmp = FileAccess.open(
		"res://tests/yamls/advanced/test_02.yaml",
		FileAccess.READ)
	var yaml2 = f_tmp.get_as_text()
	f_tmp.close()

	var expected2 = {
		"level1": {
			"level2": {
				"level3": {
					"key": "value"
				},
				"list": ["item1", "item2"]
			}
		}
	}
	test_count += 1
	var result2 = YAMLTest.parse_data(yaml2)
	if result2 == expected2:
		success_count += 1
		out.append("Test 2: PASSED - Multiple levels of nesting")
	else:
		out.append("Test 2: FAILED")
		out.append(str("Expected: ", expected2))
		out.append(str("Got: ", result2))

	# Test 3: Mixed list types
	f_tmp = FileAccess.open(
		"res://tests/yamls/advanced/test_03.yaml",
		FileAccess.READ)
	var yaml3 = f_tmp.get_as_text()
	f_tmp.close()

	var expected3 = {
		"items": [
			"string",
			42,
			true,
			{"key": "value"},
			[1, 2, 3]
		]
	}
	test_count += 1
	var result3 = YAMLTest.parse_data(yaml3)
	if result3 == expected3:
		success_count += 1
		out.append("Test 3: PASSED - Mixed list types")
	else:
		out.append("Test 3: FAILED")
		out.append(str("Expected: ", expected3))
		out.append(str("Got: ", result3))

	# Test 4: Comments and empty lines
	f_tmp = FileAccess.open(
		"res://tests/yamls/advanced/test_04.yaml",
		FileAccess.READ)
	var yaml4 = f_tmp.get_as_text()
	f_tmp.close()
	
	var expected4 = {
		"config": {
			"resolution": "1920x1080",
			"volume": 80,
			"mute": false
		}
	}
	test_count += 1
	var result4 = YAMLTest.parse_data(yaml4)
	if result4 == expected4:
		success_count += 1
		out.append("Test 4: PASSED - Comments and empty lines")
	else:
		out.append("Test 4: FAILED")
		out.append(str("Expected: ", expected4))
		out.append(str("Got: ", result4))

	# Test 5: Colons in values
	f_tmp = FileAccess.open(
		"res://tests/yamls/advanced/test_05.yaml",
		FileAccess.READ)
	var yaml5 = f_tmp.get_as_text()
	f_tmp.close()
	
	var expected5 = {
		"url": "https://example.com",
		"time": "12:30:45"
	}
	test_count += 1
	var result5 = YAMLTest.parse_data(yaml5)
	if result5 == expected5:
		success_count += 1
		out.append("Test 5: PASSED")
	else:
		out.append("Test 5: FAILED")
		out.append(str("Expected: ", expected5))
		out.append(str("Got: ", result5))
	
	# Test 6: Inline comments and tricky strings
	f_tmp = FileAccess.open(
		"res://tests/yamls/advanced/test_06.yaml",
		FileAccess.READ)
	var yaml6 = f_tmp.get_as_text()
	f_tmp.close()
	
	var expected6 = {
		"tricky_string": "un ': \"terminated",
		"valid#:key": "aweird#string",
		"not_comment": " #string",
		"multi": "This is a multiline string.\n# This is NOT a comment."
	}
	test_count += 1
	var result6 = YAMLTest.parse_data(yaml6)
	if typeof(result6) == TYPE_DICTIONARY and result6 == expected6:
		success_count += 1
		out.append("Test 6: PASSED - Inline Comments and tricky strings")
	else:
		out.append("Test 6: FAILED")
		out.append(str("Expected: ", expected6))
		out.append(str("Got: ", result6))
	
	out.append("Advanced Tests: %d/%d passed" % [success_count, test_count])
	return {"success": success_count == test_count, "output": out}
