extends YAMLTest

# An entry in a flow sequence may itself be a single "key: value" pair, which YAML reads as a
# one-entry mapping: "[foo: bar]" is a sequence holding {foo: bar}, not the scalar "foo: bar".
#
# The guard that matters is what does NOT become a pair. A colon only separates when whitespace
# follows it -- otherwise every URL in a flow list would turn into a mapping.

func run() -> bool:
	_expect(parse_data("a: [foo: bar]\n"), {"a": [{"foo": "bar"}]}, "single pair in a flow sequence")
	_expect(parse_data("a: [x, foo: bar, y]\n"), {"a": ["x", {"foo": "bar"}, "y"]},
			"a pair beside plain entries")
	_expect(parse_data("a: [\n  foo: bar\n]\n"), {"a": [{"foo": "bar"}]}, "across lines")
	_expect(parse_data("a: ['q k' : v]\n"), {"a": [{"q k": "v"}]}, "quoted key, spaced colon")

	# A colon with no whitespace after it does not separate: these stay scalars.
	_expect(parse_data("a: [http://example.com]\n"), {"a": ["http://example.com"]},
			"a URL is not a single pair")
	_expect(parse_data('a: ["k: v"]\n'), {"a": ["k: v"]}, "a colon inside quotes is not a separator")
	_expect(parse_data("a: [x:y]\n"), {"a": ["x:y"]}, "no space after the colon")

	# Nested collections still parse as themselves.
	_expect(parse_data("a: [[1, 2], {b: c}]\n"), {"a": [[1, 2], {"b": "c"}]}, "nested flow entries")

	return passed()
