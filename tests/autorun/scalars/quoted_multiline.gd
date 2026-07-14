extends YAMLTest

# A quoted scalar may span lines with no flow collection around it. Its breaks fold like a
# plain scalar's -- one break is a space, N blank lines are N newlines -- and the whitespace
# around each break is not content.
#
# The sharp edge: whitespace an ESCAPE produced is content, but whitespace the source line
# merely ended with is not. "a\t  \n b" keeps the escaped tab and drops the two spaces.

func run() -> bool:
	_expect(parse_data('a: "one\n  two"\n'), {"a": "one two"}, "break folds to a space")
	_expect(parse_data("a: 'one\n  two'\n"), {"a": "one two"}, "single quotes fold too")
	_expect(parse_data('a: "one\n\n  two"\n'), {"a": "one\ntwo"}, "a blank line is a newline")

	# Leading whitespace on the continuation and trailing whitespace before the break both go.
	_expect(parse_data('a: "one   \n     two"\n'), {"a": "one two"}, "whitespace around the break")

	# An escaped tab survives; the literal spaces after it do not.
	_expect(parse_data('a: "one\\t  \n  two"\n'), {"a": "one\t two"}, "escaped tab outlives literal spaces")

	# A backslash before the break escapes it: no fold, no space.
	_expect(parse_data('a: "one\\\n  two"\n'), {"a": "onetwo"}, "backslash escapes the break")

	# Whitespace before the CLOSING quote never met a break, so it stays.
	_expect(parse_data('a: "one\n  two  "\n'), {"a": "one two  "}, "trailing space before the quote stays")

	# A whole document, and a value under a bare key, are both quoted-scalar positions.
	_expect(parse_data('"one\ntwo"\n'), "one two", "quoted scalar as the document")
	_expect(parse_data('a:\n  "one\n  two"\n'), {"a": "one two"}, "quoted scalar as a block value")

	# The comment after the closing quote is not swallowed into the scalar.
	_expect(parse_data('a: "one\n  two" # note\nb: 1\n'), {"a": "one two", "b": 1},
			"comment after the closing quote")

	return passed()
