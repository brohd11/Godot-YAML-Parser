
# Test basic YAML parsing functionality
static func run() -> Dictionary:
	var out: Array[String] = []
	var test_count = 0
	var success_count = 0
	var f_tmp
	
	# Test 1: Simple key-value pairs
	f_tmp = FileAccess.open(
		"res://tests/yamls/basic/test_01.yaml",
		FileAccess.READ)
	var yaml1 = f_tmp.get_as_text()
	f_tmp.close()

	var expected1 = {
		"key1": "value1",
		"key2": 42,
		"key3": true
	}
	test_count += 1
	var result1 = YAMLTest.parse_data(yaml1)
	if result1.hash() == expected1.hash():
		success_count += 1
		out.append("Test 1: PASSED - Simple key-value pairs")
	else:
		out.append("Test 1: FAILED")
		out.append(str("Expected: ", expected1))
		out.append(str("Got: ", result1))
	
	# Test 2: Nested dictionaries
	f_tmp = FileAccess.open(
		"res://tests/yamls/basic/test_02.yaml",
		FileAccess.READ)
	var yaml2 = f_tmp.get_as_text()
	f_tmp.close()
	
	var expected2 = {
		"parent": {
			"child1": "value1",
			"child2": 3.14
		}
	}
	test_count += 1
	var result2 = YAMLTest.parse_data(yaml2)
	if result2.hash() == expected2.hash():
		success_count += 1
		out.append("Test 2: PASSED - Nested dictionaries")
	else:
		out.append("Test 2: FAILED")
		out.append(str("Expected: ", expected2))
		out.append(str("Got: ", result2))
	
	# Test 3: Simple lists
	f_tmp = FileAccess.open(
		"res://tests/yamls/basic/test_03.yaml",
		FileAccess.READ)
	var yaml3 = f_tmp.get_as_text()
	f_tmp.close()
	
	var expected3 = {
		"items": ["item1", 42, false]
	}
	test_count += 1
	var result3 = YAMLTest.parse_data(yaml3)
	if typeof(result3) == TYPE_DICTIONARY and result3.has("items") and typeof(result3["items"]) == TYPE_ARRAY:
		var items = result3["items"]
		if items.size() == 3 and items[0] == "item1" and items[1] == 42 and items[2] == false:
			success_count += 1
			out.append("Test 3: PASSED - Simple lists")
		else:
			out.append("Test 3: FAILED - Incorrect list content")
			out.append(str("Expected: ", expected3["items"]))
			out.append(str("Got: ", items))
	else:
		out.append("Test 3: FAILED - items is not a list")
		out.append(str("Got: ", result3))
	
	# Test 4: Mixed structures
	f_tmp = FileAccess.open(
		"res://tests/yamls/basic/test_04.yaml",
		FileAccess.READ)
	var yaml4 = f_tmp.get_as_text()
	f_tmp.close()
	
	var expected4 = {
		"config": {
			"title": "Game Settings",
			"values": [1, 2, 3],
			"enabled": true
		}
	}
	test_count += 1
	var result4 = YAMLTest.parse_data(yaml4)
	if result4.hash() == expected4.hash():
		success_count += 1
		out.append("Test 4: PASSED - Mixed structures")
	else:
		out.append("Test 4: FAILED")
		out.append(str("Expected: ", expected4))
		out.append(str("Got: ", result4))
	
	# Test 5: Empty values
	f_tmp = FileAccess.open(
		"res://tests/yamls/basic/test_05.yaml",
		FileAccess.READ)
	var yaml5 = f_tmp.get_as_text()
	f_tmp.close()
	
	var expected5 = {
		"key1": null,
		"key2": null,
		"key3": "value"
	}
	test_count += 1
	var result5 = YAMLTest.parse_data(yaml5)
	if typeof(result5) == TYPE_DICTIONARY and result5.has("key1") and result5["key1"] == null and result5.has("key2") and result5["key2"] == null and result5.get("key3") == "value":
		success_count += 1
		out.append("Test 5: PASSED - Empty values")
	else:
		out.append("Test 5: FAILED")
		out.append(str("Expected: ", expected5))
		out.append(str("Got: ", result5))
	
	out.append("Basic Tests: %d/%d passed" % [success_count, test_count])
	return {"success": success_count == test_count, "output": out}
