extends YAMLTest

# Directives ("%YAML 1.2", "%TAG ...") introduce a document. Nothing here resolves tags, so a
# directive has nothing to act on and is ignored -- but it must not survive into the document
# and be read as a scalar, which is what used to make "%YAML 1.2\n--- text" two documents.
#
# The catch is that "%" only opens a directive BEFORE the document's content. Further down it
# belongs to whatever is already open, and skipping it there would eat a line of the value.

func run() -> bool:
	var parser = YAMLParser.new()

	_expect(parse_data("%YAML 1.2\n--- text\n"), "text", "directive before the marker")
	_expect(parse_data("%FOO bar\n# comment\n---\nvalue\n"), "value",
			"a reserved directive, and a comment, are both ignored")

	parser.parse_all("%YAML 1.2\n---\na: 1\n")
	_expect(parser.data, [{"a": 1}], "a directive does not open a document of its own")

	# A directive may follow a document end and introduce the next document.
	parser.parse_all("one\n---\n# empty\n...\n%YAML 1.2\n---\ntwo\n")
	_expect(parser.data, ["one", null, "two"], "directive mid-stream")

	# ...but a "%" in column 0 with content already above it is content, not a directive.
	_expect(parse_data("---\nscalar\n%YAML 1.2\n"), "scalar %YAML 1.2",
			"a plain scalar may run on into a %-line")
	_expect(parse_data("|\n%not-a-directive\n"), "%not-a-directive\n",
			"a zero-indented block scalar may contain one")
	_expect(parse_data("--- { matches\n% : 20 }\n"), {"matches %": 20},
			"a multi-line flow may contain one")

	return passed()
