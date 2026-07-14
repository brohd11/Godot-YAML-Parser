extends YAMLTest

# YAML permits a trailing comma in a flow collection -- the spec uses one in its own
# examples (7.13, 7.15). The empty segment it leaves behind is punctuation, not a node.
#
# This used to yield a trailing null, and the README defended that as spec-strict. It was
# not: no other parser does it, and the spec's own examples rely on the comma being allowed.

func run() -> bool:
	_check("a: [1, 2, ]\n", {"a": [1, 2]})
	_check("a: {x: 1, y: 2, }\n", {"a": {"x": 1, "y": 2}})
	_check("- [ one, two, ]\n- [three ,four]\n", [["one", "two"], ["three", "four"]])

	# An empty collection is still empty, and an interior gap is still a null -- only the
	# TRAILING comma is punctuation.
	_check("a: []\n", {"a": []})
	_check("a: [ ]\n", {"a": []})
	_expect(parse_data("a: [1, , 2]\n"), {"a": [1, null, 2]}, "interior gap stays null")

	return passed()
