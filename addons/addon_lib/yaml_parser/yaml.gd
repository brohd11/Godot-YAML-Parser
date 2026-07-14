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
		# Text ending in a newline splits to a phantom final "". It is not a line, and
		# counting it as one hands every block scalar a spurious trailing break.
		if lines.size() > 0 and lines[lines.size() - 1] == "":
			lines.remove_at(lines.size() - 1)

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
	## Saw a "]" or "}" with nothing open. Recorded rather than acted on, because driving
	## the depth negative would disable every later top-level test on the line.
	var unbalanced := false

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
		elif c == "]" or c == "}":
			if stack.is_empty():
				unbalanced = true
			else:
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
# Modelled on Godot's own JSON class: an entry point returns an Error and leaves the
# result in `data`, with get_error_message() and get_error_line() to say what went wrong.
# Nothing here ever prints -- a caller that wants a failure in the log pushes it itself.
#
# Malformed YAML is an error, not something to paper over. The parser reads the whole
# document either way, so `errors` lists everything wrong with it and not just the first
# thing -- but `data` is null, because a structure the parser had to guess at is worse
# than no structure at all.
# ---------------------------------------------------------------------------

## Result of the last parse. Null if it failed.
var data: Variant = null
## Every problem found in the last parse, each already carrying its line number. Empty
## when the parse succeeded.
var errors: Array[String] = []

var _err: Error = OK
var _err_msg := ""
var _err_line := -1
## Line in the ORIGINAL text that the document being parsed starts on. Documents are
## split before they are parsed, so a cursor index alone cannot name a line in the file.
var _origin := 0


## The reason the last call failed, or "" if it succeeded.
func get_error_message() -> String:
	return _err_msg


## The line the last failure was found on, or -1 if there was none.
func get_error_line() -> int:
	return _err_line


# Record a parse error. The first one becomes the reported failure; the rest still land
# in `errors`, so one call reports every problem in the file rather than a first taste.
func _error(line: int, msg: String) -> void:
	var text = "YAML: line %d: %s" % [line, msg] if line > 0 else "YAML: %s" % msg
	errors.append(text)
	if _err == OK:
		_err = ERR_PARSE_ERROR
		_err_msg = text
		_err_line = line


# The line in the original text that `idx` -- an index into the current document -- names.
func _line(idx: int) -> int:
	return _origin + idx + 1


# Parse the first (or only) document. A file with no `---` marker is one document,
# so this keeps its original meaning.
func parse(yaml_content: String) -> Error:
	_reset()
	var docs = _split_documents(yaml_content)
	if docs.is_empty():
		return OK
	data = _parse_text(docs[0][0], docs[0][2])
	if _err != OK:
		data = null
	return _err


# Parse every `---` separated document in the text. `data` is an Array.
func parse_all(yaml_content: String) -> Error:
	_reset()
	var out = []
	for doc in _split_documents(yaml_content):
		out.append(_parse_text(doc[0], doc[2]))
	data = [] if _err != OK else out
	return _err


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
	errors.clear()
	_err = OK
	_err_msg = ""
	_err_line = -1
	_origin = 0


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


func _parse_text(text: String, origin: int) -> Variant:
	_origin = origin
	var cur = _Cursor.new(text)
	var j = cur.peek()
	if j == -1:
		return null
	var out = _parse_block(cur, _get_indent_level(cur.line_at(j)))
	# The root block is the whole document, so anything peek() can still find is a line the
	# parser never accounted for -- a stray closing bracket, a mis-indented key, trailing
	# junk after a scalar. It parsed to nothing, which means the document is not what it looks.
	var k = cur.peek()
	if k != -1:
		_error(_line(k), "unexpected content: '%s'" % cur.line_at(k).strip_edges())
	return out


