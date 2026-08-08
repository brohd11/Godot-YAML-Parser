extends YAMLTest

# Consistent with the parser's strict philosophy, a tag it cannot resolve, or one whose value
# has the wrong shape, is a parse error: `data` is null and the problem names its line.

func run() -> bool:
	var p = YAMLParser.new()

	# A tag that is neither built-in nor registered (e.g. a typo).
	_expect(p.parse("v: !Vetcor2 [1, 2]"), ERR_PARSE_ERROR, "unknown tag is an error")
	_expect(p.get_error_message().contains("unknown tag '!Vetcor2'"), true, "unknown tag message")
	_expect(p.data, null, "a failed parse yields no data")

	# A built-in whose value has the wrong arity.
	_expect(p.parse("v: !Vector2 [1]"), ERR_PARSE_ERROR, "wrong-arity vector is an error")
	_expect(p.get_error_message().contains("expects a sequence of 2 numbers"), true, "arity message")

	# Non-number elements.
	_expect(p.parse("v: !Vector2 [a, b]"), ERR_PARSE_ERROR, "non-number vector is an error")

	# A bad tag inside a flow collection is caught too, and names the flow's line.
	_expect(p.parse("v: [!Vector2 [1, 2, 3]]"), ERR_PARSE_ERROR, "bad tag in a flow is an error")

	# !!seq / !!map assert shape.
	_expect(p.parse("v: !!seq 5"), ERR_PARSE_ERROR, "!!seq on a scalar is an error")

	# A valid tagged document raises nothing.
	_expect(p.parse("v: !Vector2 [1, 2]"), OK, "a valid tag parses cleanly")
	_expect(p.errors.is_empty(), true, "a valid tag reports no errors")

	return passed()
