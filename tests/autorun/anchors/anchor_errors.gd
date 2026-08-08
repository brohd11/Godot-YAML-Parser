extends YAMLTest

# The error cases anchors introduce. Consistent with the parser's strict philosophy, an alias
# with no matching anchor is a parse error rather than a literal string, and a merge whose
# source is not a mapping is rejected. Each reports a line and leaves `data` null.

func run() -> bool:
	var p = YAMLParser.new()

	# An alias with no matching anchor.
	_expect(p.parse("a: *missing"), ERR_PARSE_ERROR, "unknown alias is an error")
	_expect(p.get_error_message().contains("unknown alias '*missing'"), true, "unknown alias message")
	_expect(p.data, null, "a failed parse yields no data")

	# An anchor with no name.
	_expect(p.parse("a: & 5"), ERR_PARSE_ERROR, "empty anchor name is an error")
	_expect(p.get_error_message().contains("anchor name expected"), true, "empty anchor message")

	# A merge whose source is a scalar.
	_expect(p.parse("m:\n  <<: 5"), ERR_PARSE_ERROR, "merging a scalar is an error")
	_expect(p.get_error_message().contains("expects a mapping"), true, "scalar-merge message")

	# A merge sequence with a non-mapping entry.
	_expect(p.parse("a: &a\n  k: 1\nm:\n  <<: [*a, 3]"), ERR_PARSE_ERROR,
		"a non-mapping merge-sequence entry is an error")
	_expect(p.get_error_message().contains("sequence entry is not a mapping"), true,
		"sequence-entry-merge message")

	# An unknown alias inside a flow collection is caught too.
	_expect(p.parse("v: [1, *nope]"), ERR_PARSE_ERROR, "unknown alias in a flow is an error")

	# A valid anchor/alias document raises nothing.
	_expect(p.parse("a: &x 1\nb: *x"), OK, "valid anchors parse cleanly")
	_expect(p.errors.is_empty(), true, "valid anchors report no errors")

	return passed()
