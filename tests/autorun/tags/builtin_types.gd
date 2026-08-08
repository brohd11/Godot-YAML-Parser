extends YAMLTest

# A tag (!Vector2, !Color, ...) constructs a typed value from the parsed node. `dump` does not
# emit tags, so these do NOT round-trip -- they assert with _expect(parse_data(...)), never
# _check (which would fail on the dump round-trip).

func run() -> bool:
	# Vectors, in a mapping value.
	_expect(parse_data("pos: !Vector2 [1, 2]"), {"pos": Vector2(1, 2)}, "Vector2")
	_expect(parse_data("v: !Vector2i [4, 5]"), {"v": Vector2i(4, 5)}, "Vector2i")
	_expect(parse_data("v: !Vector3 [1, 2, 3]"), {"v": Vector3(1, 2, 3)}, "Vector3")
	_expect(parse_data("v: !Vector4 [1, 2, 3, 4]"), {"v": Vector4(1, 2, 3, 4)}, "Vector4")

	# Color from an array and from a hex string.
	_expect(parse_data("c: !Color [1, 0, 0]"), {"c": Color(1, 0, 0)}, "Color from array")
	_expect(parse_data("c: !Color [1, 0, 0, 0.5]"), {"c": Color(1, 0, 0, 0.5)}, "Color with alpha")
	_expect(parse_data('c: !Color "ff0000"'), {"c": Color("ff0000")}, "Color from hex")

	# Rects and other math types.
	_expect(parse_data("r: !Rect2 [0, 0, 10, 20]"), {"r": Rect2(0, 0, 10, 20)}, "Rect2")
	_expect(parse_data("q: !Quaternion [0, 0, 0, 1]"), {"q": Quaternion(0, 0, 0, 1)}, "Quaternion")
	_expect(parse_data("p: !Plane [0, 1, 0, 5]"), {"p": Plane(0, 1, 0, 5)}, "Plane")

	# String-backed types.
	_expect(parse_data("n: !StringName foo"), {"n": &"foo"}, "StringName")
	_expect(parse_data('n: !NodePath "a/b"'), {"n": NodePath("a/b")}, "NodePath")

	# Packed arrays of scalars, and of vectors.
	_expect(parse_data("s: !PackedStringArray [a, b, c]"),
		{"s": PackedStringArray(["a", "b", "c"])}, "PackedStringArray")
	_expect(parse_data("s: !PackedInt32Array [1, 2, 3]"),
		{"s": PackedInt32Array([1, 2, 3])}, "PackedInt32Array")
	_expect(parse_data("s: !PackedVector2Array [[0, 0], [1, 1]]"),
		{"s": PackedVector2Array([Vector2(0, 0), Vector2(1, 1)])}, "PackedVector2Array")

	# Matrix/transform types from rows.
	_expect(parse_data("b: !Basis [[1, 0, 0], [0, 1, 0], [0, 0, 1]]"),
		{"b": Basis(Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1))}, "Basis")

	# In a list item, at the document root, in a nested block, and inside a flow collection.
	_expect(parse_data("- !Vector2 [1, 2]\n- !Vector2 [3, 4]"),
		[Vector2(1, 2), Vector2(3, 4)], "tag on list items")
	_expect(parse_data("--- !Vector3 [1, 2, 3]"), Vector3(1, 2, 3), "tag at document root")
	_expect(parse_data("v: !Vector2\n  - 7\n  - 8"), {"v": Vector2(7, 8)}, "tag over a nested block")
	_expect(parse_data('v: [!Vector2 [1, 2], !Color "00ff00"]'),
		{"v": [Vector2(1, 2), Color("00ff00")]}, "tags inside a flow sequence")

	return passed()
