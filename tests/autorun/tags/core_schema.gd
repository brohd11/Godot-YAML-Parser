extends YAMLTest

# The core YAML 1.2 schema tags override implicit typing: "!!str 123" is the string "123", not
# the int 123. "!!seq"/"!!map" assert a node's shape.

func run() -> bool:
	_expect(parse_data("v: !!str 123"), {"v": "123"}, "!!str forces a string")
	_expect(parse_data("v: !!str true"), {"v": "true"}, "!!str on a would-be bool")
	_expect(parse_data('v: !!int "42"'), {"v": 42}, "!!int on a quoted number")
	_expect(parse_data("v: !!int 42"), {"v": 42}, "!!int on an int")
	_expect(parse_data('v: !!float "1.5"'), {"v": 1.5}, "!!float on a quoted number")
	_expect(parse_data('v: !!bool "true"'), {"v": true}, "!!bool true")
	_expect(parse_data('v: !!bool "false"'), {"v": false}, "!!bool false")
	_expect(parse_data("v: !!null anything"), {"v": null}, "!!null is always null")
	_expect(parse_data("v: !!seq [1, 2, 3]"), {"v": [1, 2, 3]}, "!!seq passes a sequence through")
	_expect(parse_data("v: !!map {a: 1}"), {"v": {"a": 1}}, "!!map passes a mapping through")

	return passed()
