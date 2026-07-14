extends YAMLTest

# parse_file / parse_all_file (instance, return an Error and leave the result in `data`)
# and the static dump_to_file. The failure paths are asserted, not printed.

const DIR = "res://.godot/yaml_file_api_test"

func run() -> bool:
	DirAccess.make_dir_recursive_absolute(DIR)
	var path = DIR.path_join("round_trip.yaml")
	var parser = YAMLParser.new()

	var data = {
		"name": "test",
		"count": 3,
		"nested": {"a": [1, 2], "b": null},
		"items": [{"id": 1}, {"id": 2}],
	}

	_expect(YAMLParser.dump_to_file(data, path), OK, "dump_to_file")
	_expect(parser.parse_file(path), OK, "parse_file")
	_expect(parser.data, data, "parse_file data")

	# A file written with a document marker still reads back as one document.
	var multi = DIR.path_join("multi.yaml")
	var f = FileAccess.open(multi, FileAccess.WRITE)
	f.store_string("---\na: 1\n---\nb: 2\n")
	f.close()
	_expect(parser.parse_file(multi), OK, "parse_file first doc")
	_expect(parser.data, {"a": 1}, "parse_file first doc data")
	_expect(parser.parse_all_file(multi), OK, "parse_all_file")
	_expect(parser.data, [{"a": 1}, {"b": 2}], "parse_all_file data")

	# dump_to_file creates the directory it is given, however deep.
	var fresh = DIR.path_join("fresh/deeper/made_on_demand.yaml")
	_expect(YAMLParser.dump_to_file(data, fresh), OK, "dump_to_file creates missing dirs")
	_expect(FileAccess.file_exists(fresh), true, "dump_to_file wrote the file")
	_expect(parser.parse_file(fresh), OK, "created file reads back")
	_expect(parser.data, data, "created file round-trips")

	# A parent that is a file, not a directory: the directory cannot be created, so the
	# write must fail rather than crash.
	var blocker = DIR.path_join("blocker")
	var bf = FileAccess.open(blocker, FileAccess.WRITE)
	bf.store_string("i am a file, not a directory")
	bf.close()
	_expect(YAMLParser.dump_to_file(data, blocker.path_join("x.yaml")) != OK, true,
			"dump_to_file into a file-as-directory fails")

	# An unreadable path is reported through the Error, not the log.
	var missing = DIR.path_join("nope.yaml")
	_expect(parser.parse_file(missing), ERR_FILE_NOT_FOUND, "parse_file missing")
	_expect(parser.data, null, "parse_file missing yields no data")
	_expect(parser.get_error_message().contains("file not found"), true, "parse_file missing message")

	_expect(parser.parse_all_file(missing), ERR_FILE_NOT_FOUND, "parse_all_file missing")
	_expect(parser.data, [], "parse_all_file missing yields empty")

	# A successful call clears the previous failure.
	_expect(parser.parse_file(path), OK, "error state resets")
	_expect(parser.get_error_message(), "", "error message clears")

	return passed()