# Split raw text on `---` / `...` document markers.
#
# Safe as a pre-pass because a marker only counts in column 0, and a column-0 line
# can never be inside a block scalar: block content is always indented deeper than
# the key that introduced it.
#
# Each chunk carries whether a `---` opened it, which is what tells an empty document
# apart from the empty text before a leading marker. Without that flag the two are
# indistinguishable, and dropping both loses every empty document in the stream.
#
# It also carries the line the chunk starts on. A cursor index alone names a line in the
# CHUNK, and an error has to name a line in the FILE.
#
# Returns [text, opened_by_marker, origin_line] per document.
static func _split_documents(text: String) -> Array:
	var docs = []
	var chunk = PackedStringArray()
	var opened = false
	var started = false     # has this chunk seen a line of actual content yet?
	var origin = 0          # index of the chunk's first line in `text`
	var n = -1
	for raw in text.split("\n", true):
		n += 1
		var line = raw.rstrip("\r")
		var s = line.strip_edges()
		# A tab may separate a marker from its content just as a space does ("---\tfoo").
		var col0 = _get_indent_level(line) == 0
		# A directive ("%YAML 1.2", "%TAG ...") introduces a document; it is not content, and
		# nothing here resolves tags, so there is nothing for one to act on. It only counts
		# BEFORE the document's content: a "%" in column 0 further down belongs to whatever is
		# already open -- a zero-indented block scalar, a multi-line flow, a plain scalar
		# running on -- and skipping it there would eat a line of the value.
		#
		# Blanked rather than dropped: peek() skips an empty line just the same, and keeping
		# the line keeps every index below it lined up with the file, which is what lets an
		# error name a real line number.
		if col0 and not started and line.begins_with("%"):
			chunk.append("")
			continue
		var is_start = col0 and (s == "---" or s.begins_with("--- ") or s.begins_with("---\t"))
		var is_end = col0 and (s == "..." or s.begins_with("... ") or s.begins_with("...\t"))
		if not (is_start or is_end):
			chunk.append(line)
			# Blanks and comments are not content: a directive may still follow them.
			var bare = line.lstrip(" \t")
			if not (bare.is_empty() or bare.begins_with("#")):
				started = true
			continue
		docs.append(["\n".join(chunk), opened, origin])
		chunk = PackedStringArray()
		opened = is_start
		started = false
		# "--- foo" carries the document's root node on the marker line itself. Anything
		# past the three dashes and their separator is that node, whether a space or a
		# tab did the separating -- so the chunk starts ON the marker line, not after it.
		origin = n + 1
		if is_start and s.length() > 3:
			chunk.append(s.substr(4).strip_edges())
			started = true
			origin = n
	docs.append(["\n".join(chunk), opened, origin])

	var out = []
	for d in docs:
		# A chunk with content is a document. An empty one is a document only when a
		# `---` opened it: `---\n---\n` is two empty documents, but the empty text
		# before a leading `---`, or after a trailing `...`, is not a document at all.
		if _Cursor.new(d[0]).peek() != -1 or d[1]:
			out.append(d)
	return out


# YAML forbids tabs for INDENTATION, and _get_indent_level counts spaces only, so a
# tab-indented line reads as if it sat further left than it does and the structure quietly
# collapses. That is not something to repair -- the document does not mean what it looks
# like it means.
#
# Checked only where a mapping key or a sequence entry is read, because only those lines
# have indentation that MEANS something: their column is their nesting. Everywhere else a
# leading tab is separation, not indentation, and is perfectly legal -- "\t{}", "- \t-1" and
# a value written as "key:\n \tvalue" are all valid YAML. So are tabs inside block scalars,
# inside quoted scalars, and between tokens ("foo:\tbar"). A whole-document scan cannot tell
# any of that apart from a real tab indent and condemns all of it.
func _check_indent_tab(cur: _Cursor, j: int) -> void:
	var raw = cur.line_at(j)
	var n = _get_indent_level(raw)
	if n < raw.length() and raw[n] == "\t":
		_error(_line(j), "tab used for indentation; YAML requires spaces")


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
	# A block scalar can be the block itself, when its header rode in on the document
	# marker ("--- |"). Everywhere else a key or a dash introduces it, and the header
	# is dispatched from there. Without this the header parses as a plain scalar and
	# takes its own content with it: "--- >" became the string "> ab cd".
	if _is_block_header(content0):
		cur.i = j + 1
		# indent - 1, not indent: a block scalar reached here is the block itself, so the
		# node above it is its parent, and at the document root there is none. Its content
		# may therefore legally start in column 0 ("--- >" with text flush left).
		return _consume_block_scalar(cur, content0, indent - 1)
	if _is_list_line(content0):
		return _parse_list(cur, indent)
	# An explicit entry holds no colon on its "? key" line, so the plain-scalar test below
	# would claim it. It is a mapping.
	if _is_explicit_key(content0):
		return _parse_map(cur, indent)
	# No key at all, so the block is not a map: it is a plain scalar, possibly
	# spanning lines. Same discriminator _parse_list uses for its plain items.
	var kv0 = _split_key_value(content0)
	if kv0[1] == null and not content0.ends_with(":"):
		cur.i = j + 1
		return _parse_plain_scalar(cur, content0, indent)
	return _parse_map(cur, indent)


