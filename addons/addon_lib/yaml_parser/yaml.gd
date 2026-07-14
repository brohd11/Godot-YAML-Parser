extends RefCounted
class_name YAMLParser

# Node types kept for compatibility with any external references.
const NODE_DICT = 0
const NODE_LIST = 1

# A block scalar header: "|" or ">", then an optional indentation indicator (1-9)
# and an optional chomping indicator, in either order -- e.g. "|", ">-", "|2", "|2-".
# This used to be a fixed list matched by equality, which left "|2" parsing as the
# literal string "|2".
static func _is_block_header(s: String) -> bool:
	if s.is_empty() or (s[0] != "|" and s[0] != ">"):
		return false
	var seen_indent = false
	var seen_chomp = false
	for c in s.substr(1):
		if c >= "1" and c <= "9" and not seen_indent:
			seen_indent = true
		elif (c == "-" or c == "+") and not seen_chomp:
			seen_chomp = true
		else:
			return false
	return true


# The indentation indicator from a block header, or 0 if there is none. It is
# relative to the parent node's indentation.
static func _block_indent_hint(header: String) -> int:
	for c in header.substr(1):
		if c >= "1" and c <= "9":
			return c.to_int()
	return 0

# ---------------------------------------------------------------------------
# Line cursor: holds the split lines and a mutable index we fully control.
# Using an explicit index (instead of `for i in range(...)`) is what allows
# block scalars to be consumed by lookahead and lets us re-examine a line
# after a nested block returns. This avoids the old `i -= 1` no-op bug.
# ---------------------------------------------------------------------------
class _Cursor:
	var lines: PackedStringArray
	var i: int = 0

	func _init(text: String) -> void:
		lines = text.split("\n", true)

	# Index of the next significant (non-empty, non-comment) line, or -1.
	func peek() -> int:
		var j = i
		while j < lines.size():
			var s = lines[j].rstrip("\r")
			var st = s.lstrip(" \t")
			if st.is_empty() or st[0] == "#":
				j += 1
				continue
			return j
		return -1

	func line_at(idx: int) -> String:
		return lines[idx].rstrip("\r")


# ---------------------------------------------------------------------------
# Flow scanner: the single copy of "am I inside a quote or a bracket right now".
# Every top-level scan drives one of these. The state survives across feed_at()
# calls, which is what lets a flow collection -- and a quoted scalar inside one --
# span lines.
# ---------------------------------------------------------------------------
class _Scan:
	var stack := PackedStringArray()  # expected closers, innermost last
	var quote := ""                   # open quote char, "" when outside a string

	func depth() -> int:
		return stack.size()

	# Outside any quote. Brackets may still be open.
	func bare() -> bool:
		return quote.is_empty()

	# Outside any quote AND any bracket.
	func top() -> bool:
		return quote.is_empty() and stack.is_empty()

	# Consume the char at s[i]; returns how many chars it consumed (1 or 2).
	# Index-based rather than char-at-a-time so an escape pair is swallowed whole
	# and its second char is never re-read as an opening quote.
	func feed_at(s: String, i: int) -> int:
		var c = s[i]
		var has_next = i + 1 < s.length()
		if not quote.is_empty():
			if quote == "'":
				# Single quotes take no backslash escapes; only '' is special.
				if c == "'":
					if has_next and s[i + 1] == "'":
						return 2
					quote = ""
				return 1
			if c == "\\" and has_next:
				return 2
			if c == '"':
				quote = ""
			return 1
		if c == '"' or c == "'":
			quote = c
		elif c == "[":
			stack.append("]")
		elif c == "{":
			stack.append("}")
		elif (c == "]" or c == "}") and not stack.is_empty():
			# A closer with nothing open is ignored rather than driving the depth
			# negative, which would disable every later top-level test on the line.
			stack.resize(stack.size() - 1)
		return 1

	# What it would take to balance an unterminated flow: close the open quote,
	# then the outstanding brackets innermost first.
	func closers() -> String:
		var out = quote
		for k in range(stack.size() - 1, -1, -1):
			out += stack[k]
		return out


# Advance `sc` over every char of `s`. No comment handling.
static func _feed_all(sc: _Scan, s: String) -> void:
	var i = 0
	while i < s.length():
		i += sc.feed_at(s, i)


