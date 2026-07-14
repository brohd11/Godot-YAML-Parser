class_name YAMLTest

## -1 = No run yet, 0 = pass, 1 = fail
var pass_state:= -1
## Report lines collected during the run. The runner folds these into its result.
var output: Array[String] = []
## Errors the parser raised during the most recent _check, for tests that assert on them.
var last_errors: Array[String] = []

## Parse and hand back just the data. For suites that assert on parsed values and
## have no interest in the Error itself; anything testing the API surface
## itself should drive YAMLParser directly.
static func parse_data(yaml: String) -> Variant:
	var parser = YAMLParser.new()
	parser.parse(yaml)
	return parser.data


func get_test_name():
	return get_script().resource_path.get_file()


func run() -> bool:
	return passed()

func passed():
	return pass_state == 0

func _log(text: String) -> void:
	output.append(text)


## Compare a value the test computed itself. `what` names the assertion in the report.
func _expect(got, expected, what: String = "") -> void:
	if got == expected:
		if pass_state == -1:
			pass_state = 0
		return
	pass_state = 1
	if not what.is_empty():
		_log("   %s" % what)
	_log(str("   got: ", got))
	_log(str("   exp: ", expected))


## Parse `yaml`, compare against `expected`, then assert it survives a dump round-trip.
## The parser's errors are drained into the report rather than the engine log. `_check` is
## for YAML that is meant to be VALID, so an error here is a failure in its own right --
## `data` is null on error, and the comparison below would fail anyway.
func _check(yaml: String, expected) -> bool:
	var parser = YAMLParser.new()
	parser.parse(yaml)
	var got = parser.data
	last_errors = parser.errors.duplicate()
	for e in last_errors:
		_log("   error: %s" % e)

	var ok = got == expected
	if ok:
		if pass_state == -1:
			pass_state = 0
	else:
		pass_state = 1
		_log(str("   got: ", got))
		_log(str("   exp: ", expected))

	var dump = YAMLParser.dump(got)
	parser.parse(dump)
	var reparse_ok = parser.data == expected
	if not reparse_ok:
		pass_state = 1
		_log(str("   reparse got: ", got))
		_log(str("   exp: ", expected))

	return passed()
