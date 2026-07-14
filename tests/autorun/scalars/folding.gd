extends YAMLTest

# Line-break folding. A plain scalar folds each break to a single space, but a run of N
# blank lines is N newlines -- that is how a plain scalar gets a paragraph break. Blank
# lines that trail the scalar belong to whatever structure follows it, so they are dropped.
#
# These all used to collapse to a single space, and a folded block scalar turned one blank
# line into two newlines (the fold emitted an empty line AND the join added a break).

func run() -> bool:
	# Plain scalar continuing an inline value, and the same scalar in block form.
	_expect(parse_data("plain: a\n b\n\n c\n"), {"plain": "a b\nc"},
			"blank line in an inline plain scalar")
	_expect(parse_data("plain:\n  a\n  b\n\n  c\n"), {"plain": "a b\nc"},
			"blank line in a block plain scalar")
	_expect(parse_data("plain: a\n\n\n b\n"), {"plain": "a\n\nb"},
			"two blank lines are two newlines")

	# A blank line before a shallower line ends the scalar rather than folding into it.
	_expect(parse_data("plain:\n  a\n  b\n\nnext: 1\n"), {"plain": "a b", "next": 1},
			"trailing blank line is not folded in")

	# Folded block scalar: one blank line is one newline, two are two.
	_expect(parse_data("key: >\n ab\n cd\n \n ef\n\n\n gh\n"), {"key": "ab cd\nef\n\ngh\n"},
			"blank lines in a folded block scalar")

	# A block scalar header may ride in on the document marker, in which case the scalar
	# is the whole document. This used to parse as the plain scalar "> ab cd".
	_expect(parse_data("--- >\n ab\n cd\n"), "ab cd\n", "folded block scalar as document root")
	_expect(parse_data("--- |\n ab\n cd\n"), "ab\ncd\n", "literal block scalar as document root")
	_expect(parse_data("--- |1-\n"), "", "empty block scalar as document root")

	# ...and it may be a sequence entry. A bare header holds no colon, so this used to fall
	# into the plain-scalar branch and fold the header in with its own content ("| x").
	_expect(parse_data("- |\n x\n- >\n y\n"), ["x\n", "y\n"], "block scalar as a sequence entry")
	_expect(parse_data("- |\n x\n-\n foo: bar\n"), ["x\n", {"foo": "bar"}],
			"block scalar beside other entry types")

	# Chomping. `keep` must preserve every trailing break -- the line count used to come up
	# one short, so the final newline went missing.
	_expect(parse_data("- |+\n\n\n"), ["\n\n"], "keep chomping preserves trailing breaks")
	_expect(parse_data("a: |-\n  x\n\n"), {"a": "x"}, "strip chomping")
	_expect(parse_data("a: |\n  x\n\n"), {"a": "x\n"}, "clip chomping")

	# Either order of indicators is legal. Chomping used to be read off the END of the
	# header, so "|-2" was mistaken for clip.
	_expect(parse_data("- |2-\n  a\n- |-2\n  b\n"), ["a", "b"], "indent/chomp indicator order")

	# A whitespace-only line is not empty: the spaces past the block's indent are content.
	_expect(parse_data("foo: |\n  x\n   \n"), {"foo": "x\n \n"}, "whitespace-only line keeps content")

	# ...but a line holding a TAB is not whitespace-only at all. The tab is content, and if it
	# comes first it is what establishes the block's indent.
	_expect(parse_data("foo: |\n \t\nbar: 1\n"), {"foo": "\t\n", "bar": 1}, "a tab is content")

	# In a folded scalar a MORE-INDENTED line is never folded: it stays literal, and the break
	# beside it stays a line feed. Without that, an indented block collapses into one line.
	_expect(parse_data(">\n a\n b\n\n   indented\n   lines\n\n c\n"),
			"a b\n\n  indented\n  lines\n\nc\n", "more-indented lines are not folded")

	# A block scalar at the document root may start its content in column 0 -- there is no
	# parent node to be more indented than.
	_expect(parse_data("--- >\nline1\nline2\n"), "line1 line2\n", "zero-indented folded scalar")
	_expect(parse_data("--- |\nline1\nline2\n"), "line1\nline2\n", "zero-indented literal scalar")

	return passed()