# Fold the continuation lines of a multi-line plain scalar onto `first`.
#
# A single line break folds to one space, but a run of N blank lines is N newlines --
# that is how a plain scalar gets a paragraph break. Blank lines trailing the scalar
# belong to whatever structure follows it, so they are dropped rather than folded.
#
# `deeper_only` picks the bound. A scalar that IS the block owns every line down to
# the first one shallower than `indent`, since a scalar block has no siblings by
# construction. A scalar continuing an inline value owns only the lines strictly
# deeper than the key that introduced it.
func _fold_plain(cur: _Cursor, first: String, indent: int, deeper_only: bool) -> String:
	var text = first
	var blanks = 0
	while true:
		var j = cur.peek()
		if j == -1:
			break
		var ind = _get_indent_level(cur.line_at(j))
		if ind < indent or (deeper_only and ind == indent):
			break
		# peek() stepped over the blank and comment lines in [cur.i, j). Only the blank
		# ones fold; a comment contributes nothing to the scalar.
		for k in range(cur.i, j):
			if cur.line_at(k).strip_edges().is_empty():
				blanks += 1
		var content = _strip_inline_comment(cur.line_at(j).strip_edges())
		cur.i = j + 1
		if content.is_empty():
			continue
		# A plain scalar may not contain ": " -- YAML forbids it precisely so that this is
		# unambiguous. A continuation line holding one is a mapping entry that lost its
		# indentation and is being swallowed into the scalar above it.
		if _find_key_separator(content) != -1:
			_error(_line(j), "mapping entry folded into a plain scalar: '%s'" % content)
		text += ("\n".repeat(blanks) if blanks > 0 else " ") + content
		blanks = 0
	return text


# A block whose first line is a scalar: a whole document may be one, as may the value under
# a bare "key:". A quoted scalar folds by its own rules and must not be run through the plain
# folder as well, or its breaks get folded twice.
func _parse_plain_scalar(cur: _Cursor, first: String, indent: int) -> Variant:
	if first.begins_with('"') or first.begins_with("'"):
		return _parse_value(_complete_quoted(cur, first))
	return _parse_value(_fold_plain(cur, first, indent, false))


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
		_check_indent_tab(cur, j)
		var content = _strip_inline_comment(raw.substr(indent))
		if _is_list_line(content):
			break

		# An explicit entry: "? key" on one line, and optionally ": value" on a later one.
		# Both markers introduce a node of their own, so both go through the same rebuild.
		if _is_explicit_key(content):
			var xkey = _parse_explicit_node(cur, j, indent)
			var xvalue = null
			var vj = cur.peek()
			if vj != -1 and _get_indent_level(cur.line_at(vj)) == indent:
				var vcontent = cur.line_at(vj).substr(indent)
				if _is_explicit_value(vcontent):
					xvalue = _parse_explicit_node(cur, vj, indent)
			# A "?" key with no ":" line of its own simply has no value.
			result[xkey] = xvalue
			continue

		var kv = _split_key_value(content)
		var key = _unquote_key(kv[0])
		var value_str = kv[1]
		cur.i = j + 1

		# Every line of a mapping has to BE an entry. With no separator this is not one --
		# a key whose colon was forgotten -- and it used to become a key with a null value.
		if not kv[2]:
			_error(_line(j), "expected 'key: value', found '%s'" % content)
		# YAML forbids a duplicate key. A Dictionary would simply overwrite the first, which
		# loses data the author plainly meant to keep.
		if result.has(key):
			_error(_line(j), "duplicate key '%s'" % key)

		if value_str == null:
			result[key] = _parse_value_after_key(cur, indent)
		elif value_str != null and _is_block_header(value_str):
			result[key] = _consume_block_scalar(cur, value_str, indent)
		else:
			result[key] = _parse_scalar_or_quoted(cur, value_str, indent)
	return result


# "? key" opens an explicit mapping entry. The space matters: "?foo: bar" is an ordinary key
# that merely starts with a question mark, and a plain scalar may legally begin with one.
static func _is_explicit_key(content: String) -> bool:
	if not content.begins_with("?"):
		return false
	return content.length() == 1 or content[1] == " " or content[1] == "\t"


