## Scores YAMLParser against the official yaml-test-suite (yaml/yaml-test-suite).
##
## Report only -- this is not part of the CI run. It lives outside tests/autorun/ so
## test_run.gd does not discover it, and its entry point always exits 0.
##
##     python3 tests/yaml_test_suite/gen_suite.py                          # build the corpus
##     godot --headless --script res://tests/yaml_test_suite/conformance_test.gd
##
## The suite measures strictness, which is the axis this parser deliberately trades away:
## parse() never fails, it repairs and warns. So the 94 must-fail cases are reported
## rather than scored, and the headline number covers the cases with a JSON expectation.

const SUITE_PATH = "res://tests/yaml_test_suite/suite.json"
const RESULTS_PATH = "res://tests/yaml_test_suite/results.json"

# Feature probes, in priority order: a case is filed under the first one that matches its
# input. Heuristics on the raw text, not a parse -- enough to rank the backlog, no more.
const BUCKETS: Array = [
	["anchors & aliases", "(^|[\\s\\[{,])[&*][\\w\\-]|<<\\s*:"],
	["tags & directives", "(^|\\s)!|^%"],
	["explicit keys (?)", "^\\s*\\?(\\s|$)"],
	["tab indentation", "^\\t| \\t"],
]


static func run() -> Dictionary:
	var cases = _load_suite()
	if cases.is_empty():
		return {"output": ["Could not read %s -- run gen_suite.py first." % SUITE_PATH]}

	var passed: Array[String] = []
	var failed: Array[String] = []
	var skipped: Array[String] = []
	# Must-fail cases: the parser cannot reject, so record whether it at least warned.
	var warned: Array[String] = []
	var silent: Array[String] = []

	for case in cases:
		var parser = YAMLParser.new()
		parser.parse_all(case["yaml"])

		if case["fail"]:
			if parser.warnings.is_empty():
				silent.append(case["id"])
			else:
				warned.append(case["id"])
		elif case.has("json"):
			if _equiv(parser.data, case["json"]):
				passed.append(case["id"])
			else:
				failed.append(case["id"])
		else:
			skipped.append(case["id"])

	var scored = passed.size() + failed.size()
	var by_bucket = _bucket(failed, cases)

	var out: Array[String] = []
	out.append("YAML Test Suite (yaml/yaml-test-suite, data-2022-01-17)")
	out.append("")
	out.append("  %d / %d passing (%.1f%%)" % [
			passed.size(), scored, 100.0 * passed.size() / maxi(scored, 1)])
	out.append("")
	out.append("Failures by feature (heuristic)")
	for name in by_bucket:
		var ids: Array = by_bucket[name]
		out.append("  %-20s %3d   %s" % [name, ids.size(), _preview(ids)])
	out.append("")
	out.append("Must-fail cases: %d (not scored -- parse() cannot fail by design)" % (
			warned.size() + silent.size()))
	out.append("  warned            %3d" % warned.size())
	out.append("  silently accepted %3d   %s" % [silent.size(), _preview(silent)])
	out.append("")
	out.append("Skipped: %d (valid, but no JSON expectation in the suite)" % skipped.size())

	_write_results(passed, failed, skipped, warned, silent)
	out.append("Wrote %s" % RESULTS_PATH)

	return {"output": out, "passed": passed, "failed": failed}


static func _load_suite() -> Array:
	var f = FileAccess.open(SUITE_PATH, FileAccess.READ)
	if f == null:
		return []
	var parsed = JSON.parse_string(f.get_buffer(f.get_length()).get_string_from_utf8())
	return parsed if parsed is Array else []


# The suite's expectation comes back through JSON, so a whole number may arrive as either
# an int or a float depending on which side produced it. Compare numbers by value; recurse
# through containers so a nested mismatch is not masked by Variant equality.
static func _equiv(got, expected) -> bool:
	if got is float or got is int:
		if not (expected is float or expected is int):
			return false
		return float(got) == float(expected)

	if got is Array:
		if not (expected is Array) or got.size() != expected.size():
			return false
		for i in got.size():
			if not _equiv(got[i], expected[i]):
				return false
		return true

	if got is Dictionary:
		if not (expected is Dictionary) or got.size() != expected.size():
			return false
		for key in expected:
			if not got.has(key) or not _equiv(got[key], expected[key]):
				return false
		return true

	# GDScript's == raises on mismatched types rather than returning false, and a parser
	# under test will hand us plenty of those.
	if typeof(got) != typeof(expected):
		return false
	return got == expected


static func _bucket(failed: Array[String], cases: Array) -> Dictionary:
	var yaml_by_id := {}
	for case in cases:
		yaml_by_id[case["id"]] = case["yaml"]

	var out := {}
	for entry in BUCKETS:
		out[entry[0]] = []
	out["other"] = []

	for id in failed:
		var text: String = yaml_by_id[id]
		var placed := false
		for entry in BUCKETS:
			var re = RegEx.create_from_string("(?m)" + entry[1])
			if re.search(text) != null:
				out[entry[0]].append(id)
				placed = true
				break
		if not placed:
			out["other"].append(id)

	return out


static func _preview(ids: Array) -> String:
	if ids.is_empty():
		return ""
	var shown = ids.slice(0, 4)
	var s = ", ".join(shown)
	return s + (", ..." if ids.size() > shown.size() else "")


static func _write_results(passed: Array[String], failed: Array[String],
		skipped: Array[String], warned: Array[String], silent: Array[String]) -> void:
	var f = FileAccess.open(RESULTS_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({
		"suite": "data-2022-01-17",
		"passed": passed,
		"failed": failed,
		"skipped": skipped,
		"must_fail_warned": warned,
		"must_fail_silent": silent,
	}, "  "))
	f.close()
