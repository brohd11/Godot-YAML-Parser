extends YAMLTest

# Now that "&", "*" and "<<" are meaningful, a STRING that merely contains them must still
# survive a dump round-trip: dump quotes such strings, and on reparse a leading quote stops
# the anchor/alias/merge machinery from firing. A naive implementation that stripped "&"/"*"
# before the quote check, or matched a quoted "<<" as a merge key, would break these.

func run() -> bool:
	# A string value that looks like an anchor-and-alias pair stays that literal string.
	_check("v: \"&anchor *alias\"", {"v": "&anchor *alias"})

	# A quoted "<<" is an ordinary key and round-trips as one.
	_check("m:\n  \"<<\": kept", {"m": {"<<": "kept"}})

	# A leading "*" in a string is quoted on dump, so it does not read back as an alias.
	_check("pattern: \"*.txt\"", {"pattern": "*.txt"})

	# Round-trip a structure built in memory (not from parsing) that contains these chars.
	var data = {"note": "see &ref", "glob": "*", "<<": "literal"}
	var reparsed = YAMLTest.parse_data(YAMLParser.dump(data))
	_expect(reparsed, data, "in-memory data with &/*/<< round-trips through dump")

	return passed()