# ": value" answering an explicit key, under the same rule.
static func _is_explicit_value(content: String) -> bool:
	if not content.begins_with(":"):
		return false
	return content.strip_edges() == ":" or content[1] == " " or content[1] == "\t"


# The node introduced by a "?" or ":" marker. It begins at its own column, part way along the
# marker's line -- exactly the shape _parse_nested_dash_list already handles for "- - x". So
# rebuild it the same way: re-pad the text after the marker to the column it really sits at,
# gather the lines beneath that belong to it, and hand the lot back to _parse_block. A compact
# sequence ("? a" / ": - one" / "  - two") and a multi-line plain key then both fall out of the
# ordinary block parser instead of needing a private code path.
func _parse_explicit_node(cur: _Cursor, marker_idx: int, indent: int) -> Variant:
	var raw0 = cur.line_at(marker_idx)
	cur.i = marker_idx + 1
	var after = raw0.substr(indent + 1)
	var trimmed = after.lstrip(" \t")
	if trimmed.is_empty() or trimmed.begins_with("#"):
		# Nothing on the marker line; the node is on the lines below it.
		return _parse_value_after_key(cur, indent)
	# A block scalar's content is measured from the ENTRY, not from the header's own column:
	# in "? |" the header sits at column 2 and its content does too, and only the entry's
	# indent is shallower than both.
	if _is_block_header(trimmed):
		return _consume_block_scalar(cur, trimmed, indent)
	var node_col = indent + 1 + (after.length() - trimmed.length())
	var synth = PackedStringArray([" ".repeat(node_col) + trimmed])
	while cur.i < cur.lines.size():
		var r = cur.line_at(cur.i)
		if r.strip_edges() == "":
			synth.append("")
			cur.i += 1
			continue
		if _get_indent_level(r) < node_col:
			break
		synth.append(r)
		cur.i += 1
	return _parse_block(_Cursor.new("\n".join(synth)), node_col)


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
		_check_indent_tab(cur, j)
		var content = _strip_inline_comment(raw.substr(indent))
		var stripped = content.lstrip(" \t")
		if not stripped.begins_with("-"):
			break

		# Column where item content begins (after the dash and its spaces).
		var dash_col = indent + (content.length() - stripped.length())
		var after = stripped.substr(1)  # everything after the dash
		var after_trimmed = after.lstrip(" \t")
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

		# "- |" is a block scalar, not the plain scalar "|". A bare header holds no colon,
		# so _split_key_value sees nothing and the plain-scalar branch below would fold the
		# header together with its own content. The dash's column is the parent: the content
		# has to beat it, and an indicator like ">1" is measured from it.
		if _is_block_header(item_text):
			result.append(_consume_block_scalar(cur, item_text, indent))
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
				# The key is the parent, so an indicator like "|2" counts from item_indent.
				# A sibling key sits AT item_indent and so still ends the block, since the
				# scan stops on any line at or shallower than its parent.
				d[k] = _consume_block_scalar(cur, v, item_indent)
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


# A line of spaces is empty. A line holding a TAB is not: the tab is content, and if it is
# the first such line it sets the block's indent. strip_edges() cannot be used to test this,
# because it strips tabs too and so reports " \t" as blank.
static func _is_blank_line(s: String) -> bool:
	return s.lstrip(" ").is_empty()


# Consume a block scalar (| or >) by lookahead. The block ends at the first
# non-blank line whose indent is less than the block's established indent.
func _consume_block_scalar(cur: _Cursor, header: String, parent_indent: int) -> String:
	var style = ML_LITERAL if header.begins_with("|") else ML_FOLDED
	# The indicators may come in either order -- "|2-" and "|-2" are both legal -- so look
	# for the chomping character anywhere in the header rather than only at the end.
	var chomping = "clip"
	for c in header.substr(1):
		if c == "-":
			chomping = "strip"
		elif c == "+":
			chomping = "keep"

	var collected = []
	# An explicit indentation indicator ("|2") fixes the content column relative to
	# the parent, instead of inferring it from the first line.
	var hint = _block_indent_hint(header)
	var block_indent = parent_indent + hint if hint > 0 else -1
	while cur.i < cur.lines.size():
		var raw = cur.line_at(cur.i)
		if _is_blank_line(raw):
			# A whitespace-only line still carries whatever sits past the block's indent:
			# inside a block indented 2, a line of three spaces contributes one. Before
			# the indent is known such a line is simply empty, and it must not set it --
			# the indent comes from the first line with real content.
			if block_indent == -1:
				collected.append("")
			else:
				collected.append(raw.substr(block_indent) if raw.length() > block_indent else "")
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


