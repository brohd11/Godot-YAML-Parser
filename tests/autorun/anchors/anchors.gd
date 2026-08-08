extends YAMLTest

# An anchor "&name" labels a node; an alias "*name" elsewhere is that same node. There is no
# node type in this parser -- values are native Godot Dictionaries/Arrays/scalars -- so an
# anchor is the RETURN of the sub-parse, and an alias hands that same object back. The anchor
# is registered only AFTER its node finishes, which is why a self-reference cannot form a cycle.

func run() -> bool:
	# Anchor and alias on a scalar value.
	_check("a: &x 5\nb: *x", {"a": 5, "b": 5})

	# Anchor on a whole mapping; the alias reproduces it.
	_check("defaults: &d\n  color: red\n  size: 10\nitem: *d",
		{"defaults": {"color": "red", "size": 10}, "item": {"color": "red", "size": 10}})

	# Anchor on a list value, reused by alias.
	_check("base: &l\n  - 1\n  - 2\ncopy: *l",
		{"base": [1, 2], "copy": [1, 2]})

	# Anchor on a plain scalar that is itself a list item.
	_check("- &a 1\n- *a\n- 2", [1, 1, 2])

	# Anchor on a list item that is a mapping.
	_check("- &p\n    name: bob\n- *p", [{"name": "bob"}, {"name": "bob"}])

	# A document-root anchor labels the mapping that follows at column 0.
	_check("--- &root\nfoo: 1\nbar: 2", {"foo": 1, "bar": 2})

	# A bare "&a" with nothing after it (and no deeper node) is an anchor on null.
	_check("a: &e\nb: *e", {"a": null, "b": null})

	# Redefining an anchor is allowed; the later definition wins for later aliases.
	_check("a: &x 1\nb: &x 2\nc: *x", {"a": 1, "b": 2, "c": 2})

	# An anchor nested inside a block, aliased from a shallower level.
	_check("outer:\n  inner: &v\n    k: 1\nsame: *v",
		{"outer": {"inner": {"k": 1}}, "same": {"k": 1}})

	# Shared reference: per the chosen semantics the alias is the SAME object, not a copy.
	var p = YAMLParser.new()
	p.parse("base: &b\n  x: 1\nother: *b")
	_expect(is_same(p.data["base"], p.data["other"]), true, "alias shares the anchor's object")

	# Anchors do not carry across a document boundary.
	p.parse_all("---\na: &x 1\n---\nb: *x")
	_expect(p.get_error_line(), 4, "an alias cannot reach an anchor in a prior document")

	return passed()
