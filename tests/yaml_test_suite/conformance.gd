## Scores YAMLParser against the official yaml-test-suite (yaml/yaml-test-suite).
##
## Report only -- this is not part of the CI run. It lives outside tests/autorun/ so
## test_run.gd does not discover it, and its entry point always exits 0.
##
##     python3 tests/yaml_test_suite/gen_suite.py                          # build the corpus
##     godot --headless --script res://tests/yaml_test_suite/conformance_test.gd
##
## Two numbers, because the suite measures two different things. The headline is correctness:
## of the cases carrying a JSON expectation, how many do we read the same way a conforming
## parser would? Below it is strictness: of the 94 documents that MUST be rejected, how many
## do we actually reject? The second is the weaker of the two by design -- the checks in the
## parser are chosen to never reject a valid document, and that bar costs coverage here.

const SUITE_PATH = "res://tests/yaml_test_suite/suite.json"
const RESULTS_PATH = "res://tests/yaml_test_suite/results.json"

# Feature probes, in priority order: a case is filed under the first one that matches its
# input. Heuristics on the raw text, not a parse -- enough to rank the backlog, no more.
#
# Ordered most-specific first, so the unsupported node properties claim their cases before
# the structural probes below them can. Whatever reaches "other" should be genuinely
# unclassified, which is the point: that is the list worth reading.
const BUCKETS: Array = [
	# An anchor or alias name is almost any non-space run, so \w is too narrow -- it missed
	# "&:@*!$" and an emoji anchor, both of which landed in "other" and had to be traced by hand.
	["anchors & aliases", "(^|[\\s\\[{,])[&*][^\\s,\\]}]|<<\\s*:"],
	["tags & directives", "(^|\\s)!|^%"],
	["explicit keys (?)", "^\\s*\\?(\\s|$)"],
	# A block scalar header: | or > with optional indent/chomp indicators, then a comment
	# or end of line.
	["block scalars", "(^|\\s)[|>][0-9+\\-]*[ \\t]*(#.*)?$"],
	["flow collections", "[\\[{]"],
	["quoted scalars", "[\"']"],
]

# Tab indentation is not guessed at. A regex on the raw text cannot tell an indenting tab
# from a tab sitting inside block-scalar content, and that mistake filed six cases under
# "tab indentation" that were really quoted and block scalars. The parser already knows --
# it says so in `errors` -- so ask it instead.
const TAB_INDENT_ERROR = "tab used for indentation"


static func run() -> Dictionary:
	var cases = _load_suite()
	if cases.is_empty():
		return {"output": ["Could not read %s -- run gen_suite.py first." % SUITE_PATH]}

	var passed: Array[String] = []
	var failed: Array[String] = []
	var skipped: Array[String] = []
	# Must-fail cases. Now that parse() can actually fail, these are a real score: rejecting
	# them is a pass, accepting them is a miss.
	var rejected: Array[String] = []
	var accepted: Array[String] = []

	# Cases the parser itself reported as tab-indented, which is more reliable than any
	# pattern we could run over the raw text.
	var tab_indented := {}

	for case in cases:
		var parser = YAMLParser.new()
		var err = parser.parse_all(case["yaml"])

		for e in parser.errors:
			if e.contains(TAB_INDENT_ERROR):
				tab_indented[case["id"]] = true
				break

		if case["fail"]:
			if err != OK:
				rejected.append(case["id"])
			else:
				accepted.append(case["id"])
		elif case.has("json"):
			if _equiv(parser.data, case["json"]):
				passed.append(case["id"])
			else:
				failed.append(case["id"])
		else:
			skipped.append(case["id"])

	var scored = passed.size() + failed.size()
	var by_bucket = _bucket(failed, cases, tab_indented)

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
	var must_fail = rejected.size() + accepted.size()
	out.append("Must-fail cases: %d / %d correctly rejected (%.1f%%)" % [
			rejected.size(), must_fail, 100.0 * rejected.size() / maxi(must_fail, 1)])
	out.append("  still accepted    %3d   %s" % [accepted.size(), _preview(accepted)])
	out.append("")
	out.append("Skipped: %d (valid, but no JSON expectation in the suite)" % skipped.size())

	_write_results(passed, failed, skipped, rejected, accepted)
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


static func _bucket(failed: Array[String], cases: Array, tab_indented: Dictionary) -> Dictionary:
	var yaml_by_id := {}
	for case in cases:
		yaml_by_id[case["id"]] = case["yaml"]

	var out := {}
	for entry in BUCKETS:
		out[entry[0]] = []
	out["tab indentation"] = []
	out["other"] = []

	for id in failed:
		# The parser's own verdict outranks any pattern.
		if tab_indented.has(id):
			out["tab indentation"].append(id)
			continue
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
		skipped: Array[String], rejected: Array[String], accepted: Array[String]) -> void:
	var f = FileAccess.open(RESULTS_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({
		"suite": "data-2022-01-17",
		"passed": passed,
		"failed": failed,
		"skipped": skipped,
		"must_fail_rejected": rejected,
		"must_fail_accepted": accepted,
	}, "  "))
	f.close()
