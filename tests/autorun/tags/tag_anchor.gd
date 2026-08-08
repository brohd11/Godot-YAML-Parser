extends YAMLTest

# A tag and an anchor are both node properties and may appear together, in either order. The tag
# constructs the value; the anchor then labels the CONSTRUCTED node, so an alias to it yields the
# same typed object.

func run() -> bool:
	# Anchor before tag.
	_expect(parse_data("a: &p !Vector2 [1, 2]\nb: *p"),
		{"a": Vector2(1, 2), "b": Vector2(1, 2)}, "&anchor !tag, then alias")

	# Tag before anchor.
	_expect(parse_data("a: !Vector2 &p [3, 4]\nb: *p"),
		{"a": Vector2(3, 4), "b": Vector2(3, 4)}, "!tag &anchor, then alias")

	# The alias shares the same constructed object.
	var p = YAMLParser.new()
	p.parse("a: &p !Vector2 [1, 2]\nb: *p")
	_expect(p.data["a"] == p.data["b"], true, "alias equals the constructed anchor value")

	# On a list item.
	_expect(parse_data("- &p !Color [1, 0, 0]\n- *p"),
		[Color(1, 0, 0), Color(1, 0, 0)], "&anchor !tag on a list item")

	# At the document root.
	_expect(parse_data("--- &p !Vector3 [1, 2, 3]"), Vector3(1, 2, 3), "tag+anchor at root")

	return passed()
