extends YAMLTest

# Two rules that the parser used to get wrong in ways the docs had enshrined:
#
#   * A tab is legal whitespace BETWEEN tokens. Only tab INDENTATION is illegal.
#     "foo:\tbar" is a perfectly ordinary mapping.
#   * A double-quoted scalar carries the full YAML escape set, not just \n \t \r \\ \" \'.

func run() -> bool:
	# Tab as a separator, everywhere a space would do.
	_expect(parse_data("foo:\tbar\n"), {"foo": "bar"}, "tab between key and value")
	_expect(parse_data("-\t1\n-\t2\n"), [1, 2], "tab after a dash")
	_expect(parse_data("a: b\t\n"), {"a": "b"}, "trailing tab after a value")
	_expect(parse_data("c: d\t#X\n"), {"c": "d"}, "tab before an inline comment")
	_expect(parse_data("---\tscalar\n"), "scalar", "tab after the document marker")

	# A tab is only a problem when it INDENTS a mapping key or a sequence entry -- there its
	# column is the nesting, and a tab makes the line read as if it sat further left than it
	# does. That is now an error, not a repair.
	var parser = YAMLParser.new()
	_expect(parser.parse("a:\n\tb: 1\n"), ERR_PARSE_ERROR, "tab indentation is an error")
	_expect(parser.get_error_message().contains("tab used for indentation"), true,
			"tab indentation error text")

	# ...but a tab that merely SEPARATES is fine, and none of these may be flagged.
	_expect(parser.parse("\t{}\n"), OK, "tab before a flow node is separation")
	_expect(parser.parse("key:\n \tvalue\n"), OK, "tab before a scalar value is separation")

	# Escapes. \u and \x carry a codepoint; the rest are single characters.
	_expect(parse_data('a: "\\u263A"\n'), {"a": "☺"}, "unicode escape")
	_expect(parse_data('a: "\\x0d\\x0a"\n'), {"a": "\r\n"}, "hex escape")
	_expect(parse_data('a: "x\\by"\n'), {"a": "x" + char(0x08) + "y"}, "backspace escape")
	_expect(parse_data('a: "a\\/b"\n'), {"a": "a/b"}, "escaped slash")
	# A malformed escape is recovered rather than rejected. It garbles one scalar; it does not
	# change what the document's STRUCTURE says, which is the line the errors are drawn at.
	_expect(parse_data('a: "\\uZZZZ"\n'), {"a": "uZZZZ"}, "malformed unicode escape survives")

	return passed()
