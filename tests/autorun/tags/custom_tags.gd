extends YAMLTest

# An application registers its own tags through `tag_constructors`: tag string -> Callable that
# takes the parsed value and returns the object. A user entry also overrides a built-in.

func run() -> bool:
	# A local tag the app defines.
	var p = YAMLParser.new()
	p.tag_constructors = {"!Deg": func(x): return deg_to_rad(x)}
	p.parse("angle: !Deg 90")
	_expect(p.data, {"angle": deg_to_rad(90)}, "a registered constructor is used")

	# The parsed value handed to the constructor is fully typed (here, an Array).
	p.tag_constructors = {"!Sum": func(a): return a[0] + a[1] + a[2]}
	p.parse("total: !Sum [1, 2, 3]")
	_expect(p.data, {"total": 6}, "constructor receives the parsed collection")

	# A user entry overrides a built-in of the same name.
	p.tag_constructors = {"!Vector2": func(_v): return "overridden"}
	p.parse("v: !Vector2 [1, 2]")
	_expect(p.data, {"v": "overridden"}, "a user tag overrides the built-in")

	# tag_constructors is configuration, not parse state: it survives across parses.
	p.parse("v: !Vector2 [3, 4]")
	_expect(p.data, {"v": "overridden"}, "registered tags persist across parses")

	return passed()