# Fold the lines of a ">" block scalar, including the break that terminates each one.
#
# Consecutive lines flush with the block's indent join with a single space, and a run of N
# blank lines becomes N newlines. But a MORE-INDENTED line is never folded: it stays literal,
# and the break beside it stays a line feed, on top of any blank lines. That extra break is
# the whole difference between a paragraph and a preserved block -- without it, an indented
# table or bullet list inside a ">" collapses into one long line.
static func _fold_block_lines(lines: Array) -> String:
	var out := ""
	var prev := ""          # "", "folded" (flush) or "spaced" (more indented)
	var blanks := 0
	for ln in lines:
		if _is_blank_line(ln):
			blanks += 1
			continue
		var kind = "spaced" if (ln.begins_with(" ") or ln.begins_with("\t")) else "folded"
		if prev.is_empty():
			out += "\n".repeat(blanks) + ln
		elif kind == "folded" and prev == "folded" and blanks == 0:
			out += " " + ln
		else:
			# Between two flush lines the break IS the fold, so only the blanks count.
			# Anywhere a spaced line is involved, the break survives on its own.
			var breaks = blanks if (kind == "folded" and prev == "folded") else 1 + blanks
			out += "\n".repeat(breaks) + ln
		prev = kind
		blanks = 0
	if out.is_empty():
		return "\n".repeat(blanks)
	# The final line's own break, then whatever blank lines trailed it. Chomping decides
	# how many of those survive.
	return out + "\n" + "\n".repeat(blanks)


# Process collected block-scalar lines according to style and chomping.
static func _process_multiline_content(content: Array, style: int, chomping: String) -> String:
	var lines = content.duplicate()

	var full_content = ""
	if style == ML_FOLDED:
		full_content = _fold_block_lines(lines)
	else:
		# Every line carries its own break. Joining on "\n" instead would give one break
		# fewer than there are lines, which `keep` then reports faithfully as a missing
		# trailing newline.
		for ln in lines:
			full_content += ln + "\n"

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
	# A quoted scalar may span lines on its own, with no flow collection around it. It needs
	# its lines RAW -- _complete_flow strips each one, and the folding rules turn on exactly
	# the leading and trailing whitespace that would destroy.
	if s.begins_with('"') or s.begins_with("'"):
		return _parse_value(_complete_quoted(cur, s))
	return _parse_value(_continue_plain_scalar(cur, _complete_flow(cur, s), indent))


# If `first` opens a quoted scalar it does not close, pull the following lines off the cursor
# until the quote closes, and return the whole thing with its line breaks intact. The closing
# line is cut at the quote, so a comment after it is not swallowed.
func _complete_quoted(cur: _Cursor, first: String) -> String:
	# The line the quote opened on -- what an error should point at, not wherever the parser
	# eventually ran out of document.
	var start = cur.i - 1
	var sc = _Scan.new()
	_feed_all(sc, first)
	if sc.quote.is_empty():
		return first          # closed on its own line; nothing to continue
	var parts = PackedStringArray([first])
	while cur.i < cur.lines.size():
		var raw = cur.line_at(cur.i)
		cur.i += 1
		var i = 0
		while i < raw.length():
			i += sc.feed_at(raw, i)
			if sc.quote.is_empty():
				break
		if sc.quote.is_empty():
			parts.append(raw.substr(0, i))
			return "\n".join(parts)
		parts.append(raw)
	# Ran off the end of the document with the quote still open.
	_error(_line(start), "unterminated quoted scalar; expected a closing %s" % sc.quote)
	parts.append(sc.quote)
	return "\n".join(parts)


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
	return _fold_plain(cur, text, indent, true)


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

	# The line `first` came from. An error here names the bracket that opened, not the line
	# the parser happened to give up on -- the opening is what the author has to go fix.
	var start = cur.i - 1
	var sc = _Scan.new()
	_feed_all(sc, first)
	if sc.unbalanced:
		_error(_line(start), "unmatched closing bracket in '%s'" % first.strip_edges())
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
		_error(_line(start), "unterminated flow collection; expected '%s'" % sc.closers())
		parts.append(sc.closers())

	# A single space, because a plain or quoted scalar may itself span lines and
	# YAML folds that break to one space. Between structural tokens the space is
	# discarded by the strip_edges() in _split_top_level.
	return " ".join(parts)


