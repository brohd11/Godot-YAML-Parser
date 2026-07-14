extends YAMLTest

# Explicit mapping entries: "? key" on one line, an optional ": value" on a later one.
#
# Both markers introduce a node that begins part way along the line, at its own column, so
# each is rebuilt as a sub-document and handed back to the ordinary block parser -- the same
# trick "- - x" already uses. A compact sequence after the colon then needs no special case.

func run() -> bool:
	_expect(parse_data("? a\n: 1\n"), {"a": 1}, "explicit key and value")
	_expect(parse_data("? a\n"), {"a": null}, "explicit key with no value")
	_expect(parse_data("? a\n? b\nc:\n"), {"a": null, "b": null, "c": null},
			"explicit keys mixed with an implicit one")
	_expect(parse_data("a: 4.2\n? d\n: 23\n"), {"a": 4.2, "d": 23}, "implicit then explicit")

	# A comment may sit between the key and its value.
	_expect(parse_data("? key\n# comment\n: value\n"), {"key": "value"}, "comment between ? and :")

	# The value may be a compact sequence that starts on the ":" line itself.
	_expect(parse_data("? a\n: - one\n  - two\n"), {"a": ["one", "two"]}, "compact sequence value")

	# A block scalar may be the key. Its content is measured from the ENTRY, not from the
	# header's own column -- both sit at column 2 here.
	_expect(parse_data("? |\n  block key\n: v\n"), {"block key\n": "v"}, "block scalar as the key")

	# Key and value may each run across lines.
	_expect(parse_data("? a\n  true\n: null\n  d\n"), {"a true": "null d"}, "multi-line key and value")

	# Nested inside a mapping, at depth.
	_expect(parse_data("m:\n  ? sky\n  : blue\n  sea: green\n"),
			{"m": {"sky": "blue", "sea": "green"}}, "explicit entry nested in a mapping")

	# "?foo" is an ordinary key that merely starts with a question mark -- the space is what
	# makes the marker.
	_expect(parse_data("?foo: bar\n"), {"?foo": "bar"}, "?foo is not an explicit key")

	return passed()
