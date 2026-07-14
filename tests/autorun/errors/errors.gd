extends YAMLTest

# Malformed YAML is an error, not something to paper over. parse() returns ERR_PARSE_ERROR,
# `data` is null, and `errors` lists everything wrong with the document -- not just the first
# thing, because a config with three typos should report three, not send you round twice.
#
# The bar these checks have to clear is not "catch every mistake" but "never cry wolf": a
# parser that rejects a valid config is worse than one that stays quiet. Every check here is
# measured against the full yaml-test-suite for false positives.

func run() -> bool:
	var p = YAMLParser.new()

	# A line of a mapping that is not an entry. This used to become a key with a null value.
	_expect(p.parse("a: 1\nb\n"), ERR_PARSE_ERROR, "missing colon is an error")
	_expect(p.data, null, "a failed parse yields no data")
	_expect(p.get_error_message().contains("expected 'key: value'"), true, "missing colon message")
	_expect(p.get_error_line(), 2, "missing colon line")

	# YAML forbids a duplicate key; a Dictionary would just overwrite the first.
	_expect(p.parse("a: 1\nb: 2\na: 3\n"), ERR_PARSE_ERROR, "duplicate key is an error")
	_expect(p.get_error_line(), 3, "duplicate key line")

	# An over-indented entry gets folded into the scalar above it. A plain scalar may not
	# contain ": " at all, so this is unambiguous.
	_expect(p.parse("a: 1\n  b: 2\n"), ERR_PARSE_ERROR, "mapping folded into a plain scalar")
	_expect(p.get_error_message().contains("folded into a plain scalar"), true, "fold message")

	_expect(p.parse("a: [1, 2]]\n"), ERR_PARSE_ERROR, "unmatched closing bracket")
	_expect(p.parse("a: [1,\n2\n"), ERR_PARSE_ERROR, "unterminated flow")
	_expect(p.parse('a: "x\n'), ERR_PARSE_ERROR, "unterminated quoted scalar")
	_expect(p.parse("a:\n\tb: 1\n"), ERR_PARSE_ERROR, "tab indentation")

	# Every error is reported, not only the first.
	p.parse("a: 1\nb\nc\n")
	_expect(p.errors.size(), 2, "all errors are collected")
	_expect(p.get_error_message(), p.errors[0], "get_error_message is the first error")

	# Line numbers survive document splitting -- they name the line in the FILE, not in the
	# chunk the splitter handed to the parser.
	p.parse_all("---\na: 1\n---\nb: 2\nc\n")
	_expect(p.get_error_line(), 5, "line numbers are file-relative across documents")

	# A clean parse says so, and leaves nothing behind.
	_expect(p.parse("a: 1\nb:\n  - x\n  - y\n"), OK, "valid YAML parses")
	_expect(p.errors.is_empty(), true, "valid YAML reports no errors")
	_expect(p.get_error_message(), "", "no message on success")
	_expect(p.get_error_line(), -1, "no line on success")

	# Things that merely LOOK wrong and are not. A stray bracket in a plain scalar opens
	# nothing; a colon with no space is part of the scalar; a tab may separate tokens.
	_expect(p.parse("note: TODO [wip\nb: 2\n"), OK, "a stray bracket is not an error")
	_expect(p.parse("url: http://example.com\n"), OK, "a colon inside a scalar is not an error")
	_expect(p.parse("foo:\tbar\n"), OK, "a tab between tokens is not an error")
	_expect(p.parse("a: |\n  x: not a mapping\n"), OK, "a block scalar's body is opaque")

	# The file entry points report a parse failure too, not only a missing file.
	var dir = "res://.godot/yaml_error_test"
	DirAccess.make_dir_recursive_absolute(dir)
	var path = dir.path_join("bad.yaml")
	var f = FileAccess.open(path, FileAccess.WRITE)
	f.store_string("a: 1\nb\n")
	f.close()
	_expect(p.parse_file(path), ERR_PARSE_ERROR, "parse_file reports a malformed file")
	_expect(p.data, null, "parse_file yields no data on a parse error")

	return passed()
