extends YAMLTest

# A STRING that merely contains "!" must still survive a dump round-trip: dump quotes it (its
# special_chars list includes "!"), and on reparse a leading quote stops the tag machinery from
# firing. Detection fires only on an UNQUOTED leading "!", so these stay literal strings.

func run() -> bool:
	# A value that looks like a tagged node, but quoted, is an ordinary string.
	_check('v: "!Vector2 [1, 2]"', {"v": "!Vector2 [1, 2]"})

	# A leading "!" in a plain-looking string, quoted, does not become a tag.
	_check('shell: "!important"', {"shell": "!important"})

	# In-memory data with a "!" string round-trips through dump.
	var data = {"note": "use !force", "cmd": "!!bang"}
	_expect(YAMLTest.parse_data(YAMLParser.dump(data)), data, "'!' strings round-trip through dump")

	return passed()