# Split the inside of a flow collection on its top-level commas.
#
# YAML permits a trailing comma -- "[a, b, ]" and "{a: 1, }" are both legal, and the spec
# uses them in its own examples -- so an empty final item is separator punctuation, not an
# empty node. Without this, "[1, 2, ]" parsed to [1, 2, null].
static func _flow_items(inner: String) -> Array:
	var items = _split_top_level(inner, ",")
	if items.size() > 1 and items[items.size() - 1].strip_edges().is_empty():
		items.remove_at(items.size() - 1)
	return items


# The index of a top-level ": " separator, or -1.
#
# A bare colon will not do. _find_top_level takes the FIRST top-level colon whatever follows
# it, which is fine for a flow mapping entry -- already known to be a pair -- but would read
# "[http://example.com]" as {"http": "//example.com"}. Only a colon with whitespace after it,
# or one ending the token, separates a key from its value. Same rule _split_key_value uses.
static func _find_key_separator(s: String) -> int:
	var sc = _Scan.new()
	var i = 0
	while i < s.length():
		if sc.top() and s[i] == ":" \
				and (i + 1 >= s.length() or s[i + 1] == " " or s[i + 1] == "\t"):
			return i
		i += sc.feed_at(s, i)
	return -1


# An entry in a flow sequence may itself be a single "key: value" pair, which YAML reads as a
# one-entry mapping: "[foo: bar]" is a sequence holding {foo: bar}, not the scalar "foo: bar".
static func _parse_flow_entry(item: String) -> Variant:
	var idx = _find_key_separator(item)
	if idx == -1:
		return _parse_value(item)
	var v = item.substr(idx + 1).strip_edges()
	return {_parse_value(item.substr(0, idx)): (null if v.is_empty() else _parse_value(v))}


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
			for item in _flow_items(inner):
				result.append(_parse_flow_entry(item))
		return result

	# Inline flow mapping.
	if s.begins_with("{") and s.ends_with("}"):
		var inner = s.substr(1, s.length() - 2)
		var result = {}
		if not inner.strip_edges().is_empty():
			for item in _flow_items(inner):
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
	# Where this line's run of LITERAL trailing whitespace begins in `result`, or -1.
	# Whitespace a line ENDS with is not part of the scalar, but whitespace an escape
	# produced (a \t, or a backslash-space) is -- and a plain rstrip cannot tell them
	# apart. Set on a source space or tab, cleared on anything else, including escapes.
	var ws_start = -1
	while i < content.length():
		var c = content[i]

		# A line break inside a quoted scalar folds, exactly as it does in a plain one:
		# one break is a space, N blank lines are N newlines. The whitespace around the
		# break -- trailing on this line, leading on the next -- is not content.
		if c == "\n":
			if ws_start >= 0:
				result = result.substr(0, ws_start)
				ws_start = -1
			var breaks = 1
			i += 1
			while i < content.length():
				var j = i
				while j < content.length() and (content[j] == " " or content[j] == "\t"):
					j += 1
				if j < content.length() and content[j] == "\n":
					breaks += 1
					i = j + 1
					continue
				i = j     # drop the next line's leading whitespace
				break
			result += " " if breaks == 1 else "\n".repeat(breaks - 1)
			continue

		if quote == "'":
			# In single quotes, only '' is special (escaped single quote).
			if c == "'" and i + 1 < content.length() and content[i + 1] == "'":
				result += "'"
				ws_start = -1
				i += 2
				continue
			if c == " " or c == "\t":
				if ws_start == -1:
					ws_start = result.length()
			else:
				ws_start = -1
			result += c
			i += 1
			continue

		# A backslash immediately before the break escapes it: no fold, no space, and the
		# next line's leading whitespace still goes.
		if c == "\\" and i + 1 < content.length() and content[i + 1] == "\n":
			ws_start = -1
			i += 2
			while i < content.length() and (content[i] == " " or content[i] == "\t"):
				i += 1
			continue

		# Double-quote escape handling.
		if escape:
			escape = false
			# \xXX, \uXXXX and \UXXXXXXXX carry their codepoint in the digits that follow.
			# A malformed one is left as the bare character, in keeping with the parser's
			# habit of recovering rather than failing.
			var digits = 0
			match c:
				"x": digits = 2
				"u": digits = 4
				"U": digits = 8
			# Anything an escape produces is content, whitespace included, so the run of
			# literal trailing whitespace ends here.
			ws_start = -1
			if digits > 0:
				var hex = content.substr(i + 1, digits)
				var code = hex.hex_to_int() if hex.is_valid_hex_number() else -1
				# A Godot String cannot hold a NUL -- it truncates there -- and anything
				# past the Unicode range is not a character at all. Leave both as the bare
				# escape rather than corrupt the string around them.
				if hex.length() == digits and code > 0 and code <= 0x10FFFF:
					result += String.chr(code)
					i += 1 + digits
					continue
				result += c
				i += 1
				continue
			match c:
				"n": result += "\n"
				"t": result += "\t"
				"r": result += "\r"
				"b": result += char(0x08)
				"f": result += char(0x0C)
				"v": result += char(0x0B)
				"a": result += char(0x07)
				"e": result += char(0x1B)
				# \0 is NUL, which a Godot String cannot carry -- it truncates there. Left
				# as a bare "0" rather than silently cutting the rest of the value away.
				"N": result += char(0x85)   # next line
				"_": result += char(0xA0)   # non-breaking space
				"L": result += char(0x2028) # line separator
				"P": result += char(0x2029) # paragraph separator
				"\\": result += "\\"
				"\"": result += "\""
				"'": result += "'"
				_: result += c   # covers \/ and anything unrecognised
			i += 1
			continue
		if c == "\\":
			escape = true
			i += 1
			continue
		if c == " " or c == "\t":
			if ws_start == -1:
				ws_start = result.length()
		else:
			ws_start = -1
		result += c
		i += 1
	# Whitespace before the CLOSING QUOTE is content -- it never met a line break -- so
	# ws_start is deliberately not applied here.
	return result