# ---------------------------------------------------------------------------
# Public entry points.
#
# Modelled on Godot's own JSON class: an entry point returns an Error and leaves
# the result in `data`. Nothing here ever prints -- a caller that wants a failure
# in the log pushes it themselves, from get_error_message() and warnings.
# ---------------------------------------------------------------------------

## Result of the last parse. Null if it failed.
var data: Variant = null
## Non-fatal problems from the last parse: the document still parsed, but something
## in it was repaired (a tab indent, an unterminated flow collection).
var warnings: Array[String] = []

var _err: Error = OK
var _err_msg := ""


## The reason the last call failed, or "" if it succeeded.
func get_error_message() -> String:
	return _err_msg


# Parse the first (or only) document. A file with no `---` marker is one document,
# so this keeps its original meaning.
func parse(yaml_content: String) -> Error:
	_reset()
	var docs = _split_documents(yaml_content)
	if docs.is_empty():
		return OK
	data = _parse_text(docs[0])
	return OK


# Parse every `---` separated document in the text. `data` is an Array.
func parse_all(yaml_content: String) -> Error:
	_reset()
	var out = []
	for text in _split_documents(yaml_content):
		out.append(_parse_text(text))
	data = out
	return OK


# Parse the first (or only) document in `path`.
func parse_file(path: String) -> Error:
	_reset()
	var text = _read_file(path)
	if text == null:
		return _err
	return parse(text)


# Parse every document in `path`. `data` is an Array.
func parse_all_file(path: String) -> Error:
	_reset()
	var text = _read_file(path)
	if text == null:
		data = []
		return _err
	return parse_all(text)


func _reset() -> void:
	data = null
	warnings.clear()
	_err = OK
	_err_msg = ""


# Record a failure and hand back its code, so a caller can `return _fail(...)`.
func _fail(code: Error, msg: String) -> Error:
	_err = code
	_err_msg = msg
	return code


