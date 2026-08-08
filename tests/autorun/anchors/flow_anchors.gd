extends YAMLTest

# Anchors and aliases also work inside flow collections. Within one flow the entries are read
# left to right, so "[&a 1, *a]" registers the anchor before the alias that follows resolves.

func run() -> bool:
	# Anchor and alias inside a flow sequence.
	_check("v: [&a 1, *a, 3]", {"v": [1, 1, 3]})

	# Anchor and alias inside a flow mapping.
	_check("v: {x: &a 7, y: *a}", {"v": {"x": 7, "y": 7}})

	# An alias defined in block context, used inside a flow collection.
	_check("base: &b 5\nv: [*b, *b]", {"base": 5, "v": [5, 5]})

	# A flow value anchored, then aliased in block context.
	_check("v: &f [1, 2]\ncopy: *f", {"v": [1, 2], "copy": [1, 2]})

	# Merge with a flow sequence of aliases to block-defined mappings.
	_check("a: &a\n  p: 1\nb: &b\n  q: 2\nm:\n  <<: [*a, *b]",
		{"a": {"p": 1}, "b": {"q": 2}, "m": {"p": 1, "q": 2}})

	return passed()
