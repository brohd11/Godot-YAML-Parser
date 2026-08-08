extends YAMLTest

# The alias side: "*name" standing where a whole node is expected resolves to the anchored
# node, whatever its shape -- a scalar, a mapping, a sequence, or a whole document.

func run() -> bool:
	# Alias to a mapping.
	_check("anchor: &m\n  a: 1\n  b: 2\nuse: *m",
		{"anchor": {"a": 1, "b": 2}, "use": {"a": 1, "b": 2}})

	# Alias to a sequence.
	_check("anchor: &s\n  - x\n  - y\nuse: *s",
		{"anchor": ["x", "y"], "use": ["x", "y"]})

	# Alias to a scalar.
	_check("anchor: &n 42\nuse: *n", {"anchor": 42, "use": 42})

	# An alias as an entire document's node.
	var p = YAMLParser.new()
	p.parse_all("first: &a\n  k: v\n---\n*a")
	_expect(p.get_error_line() > 0, true, "alias cannot cross documents (root alias, prior anchor)")

	# Alias reused several times, each a full copy of the structure by value.
	_check("d: &d\n  n: 1\nlist:\n  - *d\n  - *d",
		{"d": {"n": 1}, "list": [{"n": 1}, {"n": 1}]})

	# Alias inside a sequence alongside plain items.
	_check("a: &a hello\nseq:\n  - one\n  - *a\n  - three",
		{"a": "hello", "seq": ["one", "hello", "three"]})

	return passed()
