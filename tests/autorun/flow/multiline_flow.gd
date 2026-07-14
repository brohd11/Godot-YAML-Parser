extends YAMLTest

# Multi-line flow collections: JSON-style [ ... ] / { ... } spanning lines.
# Every _check also asserts the dump round-trip.

func run() -> bool:
	_check(seq_value, seq_value_exp)
	_check(map_value, map_value_exp)
	_check(nested, nested_exp)
	_check(after_key, after_key_exp)
	_check(list_item, list_item_exp)
	_check(item_map_value, item_map_value_exp)
	_check(nested_dash, nested_dash_exp)
	_check(nested_dash_flat, nested_dash_flat_exp)
	_check(comment_bracket, comment_bracket_exp)
	_check(comments, comments_exp)
	_check(quoted, quoted_exp)
	_check(escaped, escaped_exp)
	_check(single_quoted, single_quoted_exp)
	_check(empty_flow, empty_flow_exp)

	# An unterminated flow used to be auto-closed with a warning. It is a syntax error: the
	# document does not say what it looks like it says, and guessing at the missing bracket
	# is worse than refusing it.
	var parser = YAMLParser.new()
	_expect(parser.parse(unterminated), ERR_PARSE_ERROR, "unterminated flow is an error")
	_expect(parser.data, null, "a failed parse yields no data")
	_expect(parser.get_error_message().contains("unterminated flow collection"), true,
			"unterminated flow error text")
	_expect(parser.get_error_line(), 1, "unterminated flow error line")

	# A plain scalar holding a stray bracket opens nothing, so it is not an error.
	_check(stray_bracket, stray_bracket_exp)
	_expect(last_errors.is_empty(), true, "a stray bracket in a plain scalar is not an error")
	_check(block_scalar_guard, block_scalar_guard_exp)
	_check(trailing_comma, trailing_comma_exp)
	_check(inline_hash, inline_hash_exp)

	# Flow as the whole document.
	_check("[\n  1,\n  2\n]\n", [1, 2])
	_check("[1, 2]", [1, 2])
	_check("{a: 1}", {"a": 1})
	_check("[]", [])
	_check("{}", {})

	return passed()


# A flow sequence as a map value. The closing bracket sits in column 0, so this
# also proves parsing resumes correctly on the sibling key below it.
var seq_value = """key: [
  1,
  2
]
other: x
"""
var seq_value_exp = {"key": [1, 2], "other": "x"}


var map_value = """key: {
  a: 1,
  b: two
}
"""
var map_value_exp = {"key": {"a": 1, "b": "two"}}


# Nesting broken across lines at arbitrary points.
var nested = """matrix: [
  [1, 2],
  [3,
   4],
  {a: [5]}
]
"""
var nested_exp = {"matrix": [[1, 2], [3, 4], {"a": [5]}]}


# Flow on the line after a bare "key:" (reaches _parse_block via
# _parse_value_after_key).
var after_key = """key:
  [1,
   2]
"""
var after_key_exp = {"key": [1, 2]}


var list_item = """- [
  1,
  2
]
- x
"""
var list_item_exp = [[1, 2], "x"]


# The flow is a list item's first value, so _merge_item_keys must resume below it.
var item_map_value = """- name: a
  vals: [
    1,
    2
  ]
  after: z
- name: b
"""
var item_map_value_exp = [{"name": "a", "vals": [1, 2], "after": "z"}, {"name": "b"}]


# "- - [" builds a synthetic sub-document by indent.
var nested_dash = """key:
  - - [
      1,
      2
    ]
"""
var nested_dash_exp = {"key": [[[1, 2]]]}


# The same, but with the closer in column 0. Indent alone would end the synthetic
# sub-document mid-flow and leave the stray "]" to be read as a key.
var nested_dash_flat = """key:
  - - [
  1,
  2
]
other: x
"""
var nested_dash_flat_exp = {"key": [[[1, 2]]], "other": "x"}


# A bracket inside a whole-line comment is not a bracket. If it were fed to the
# scanner it would open a depth that never closes, and the indent break that ends
# this item would never fire.
var comment_bracket = """key:
  - - a
    # note [wip
  - b
other: x
"""
var comment_bracket_exp = {"key": [["a"], "b"], "other": "x"}


# Comment after the opening bracket, per-line comment, blank line, full-line
# comment, and a comment after the closer.
var comments = """a: [ # start
  1, # one

  # a note
  2
] # done
b: 2
"""
var comments_exp = {"a": [1, 2], "b": 2}


# Quotes beat brackets, commas and hashes, across lines.
var quoted = """a: [
  "] not a closer",
  "x # y",
  "a, b",
  "k: v"
]
"""
var quoted_exp = {"a": ["] not a closer", "x # y", "a, b", "k: v"]}


# Backslash-escaped quote: the old scanner closed the string early here and split
# on the comma that is really inside the string. One item, not two.
var escaped = 'a: ["x\\", 1"]'
var escaped_exp = {"a": ["x\", 1"]}


# '' is an escaped single quote, so the colon stays inside the string.
var single_quoted = "a: ['it''s: fine']"
var single_quoted_exp = {"a": ["it's: fine"]}


var empty_flow = """a: [
]
b: {
}
"""
var empty_flow_exp = {"a": [], "b": {}}


# Unterminated at EOF. The error is reported at the OPENING bracket -- line 1, where the
# mistake is -- not at the end of the file, where the parser happened to notice.
var unterminated = """a: [1,
2
"""


# A plain scalar holding a stray bracket must NOT start consuming lines.
var stray_bracket = """note: TODO [wip
b: 2
"""
var stray_bracket_exp = {"note": "TODO [wip", "b": 2}


# A block scalar's body is opaque text; a bracket in it opens nothing.
var block_scalar_guard = """a: |
  [not a flow
b: [1]
"""
var block_scalar_guard_exp = {"a": "[not a flow\n", "b": [1]}


# YAML permits a trailing comma in a flow collection -- the spec uses one in its own
# examples (7.13, 7.15) -- so the empty segment is punctuation, not a null element. This
# used to expect [1, 2, null], which matched neither the spec nor any other parser.
var trailing_comma = """a: [
  1,
  2,
]
"""
var trailing_comma_exp = {"a": [1, 2]}


# A hash inside a flow that closes on its own line keeps its existing meaning.
var inline_hash = """a: [x #y]
"""
var inline_hash_exp = {"a": ["x #y"]}
