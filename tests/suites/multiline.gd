
# Test multiline YAML parsing
static func run() -> Dictionary:
	var out: Array[String] = []
	var test_count = 0
	var success_count = 0
	var f_tmp
	
	# Test 1: Literal block
	f_tmp = FileAccess.open(
		"res://tests/yamls/multiline/test_01.yaml",
		FileAccess.READ)
	var yaml1 = f_tmp.get_as_text()
	f_tmp.close()
	
	var expected1 = {
		"script": "function hello() {\n  print(\"Hello World!\");\n  print(\"Hello World!\");\n}\n"
	}
	test_count += 1
	var result1 = YAMLTest.parse_data(yaml1)
	if result1 == expected1:
		success_count += 1
		out.append("Test 1: PASSED - Literal block")
	else:
		out.append("Test 1: FAILED")
		out.append(str("Expected: ", expected1))
		out.append(str("Got: ", result1))
	
	# Test 2: Folded block
	f_tmp = FileAccess.open(
		"res://tests/yamls/multiline/test_02.yaml",
		FileAccess.READ)
	var yaml2 = f_tmp.get_as_text()
	f_tmp.close()
	
	var expected2 = {
		"description": "This is a long description that will be folded into a single paragraph.\n"
	}
	test_count += 1
	var result2 = YAMLTest.parse_data(yaml2)
	if result2 == expected2:
		success_count += 1
		out.append("Test 2: PASSED - Folded block")
	else:
		out.append("Test 2: FAILED")
		out.append(str("Expected: ", expected2))
		out.append(str("Got: ", result2))
		
	# Test 3: Strip chomping
	f_tmp = FileAccess.open(
		"res://tests/yamls/multiline/test_03.yaml",
		FileAccess.READ)
	var yaml3 = f_tmp.get_as_text()
	f_tmp.close()
	
	var expected3 = {
		"content": "No trailing newline"
	}
	test_count += 1
	var result3 = YAMLTest.parse_data(yaml3)
	if result3 == expected3:
		success_count += 1
		out.append("Test 3: PASSED - Strip chomping")
	else:
		out.append("Test 3: FAILED")
		out.append(str("Expected: ", expected3))
		out.append(str("Got: ", result3))
	
	# Test 4: Keep chomping
	f_tmp = FileAccess.open(
		"res://tests/yamls/multiline/test_04.yaml",
		FileAccess.READ)
	var yaml4 = f_tmp.get_as_text()
	f_tmp.close()
	
	var expected4 = {
		"content": "line 1\nline 2\n\n\n\n"
	}
	test_count += 1
	var result4 = YAMLTest.parse_data(yaml4)
	if result4 == expected4:
		success_count += 1
		out.append("Test 4: PASSED - Keep chomping")
	else:
		out.append("Test 4: FAILED")
		out.append(str("Expected: ", expected4))
		out.append(str("Got: ", result4))
	
	# Test 5: Quoted string
	f_tmp = FileAccess.open(
		"res://tests/yamls/multiline/test_05.yaml",
		FileAccess.READ)
	var yaml5 = f_tmp.get_as_text()
	f_tmp.close()
	
	var expected5 = {
		"message": "Line 1\nLine 2\tIndented"
	}
	test_count += 1
	var result5 = YAMLTest.parse_data(yaml5)
	if result5 == expected5:
		success_count += 1
		out.append("Test 5: PASSED - Quoted string")
	else:
		out.append("Test 5: FAILED")
		out.append(str("Expected: ", expected5))
		out.append(str("Got: ", result5))
	
	out.append("Multiline Tests: %d/%d passed" % [success_count, test_count])
	return {"success": success_count == test_count, "output": out}
