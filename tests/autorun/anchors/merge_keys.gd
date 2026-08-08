extends YAMLTest

# A "<<" key merges one or more mappings into the current one. Precedence, per the YAML merge
# spec: a key written explicitly in the map always wins over a merged one (whichever came
# first in the text), and among several merged sources the earlier one wins. The "<<" key
# itself never survives into the result.

func run() -> bool:
	# Single merge; the explicit key overrides the merged one.
	_check("defaults: &d\n  a: 1\n  b: 2\nthing:\n  <<: *d\n  b: 20",
		{"defaults": {"a": 1, "b": 2}, "thing": {"a": 1, "b": 20}})

	# The explicit key wins even when it is written BEFORE the merge.
	_check("defaults: &d\n  a: 1\n  b: 2\nthing:\n  b: 20\n  <<: *d",
		{"defaults": {"a": 1, "b": 2}, "thing": {"b": 20, "a": 1}})

	# A sequence of merges: the earlier source wins on a conflict.
	_check("one: &o\n  a: 1\ntwo: &t\n  a: 99\n  c: 3\nm:\n  <<: [*o, *t]",
		{"one": {"a": 1}, "two": {"a": 99, "c": 3}, "m": {"a": 1, "c": 3}})

	# "<<" does not appear as a literal key in the result.
	var p = YAMLParser.new()
	p.parse("d: &d\n  a: 1\nm:\n  <<: *d")
	_expect(p.data["m"].has("<<"), false, "the merge key is not kept in the map")

	# An inline mapping may be merged directly, without an anchor.
	_check("m:\n  <<: {x: 1, y: 2}\n  y: 20",
		{"m": {"x": 1, "y": 20}})

	# A nested block mapping may be merged directly.
	_check("m:\n  <<:\n    x: 1\n    y: 2\n  z: 3",
		{"m": {"x": 1, "y": 2, "z": 3}})

	# Merge inside a list item, both from the inline pair and a following line.
	_check("base: &b\n  a: 1\nlist:\n  - <<: *b\n    b: 2",
		{"base": {"a": 1}, "list": [{"a": 1, "b": 2}]})

	# A quoted "<<" is an ordinary key, not a merge directive.
	_check("m:\n  \"<<\": literal", {"m": {"<<": "literal"}})

	return passed()
