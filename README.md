![logo](logo.jpg)

# YAML Parser 2.0.0 ![Godot v4.x](https://img.shields.io/badge/Godot-v4.x-%23478cbf)

A YAML parser written entirely in GDScript. No C++ modules, no compilation — drop it in and it
works on every platform Godot supports.

The API is modelled on Godot's own `JSON` class: a call returns an `Error` and leaves the result
in `data`. The parser never prints; what it repaired is reported in `warnings`, and it is up to
the caller to decide what to surface.

## Features

- 100% GDScript. Nothing to compile.
- Dictionaries, lists, and mixed structures nested to any depth.
- **Multiline JSON flow.** `[` / `{` may stay open across lines, with comments and blank lines
  inside, and the closing bracket may sit at any indent (including column 0).
- **Document markers.** `---` and `...`, with `parse_all()` for multi-document files.
- **Plain scalars.** A value may run on across more-indented lines, and a block (or a whole
  document) may be a bare scalar. Each line break folds to a single space.
- **Block scalars** (`|`, `>`) with chomping modifiers (`|-`, `|+`) and indentation indicators
  (e.g. `|2`).
- **Scalar types.** Any case of `true`/`false`/`null`, plus `.inf`, `.nan`, hex (`0x1F`) and digit
  grouping (`1_000`). `yes`/`no`/`on`/`off` stay strings, per the YAML 1.2 core schema.
- Quoted strings, inline comments, empty/null values.
- **Round-trips.** `dump()` quotes any string that would not read back as that same string, so
  `parse(dump(x)) == x`.

## Basic usage

```gdscript
var parser = YAMLParser.new()

var err = parser.parse_file("res://config/settings.yaml")
if err != OK:
    push_error(parser.get_error_message())
    return

var settings = parser.data
for w in parser.warnings:
    push_warning(w)
```

```gdscript
var parser = YAMLParser.new()

parser.parse(text)                # -> Error; data = first (or only) document
parser.parse_all(text)            # -> Error; data = every `---` document, as an Array
parser.parse_file(path)           # -> ERR_FILE_NOT_FOUND / ERR_FILE_CANT_OPEN on failure
parser.parse_all_file(path)

parser.data                       # the result of the last call
parser.get_error_message()        # why the last call failed, or ""
parser.warnings                   # non-fatal repairs: tab indent, unterminated flow
```

Dumping carries no state, so it stays static -- there is nothing to instantiate:

```gdscript
YAMLParser.dump(data)                 # -> String. Cannot fail.
YAMLParser.dump_to_file(data, path)   # -> Error. Creates the directory if it does not exist.
```

Parsing *text* never fails — the parser recovers from a malformed document rather than giving up,
so `parse()` always returns `OK` and records what it had to repair in `warnings`. The file entry
points are the ones that can actually return an error.

## ⚠️ Important Warning

Do **not** edit `.yaml` files directly from the Godot editor.
The editor may convert spaces to tabs, which **breaks YAML syntax** (YAML requires indentation
using **spaces only**).

Use an external editor with "tabs to spaces" enabled — Vim, VSCode, Sublime Text, Notepad++.

Tabs used for indentation are reported in `warnings`, not corrected.

## Known limitations

- No anchors, aliases or merge keys (`&a`, `*a`, `<<:`); they pass through as literal strings.
- An unterminated flow collection consumes the rest of its document and is then closed implicitly,
  with a warning. It cannot be bounded by indentation, because a legal closing bracket may be less
  indented than the key that opened it.
- A blank line inside a multiline quoted scalar folds to a single space rather than a newline.
- A trailing comma in a flow collection yields a trailing null element (`[1, 2, ]` -> `[1, 2, null]`),
  matching the strictness of the YAML and JSON specs, which both reject it outright.
- A flow mapping's keys are typed, so `{1: a}` has an **int** key, but `dump` writes `1: a`, which
  reads back as the **string** `"1"`. Non-string keys in flow mappings do not round-trip.

## Tests

```sh
godot --headless --script res://tests/ci_test.gd    # exits 0 on pass, 1 on failure
```

Suites live in `tests/suites/`; `tests/autorun/` is scanned automatically for `YAMLTest`
subclasses. CI runs the same entry point.

## Origin

Started as a fork of [YAML.gd](https://github.com/lowlevel-1989/YAML.gd) by Vinicio Valbuena. The
parser has since been rewritten and the API is no longer compatible with the original. MIT, with
the original copyright retained.

If the original was useful to you, you can support its author:

[!["Buy Me A Coffee"](coffee.png)](https://ko-fi.com/lowlevel1989)