# Read a file whole, or record why it could not be read and return null.
func _read_file(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		_fail(ERR_FILE_NOT_FOUND, "YAML: file not found: '%s'" % path)
		return null
	var f = FileAccess.open(path, FileAccess.READ)
	if f == null:
		_fail(ERR_FILE_CANT_OPEN, "YAML: cannot read '%s': %s"
				% [path, error_string(FileAccess.get_open_error())])
		return null
	var text = f.get_as_text()
	f.close()
	return text


func _parse_text(text: String) -> Variant:
	var cur = _Cursor.new(text)
	var j = cur.peek()
	if j == -1:
		return null
	_warn_tabs(cur)
	return _parse_block(cur, _get_indent_level(cur.line_at(j)))


# Split raw text on `---` / `...` document markers.
#
# Safe as a pre-pass because a marker only counts in column 0, and a column-0 line
# can never be inside a block scalar: block content is always indented deeper than
# the key that introduced it. Chunks holding nothing but blanks and comments are
# dropped, so a leading `---` does not produce a phantom empty document.
static func _split_documents(text: String) -> Array:
	var docs = []
	var chunk = PackedStringArray()
	for raw in text.split("\n", true):
		var line = raw.rstrip("\r")
		var s = line.strip_edges()
		var marker = _get_indent_level(line) == 0 and (s == "---" or s.begins_with("--- ") \
				or s == "..." or s.begins_with("... "))
		if not marker:
			chunk.append(line)
			continue
		docs.append("\n".join(chunk))
		chunk = PackedStringArray()
		# "--- foo" carries the document's root node on the marker line itself.
		if s.begins_with("--- "):
			chunk.append(s.substr(4).strip_edges())
	docs.append("\n".join(chunk))

	var out = []
	for d in docs:
		if _Cursor.new(d).peek() != -1:
			out.append(d)
	return out


# YAML forbids tabs for indentation, and _get_indent_level counts spaces only, so a
# tab-indented line reads as column 0 and the structure silently collapses. Say so
# rather than mangle the document quietly.
func _warn_tabs(cur: _Cursor) -> void:
	for i in range(cur.lines.size()):
		var line = cur.lines[i]
		for c in line:
			if c == "\t":
				warnings.append("YAML: tab used for indentation on line %d; YAML requires spaces" % [i + 1])
				return
			if c != " ":
				break


# Parse all sibling nodes at exactly `indent`. Decides map vs list from the
# first significant line at that indent.
func _parse_block(cur: _Cursor, indent: int) -> Variant:
	var j = cur.peek()
	if j == -1:
		return null
	var line0 = cur.line_at(j)
	if _get_indent_level(line0) != indent:
		return null
	var content0 = _strip_inline_comment(line0.substr(indent))
	# A block may itself be a flow collection. This one branch covers the document
	# root ("[1, 2]" as the whole file), a flow on the line after a bare "key:",
	# a flow after an empty dash, and the synthetic sub-document of a "- - [" item.
	if content0.begins_with("[") or content0.begins_with("{"):
		cur.i = j + 1
		return _parse_scalar_or_quoted(cur, content0, indent)
	if _is_list_line(content0):
		return _parse_list(cur, indent)
	# No key at all, so the block is not a map: it is a plain scalar, possibly
	# spanning lines. Same discriminator _parse_list uses for its plain items.
	var kv0 = _split_key_value(content0)
	if kv0[1] == null and not content0.ends_with(":"):
		cur.i = j + 1
		return _parse_plain_scalar(cur, content0, indent)
	return _parse_map(cur, indent)


# A block whose first line is a plain scalar. The block owns every line down to
# the first one shallower than `indent` -- a scalar block has no siblings by
# construction -- and YAML folds each line break in a plain scalar to one space.
func _parse_plain_scalar(cur: _Cursor, first: String, indent: int) -> Variant:
	var parts = PackedStringArray([first])
	while true:
		var j = cur.peek()
		if j == -1:
			break
		if _get_indent_level(cur.line_at(j)) < indent:
			break
		var content = _strip_inline_comment(cur.line_at(j).strip_edges())
		cur.i = j + 1
		if not content.is_empty():
			parts.append(content)
	return _parse_value(" ".join(parts))


func _parse_map(cur: _Cursor, indent: int) -> Dictionary:
	var result = {}
	while true:
		var j = cur.peek()
		if j == -1:
			break
		var raw = cur.line_at(j)
		var ind = _get_indent_level(raw)
		if ind != indent:
			break
		var content = _strip_inline_comment(raw.substr(indent))
		if _is_list_line(content):
			break
		var kv = _split_key_value(content)
		var key = _unquote_key(kv[0])
		var value_str = kv[1]
		cur.i = j + 1

		if value_str == null:
			result[key] = _parse_value_after_key(cur, indent)
		elif value_str != null and _is_block_header(value_str):
			result[key] = _consume_block_scalar(cur, value_str, indent)
		else:
			result[key] = _parse_scalar_or_quoted(cur, value_str, indent)
	return result


# After a "key:" with no inline value, decide between a nested block, a
# same-indent block sequence, or a plain null.
func _parse_value_after_key(cur: _Cursor, indent: int) -> Variant:
	var nj = cur.peek()
	if nj == -1:
		return null
	var nraw = cur.line_at(nj)
	var nind = _get_indent_level(nraw)
	var ncontent = _strip_inline_comment(nraw.substr(nind))
	if nind > indent:
		return _parse_block(cur, nind)
	# A block sequence may be indented at the SAME column as its key.
	if nind == indent and _is_list_line(ncontent):
		return _parse_list(cur, indent)
	return null


func _parse_list(cur: _Cursor, indent: int) -> Array:
	var result = []
	while true:
		var j = cur.peek()
		if j == -1:
			break
		var raw = cur.line_at(j)
		var ind = _get_indent_level(raw)
		if ind != indent:
			break
		var content = _strip_inline_comment(raw.substr(indent))
		var stripped = content.lstrip(" ")
		if not stripped.begins_with("-"):
			break

		# Column where item content begins (after the dash and its spaces).
		var dash_col = indent + (content.length() - stripped.length())
		var after = stripped.substr(1)  # everything after the dash
		var after_trimmed = after.lstrip(" ")
		var item_indent = dash_col + 1 + (after.length() - after_trimmed.length())
		var item_text = after_trimmed.strip_edges()
		cur.i = j + 1

		# Empty dash: value lives on the following deeper lines.
		if item_text.is_empty():
			var nj = cur.peek()
			if nj != -1 and _get_indent_level(cur.line_at(nj)) > indent:
				result.append(_parse_block(cur, _get_indent_level(cur.line_at(nj))))
			else:
				result.append(null)
			continue

		# Nested list: "- - x" means this item is itself a list.
		if after_trimmed.begins_with("-"):
			result.append(_parse_nested_dash_list(cur, j, item_indent, indent))
			continue

		var kv = _split_key_value(item_text)
		if kv[1] == null and not item_text.ends_with(":"):
			# Plain scalar item. "- [" also lands here: _split_key_value finds no
			# top-level colon in it. A continuation line only has to beat the dash's
			# own indent, so the threshold is `indent`, not `item_indent`.
			result.append(_parse_scalar_or_quoted(cur, item_text, indent))
		else:
			# Map item: first pair is inline, remaining keys sit at item_indent.
			var d = {}
			var k = _unquote_key(kv[0])
			var v = kv[1]
			if v == null:
				var nj = cur.peek()
				if nj != -1 and _get_indent_level(cur.line_at(nj)) >= item_indent \
						and _get_indent_level(cur.line_at(nj)) > indent:
					d[k] = _parse_block(cur, _get_indent_level(cur.line_at(nj)))
				else:
					d[k] = null
			elif v != null and _is_block_header(v):
				# A sibling key at item_indent must terminate the block, so the
				# block's own content has to be deeper than item_indent - 1.
				d[k] = _consume_block_scalar(cur, v, item_indent - 1)
			else:
				# Runs before _merge_item_keys, so a multi-line flow here is fully
				# consumed and the sibling-key scan starts below it. The threshold is
				# item_indent so a sibling key at that column is not folded into the
				# value as if it were a continuation line.
				d[k] = _parse_scalar_or_quoted(cur, v, item_indent)
			_merge_item_keys(cur, d, item_indent)
			result.append(d)
	return result


# Collect additional "key: value" pairs of a list item's map (lines at exactly
# item_indent that are not themselves list entries).
func _merge_item_keys(cur: _Cursor, d: Dictionary, item_indent: int) -> void:
	while true:
		var j = cur.peek()
		if j == -1:
			break
		var raw = cur.line_at(j)
		if _get_indent_level(raw) != item_indent:
			break
		var content = _strip_inline_comment(raw.substr(item_indent))
		if _is_list_line(content):
			break
		var kv = _split_key_value(content)
		var k = _unquote_key(kv[0])
		var v = kv[1]
		cur.i = j + 1
		if v == null:
			d[k] = _parse_value_after_key(cur, item_indent)
		elif v != null and _is_block_header(v):
			d[k] = _consume_block_scalar(cur, v, item_indent)
		else:
			d[k] = _parse_scalar_or_quoted(cur, v, item_indent)


# Handle "- - x" by reconstructing a sub-document at item_indent: the remainder
# of the dash line (re-padded) plus the following lines that belong to it.
func _parse_nested_dash_list(cur: _Cursor, header_idx: int, item_indent: int, parent_indent: int) -> Variant:
	var raw0 = cur.line_at(header_idx)
	var stripped = raw0.substr(parent_indent).lstrip(" ")
	var after = stripped.substr(1).lstrip(" ")  # text after the first dash
	var synth = PackedStringArray()
	synth.append(" ".repeat(item_indent) + after)
	# Track brackets while collecting, because a flow opened inside this item owns
	# its continuation lines no matter how they are indented -- a closing bracket
	# is legal in column 0. Breaking on indent there would truncate the flow and
	# leave the stray "]" to be parsed as a key by the caller.
	var sc = _Scan.new()
	_feed_line(sc, after)
	while cur.i < cur.lines.size():
		var r = cur.line_at(cur.i)
		if r.strip_edges() == "":
			synth.append("")
			cur.i += 1
			continue
		if sc.depth() == 0 and _get_indent_level(r) < item_indent:
			break
		synth.append(r)
		cur.i += 1
		# Feed a comment-cut copy; a bracket inside a comment is not a real one.
		_feed_line(sc, r.strip_edges())
	var sub = _Cursor.new("\n".join(synth))
	return _parse_block(sub, item_indent)


# Consume a block scalar (| or >) by lookahead. The block ends at the first
# non-blank line whose indent is less than the block's established indent.
func _consume_block_scalar(cur: _Cursor, header: String, parent_indent: int) -> String:
	var style = ML_LITERAL if header.begins_with("|") else ML_FOLDED
	var chomping = "clip"
	if header.ends_with("-"):
		chomping = "strip"
	elif header.ends_with("+"):
		chomping = "keep"

	var collected = []
	# An explicit indentation indicator ("|2") fixes the content column relative to
	# the parent, instead of inferring it from the first line.
	var hint = _block_indent_hint(header)
	var block_indent = parent_indent + hint if hint > 0 else -1
	while cur.i < cur.lines.size():
		var raw = cur.line_at(cur.i)
		if raw.strip_edges() == "":
			collected.append("")
			cur.i += 1
			continue
		var ind = _get_indent_level(raw)
		if block_indent == -1:
			if ind <= parent_indent:
				break
			block_indent = ind
		elif ind < block_indent:
			break
		collected.append(raw.substr(block_indent) if raw.length() >= block_indent else "")
		cur.i += 1

	return _process_multiline_content(collected, style, chomping)


# Multiline state markers (kept for _process_multiline_content signature parity).
const ML_LITERAL = 1
const ML_FOLDED = 2


# Process collected block-scalar lines according to style and chomping.
static func _process_multiline_content(content: Array, style: int, chomping: String) -> String:
	var lines = content.duplicate()

	# Folding: join consecutive non-empty lines with a single space.
	if style == ML_FOLDED:
		var out = []
		var prev_empty = false
		for ln in lines:
			var empty = ln.strip_edges().is_empty()
			if empty:
				out.append("")
				prev_empty = true
			else:
				if not out.is_empty() and not prev_empty \
						and not out[-1].ends_with(" ") and out[-1] != "":
					out[-1] += " " + ln
				else:
					out.append(ln)
				prev_empty = false
		lines = out

	var full_content = "\n".join(lines)

	match chomping:
		"strip":
			full_content = full_content.rstrip("\n")
		"clip":
			# Clip keeps a single trailing newline -- but an empty block has no
			# content to terminate, so it stays empty rather than becoming "\n".
			full_content = full_content.rstrip("\n")
			if not full_content.is_empty():
				full_content += "\n"
		"keep":
			pass
	return full_content


# ---------------------------------------------------------------------------
# Scalar / value helpers.
# ---------------------------------------------------------------------------

# Parse a value that may be a plain scalar, quoted string, or a flow collection.
# Advances the cursor past the continuation lines of a multi-line flow, and of a
# plain scalar that runs on past its key line. `indent` is the indent of the line
# the value came from: continuation lines must be deeper than it.
func _parse_scalar_or_quoted(cur: _Cursor, s: String, indent: int) -> Variant:
	return _parse_value(_continue_plain_scalar(cur, _complete_flow(cur, s), indent))


# A plain scalar value may run on across the following, more-indented lines, each
# break folding to a single space. Only a PLAIN scalar does: a flow collection has
# already been closed by _complete_flow, and a quoted scalar spanning lines is not
# supported outside one, so anything opening with a bracket or a quote is left as is.
#
# This is unambiguous rather than a guess -- in valid YAML a deeper line following
# an INLINE value can only be a continuation of it. A block scalar is dispatched
# before we get here, a flow is already consumed, and peek() skips comment lines.
func _continue_plain_scalar(cur: _Cursor, text: String, indent: int) -> String:
	if text.is_empty() or text[0] in ["[", "{", '"', "'"]:
		return text
	var parts = PackedStringArray([text])
	while true:
		var j = cur.peek()
		if j == -1:
			break
		if _get_indent_level(cur.line_at(j)) <= indent:
			break
		var content = _strip_inline_comment(cur.line_at(j).strip_edges())
		cur.i = j + 1
		if not content.is_empty():
			parts.append(content)
	if parts.size() == 1:
		return text
	return " ".join(parts)


# If `first` opens a flow collection that it does not close, pull the following
# lines off the cursor until the brackets balance and return the whole thing as
# one logical line. Otherwise return `first` untouched.
#
# Raw lines rather than peek(): blank lines and full-line comments are legal
# inside a flow, and a closing bracket may legally sit in column 0 -- a
# multi-line flow simply cannot be bounded by indentation.
func _complete_flow(cur: _Cursor, first: String) -> String:
	# Only a value that _parse_value would itself treat as a flow may consume
	# lines. Without this gate a plain scalar holding a stray bracket ("todo [wip")
	# would open a depth and swallow the rest of the document.
	if not (first.begins_with("[") or first.begins_with("{")):
		return first

	var sc = _Scan.new()
	_feed_all(sc, first)
	if sc.depth() == 0:
		return first  # closes on its own line: the existing path, byte for byte

	# The flow stays open, so from here comments are cut on quote state alone.
	# Rescan the first line under that rule: the caller stripped it with the
	# depth-gated rule, which leaves a comment after an opening bracket in place.
	sc = _Scan.new()
	var parts = PackedStringArray([_consume_line(sc, first)])
	while sc.depth() > 0 and cur.i < cur.lines.size():
		var piece = _consume_line(sc, cur.line_at(cur.i).strip_edges())
		cur.i += 1
		if not piece.is_empty():
			parts.append(piece)

	if sc.depth() > 0:
		warnings.append("YAML: unterminated flow collection, auto-closed with '%s'" % sc.closers())
		parts.append(sc.closers())

	# A single space, because a plain or quoted scalar may itself span lines and
	# YAML folds that break to one space. Between structural tokens the space is
	# discarded by the strip_edges() in _split_top_level.
	return " ".join(parts)


# Convert a string token to the appropriate Godot type.
static func _parse_value(s: String) -> Variant:
	s = s.strip_edges()
	if s.is_empty(): return null

	# YAML 1.2 core schema accepts any case for these. `yes`/`no`/`on`/`off` are
	# deliberately NOT booleans -- that is YAML 1.1 -- and _scalar() already quotes
	# them on the way out, so leaving them as strings keeps the round-trip honest.
	var lower = s.to_lower()
	if lower == "null" or s == "~": return null
	if lower == "true": return true
	if lower == "false": return false

	if s.is_valid_int(): return s.to_int()
	if s.is_valid_float(): return s.to_float()

	if lower == ".inf" or lower == "+.inf": return INF
	if lower == "-.inf": return -INF
	if lower == ".nan": return NAN
	if s.is_valid_hex_number(true): return s.hex_to_int()

	# Digit grouping: 1_000_000. Only if what is left is actually a number, so an
	# ordinary word like snake_case falls through to the string branch below.
	if s.contains("_"):
		var bare = s.replace("_", "")
		if bare.is_valid_int(): return bare.to_int()
		if bare.is_valid_float(): return bare.to_float()

	# Inline flow sequence.
	if s.begins_with("[") and s.ends_with("]"):
		var inner = s.substr(1, s.length() - 2)
		var result = []
		if not inner.strip_edges().is_empty():
			for item in _split_top_level(inner, ","):
				result.append(_parse_value(item))
		return result

	# Inline flow mapping.
	if s.begins_with("{") and s.ends_with("}"):
		var inner = s.substr(1, s.length() - 2)
		var result = {}
		if not inner.strip_edges().is_empty():
			for item in _split_top_level(inner, ","):
				var idx = _find_top_level(item, ":")
				if idx == -1:
					result[_parse_value(item)] = null
				else:
					var k = _parse_value(item.substr(0, idx))
					var v = item.substr(idx + 1).strip_edges()
					result[k] = null if v.is_empty() else _parse_value(v)
		return result

	# Quoted string.
	if (s.begins_with('"') and s.ends_with('"')) or (s.begins_with("'") and s.ends_with("'")):
		return _parse_quoted_string(s)

	return s


# Parse a quoted string, resolving escape sequences (double-quote style) and
# doubled-quote escapes (single-quote style).
static func _parse_quoted_string(s: String) -> String:
	if s.length() < 2:
		return s
	var quote = s[0]
	var content = s.substr(1, s.length() - 2)
	var result = ""
	var escape = false
	var i = 0
	while i < content.length():
		var c = content[i]
		if quote == "'":
			# In single quotes, only '' is special (escaped single quote).
			if c == "'" and i + 1 < content.length() and content[i + 1] == "'":
				result += "'"
				i += 2
				continue
			result += c
			i += 1
			continue
		# Double-quote escape handling.
		if escape:
			escape = false
			match c:
				"n": result += "\n"
				"t": result += "\t"
				"r": result += "\r"
				"\\": result += "\\"
				"\"": result += "\""
				"'": result += "'"
				_: result += c
			i += 1
			continue
		if c == "\\":
			escape = true
			i += 1
			continue
		result += c
		i += 1
	return result


static func _unquote_key(k: String) -> String:
	k = k.strip_edges()
	if (k.begins_with('"') and k.ends_with('"')) or (k.begins_with("'") and k.ends_with("'")):
		return _parse_quoted_string(k)
	return k


# Split "key: value" on the first top-level ": " (or trailing ":").
# Returns [key, value_or_null].
static func _split_key_value(line: String) -> Array:
	var sc = _Scan.new()
	var i = 0
	while i < line.length():
		if sc.top() and line[i] == ":" and (i + 1 >= line.length() or line[i + 1] == " "):
			var v = line.substr(i + 1).strip_edges()
			return [line.substr(0, i).strip_edges(), null if v.is_empty() else v]
		i += sc.feed_at(line, i)
	if line.strip_edges().ends_with(":"):
		var key = line.strip_edges()
		return [key.substr(0, key.length() - 1).strip_edges(), null]
	return [line.strip_edges(), null]


# True if a line (already indent-stripped) starts a list entry: a dash that is
# either alone or followed by a space. "- - x" matches on the space, so there is
# no need to accept a second dash -- and accepting one is what used to make the
# document marker "---" look like a list entry and destroy the document.
static func _is_list_line(content: String) -> bool:
	var s = content.lstrip(" ")
	if not s.begins_with("-"):
		return false
	return s.length() == 1 or s[1] == " "


# Remove a trailing " #..." comment at top level (outside quotes/brackets).
static func _strip_inline_comment(content: String) -> String:
	var sc = _Scan.new()
	var i = 0
	while i < content.length():
		if sc.top() and content[i] == "#" and i > 0 and content[i - 1] == " ":
			return content.substr(0, i).strip_edges()
		i += sc.feed_at(content, i)
	return content


# Cut a comment from one line of an OPEN flow collection, advancing `sc` as it
# goes so quote and bracket state carry into the next line.
#
# The comment rule here is deliberately depth-agnostic, unlike the depth-gated
# _strip_inline_comment above: a continuation line's own bracket depth is
# meaningless, since it is relative to a flow that opened on an earlier line.
# It also cuts a comment that is the whole line (i == 0), which the trailing-
# comment rule above would miss.
static func _consume_line(sc: _Scan, line: String) -> String:
	var i = 0
	while i < line.length():
		if sc.bare() and line[i] == "#" and (i == 0 or line[i - 1] == " " or line[i - 1] == "\t"):
			return line.substr(0, i).strip_edges()
		i += sc.feed_at(line, i)
	return line


# Advance `sc` over one source line, cutting its comment first. Which comment
# rule applies depends on whether a flow is already open (see _consume_line).
static func _feed_line(sc: _Scan, line: String) -> String:
	if sc.depth() > 0:
		return _consume_line(sc, line)
	# A whole-line comment is fed nothing at all. _strip_inline_comment only cuts a
	# `#` at i > 0, so without this a bracket inside such a comment would open a
	# depth that never closes.
	if sc.bare() and line.lstrip(" \t").begins_with("#"):
		return ""
	var cut = _strip_inline_comment(line)
	_feed_all(sc, cut)
	return cut


# Count leading spaces (YAML indentation is spaces only).
static func _get_indent_level(line: String) -> int:
	var indent = 0
	for c in line:
		if c == ' ':
			indent += 1
		else:
			break
	return indent


# Find a delimiter char at bracket-depth 0 outside quotes; -1 if none.
static func _find_top_level(s: String, delim: String) -> int:
	var sc = _Scan.new()
	var i = 0
	while i < s.length():
		if sc.top() and s[i] == delim:
			return i
		i += sc.feed_at(s, i)
	return -1


# Split a string on a single-char delimiter at bracket-depth 0 outside quotes.
static func _split_top_level(s: String, delim: String) -> Array:
	# Slice on the delimiter positions rather than accumulating char by char, so
	# an escape pair is copied through intact.
	var parts = []
	var sc = _Scan.new()
	var start = 0
	var i = 0
	while i < s.length():
		if sc.top() and s[i] == delim:
			parts.append(s.substr(start, i - start).strip_edges())
			i += 1
			start = i
			continue
		i += sc.feed_at(s, i)
	parts.append(s.substr(start).strip_edges())
	return parts


# ---------------------------------------------------------------------------
# Dump
# ---------------------------------------------------------------------------
## Dump `data_to_dump` and write it to `path`, creating the directory if it does not exist.
## Static: dumping carries no state to report, so there is nothing to instantiate.
static func dump_to_file(data_to_dump: Variant, path: String) -> Error:
	var dir = path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		var mk = DirAccess.make_dir_recursive_absolute(dir)
		if mk != OK:
			return mk
	var f = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(dump(data_to_dump) + "\n")
	f.close()
	return OK


static func dump(data_to_dump, indent: int = 0) -> String:
	if data_to_dump is Dictionary or data_to_dump is Array:
		if data_to_dump.is_empty():
			return "{}" if data_to_dump is Dictionary else "[]"
	else:
		# A scalar document. Only reachable at the top level: the recursion below
		# renders scalar leaves with _scalar() and never calls back into dump().
		return _scalar(data_to_dump)

	var lines = []
	var pad = "  ".repeat(indent)

	if data_to_dump is Dictionary:
		for key in data_to_dump:
			var safe_key = _scalar(key)
			var val = data_to_dump[key]
			if val is Dictionary or val is Array:
				if val.is_empty():
					lines.append("%s%s: %s" % [pad, safe_key, "{}" if val is Dictionary else "[]"])
				else:
					lines.append("%s%s:" % [pad, safe_key])
					lines.append(dump(val, indent + 1))
			else:
				lines.append("%s%s: %s" % [pad, safe_key, _scalar(val)])
	elif data_to_dump is Array:
		for item in data_to_dump:
			if item is Dictionary or item is Array:
				if item.is_empty():
					lines.append("%s- %s" % [pad, "{}" if item is Dictionary else "[]"])
				else:
					lines.append("%s-" % pad)
					lines.append(dump(item, indent + 1))
			else:
				lines.append("%s- %s" % [pad, _scalar(item)])

	return "\n".join(lines)


static func _scalar(val) -> String:
	if val == null:
		return "null"
	if val is bool:
		return "true" if val else "false"
	if val is float:
		# str() renders these as "inf" / "nan", which do not read back as floats.
		if is_inf(val):
			return ".inf" if val > 0 else "-.inf"
		if is_nan(val):
			return ".nan"
		return str(val)
	if val is int:
		return str(val)

	var s = str(val)
	if s.is_empty():
		return '""'

	var needs_quotes = false
	var lower_s = s.to_lower()
	if lower_s in ["true", "false", "null", "yes", "no", "on", "off", "~"]:
		needs_quotes = true
	elif s.is_valid_float() or s.is_valid_int():
		needs_quotes = true

	var special_chars = [
		":", "{", "}", "[", "]", ",", "&", "*", "#", "?", "|",
		"-", "<", ">", "=", "!", "%", "@", "`", "\n", "\"", "\\"
	]
	if not needs_quotes:
		for c in special_chars:
			if c in s:
				needs_quotes = true
				break

	if s.begins_with(" ") or s.ends_with(" "):
		needs_quotes = true

	# The round-trip invariant: quote any string that would NOT read back as this
	# same string. Catches every scalar form the parser types -- .inf, .nan, hex,
	# digit-grouped ints -- without having to enumerate them here as they are added.
	if not needs_quotes and not (_parse_value(s) is String):
		needs_quotes = true

	if needs_quotes:
		s = s.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n")
		return '"%s"' % s

	return s