static func _unquote_key(k: String) -> String:
	k = k.strip_edges()
	if (k.begins_with('"') and k.ends_with('"')) or (k.begins_with("'") and k.ends_with("'")):
		return _parse_quoted_string(k)
	return k


# Split "key: value" on the first top-level ": " (or trailing ":").
# Returns [key, value_or_null].
# Returns [key, value_or_null, found_separator].
#
# The third element is what tells "key:" (an entry whose value is null) apart from "key"
# (not an entry at all). The scan to find the separator has to happen anyway, so saying
# whether it found one costs nothing -- and without it a line missing its colon quietly
# becomes a key with a null value.
static func _split_key_value(line: String) -> Array:
	var sc = _Scan.new()
	var i = 0
	while i < line.length():
		# A tab separates just as well as a space. Only tab INDENTATION is illegal in
		# YAML; as whitespace between tokens a tab is perfectly legal ("foo:\tbar").
		if sc.top() and line[i] == ":" \
				and (i + 1 >= line.length() or line[i + 1] == " " or line[i + 1] == "\t"):
			var v = line.substr(i + 1).strip_edges()
			return [line.substr(0, i).strip_edges(), null if v.is_empty() else v, true]
		i += sc.feed_at(line, i)
	if line.strip_edges().ends_with(":"):
		var key = line.strip_edges()
		return [key.substr(0, key.length() - 1).strip_edges(), null, true]
	return [line.strip_edges(), null, false]


# True if a line (already indent-stripped) starts a list entry: a dash that is
# either alone or followed by a space. "- - x" matches on the space, so there is
# no need to accept a second dash -- and accepting one is what used to make the
# document marker "---" look like a list entry and destroy the document.
static func _is_list_line(content: String) -> bool:
	var s = content.lstrip(" \t")
	if not s.begins_with("-"):
		return false
	return s.length() == 1 or s[1] == " " or s[1] == "\t"


# Remove a trailing " #..." comment at top level (outside quotes/brackets).
static func _strip_inline_comment(content: String) -> String:
	var sc = _Scan.new()
	var i = 0
	while i < content.length():
		if sc.top() and content[i] == "#" and i > 0 \
				and (content[i - 1] == " " or content[i - 1] == "\t"):
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
