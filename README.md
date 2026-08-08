# YAML Parser ![Godot v4.x](https://img.shields.io/badge/Godot-v4.x-%23478cbf)

A YAML parser written in GDScript, you can easily include a single file to provide parsing in your plugin package without needing a separate dependency.

Not 100% spec compliant -- tags are not supported, for instance. For a fully featured parser check out some of the other Godot plugins that wrap a native library, they will also be much quicker.


## Basic usage

```gdscript
var parser = YAMLParser.new()

var err = parser.parse_file("res://config/settings.yaml")
if err != OK:
    for e in parser.errors:
        push_error(e)
    return

var settings = parser.data
```

```gdscript
var parser = YAMLParser.new()

parser.parse(text)                # -> Error; data = first (or only) document
parser.parse_all(text)            # -> Error; data = every `---` document, as an Array
parser.parse_file(path)           # -> also ERR_FILE_NOT_FOUND / ERR_FILE_CANT_OPEN
parser.parse_all_file(path)

parser.data                       # the result of the last call -- null if it failed
parser.errors                     # every problem found, each already naming its line
parser.get_error_message()        # the first of them, or "" 
parser.get_error_line()           # its line number, or -1
```

Dumping carries no state, so it stays static.

```gdscript
YAMLParser.dump(data)                 # -> String. Cannot fail.
YAMLParser.dump_to_file(data, path)   # -> Error. Creates the directory if it does not exist.
```

### Errors

A parse can detect some errors (not all, see spec test below)

#### error examples:
 - a mapping line with no `key: value` separator
 - a duplicate key
 - tab indentation
 - an unterminated flow collection or quoted

When an error occurs `parse()` returns `ERR_PARSE_ERROR` and `data` is `null`.

`errors` holds **all** of errors so a file with three typos reports three.

## Note on Godot ScriptEditor

The built in editor is setup to convert indentation to tabs by default, this will break your files.

Disable the setting or Use an external editor with "tabs to spaces” enabled.


## Anchors, aliases and merge keys

Anchors (`&name`), aliases (`*name`) and merge keys (`<<:`) are supported, in both block and
flow context.

```yaml
defaults: &defaults
  retries: 3
  timeout: 30

service:
  <<: *defaults      # pull in every key of `defaults`
  timeout: 60        # ...but a key written here wins over a merged one
```

- An **alias resolves to the same object** its anchor labelled -- not a copy. Since Godot
  Dictionaries and Arrays are reference types, mutating the data reached through one alias
  mutates every use of that anchor. Treat parsed anchored nodes as shared.
- A **merge key** (`<<:`) takes a single mapping (`<<: *a`) or a sequence of them
  (`<<: [*a, *b]`). A key the mapping defines explicitly always wins over a merged one, and
  among merged sources the earlier one wins. The `<<` key itself never appears in the result.
- An **unknown alias** (no matching anchor) is a parse error, as is a merge whose source is not
  a mapping. Anchors are scoped to a single document -- an alias cannot reach an anchor defined
  in an earlier `---` document.
- **Recursive anchors** are not supported: an anchor is registered only after its node finishes
  parsing, so a self-reference (`&a [*a]`) surfaces as an unknown alias rather than a cycle.
- `dump` does not emit anchors; it writes each node out in full.


## Tags

A tag (`!Vector2`, `!!str`) is a node property that turns the parsed value into a typed object.
The node's value is parsed as usual, then a **constructor** for the tag builds the result.

```yaml
spawn: !Vector2 [100, 250]
tint:  !Color "ff8800"
speed: !!str 60          # the string "60", not the int
```

```gdscript
var settings = YAMLParser.new()
settings.parse_file("res://config/level.yaml")
settings.data.spawn   # Vector2(100, 250)
```

**Built-in tags** need no setup:

- **Core schema**: `!!str`, `!!int`, `!!float`, `!!bool`, `!!null` (override implicit typing),
  and `!!seq` / `!!map` (assert a node's shape).
- **Godot types** — vectors (`!Vector2`/`!Vector2i`/`!Vector3`/`!Vector3i`/`!Vector4`/`!Vector4i`),
  `!Color` (from `[r,g,b(,a)]` or a hex string like `"ff8800"`), `!Rect2`/`!Rect2i`,
  `!Quaternion`, `!Plane`, `!AABB`, `!Basis`, `!Transform2D`/`!Transform3D`, `!Projection`,
  `!StringName`, `!NodePath`, and the packed arrays (`!PackedInt32Array`, `!PackedStringArray`,
  `!PackedVector2Array`, `!PackedColorArray`, …). Numeric types take a flat `[...]` sequence;
  matrix and packed-vector types take a sequence of rows.

**Custom tags** — register a `tag -> Callable` before parsing. The Callable receives the parsed
value and returns the object; a registered entry also overrides a built-in of the same name.

```gdscript
var p = YAMLParser.new()
p.tag_constructors = { "!Deg": func(v): return deg_to_rad(v) }
p.parse("turn: !Deg 90")            # -> { "turn": 1.5708... }
```

- `tag_constructors` is **configuration, not parse state** — set it once and reuse the parser.
- An **unknown tag** (not built-in, not registered), or a tag whose value has the wrong shape
  (`!Vector2 [1]`), is a parse error.
- Node properties combine: `&anchor !Vector2 [1,2]` (either order) anchors the *constructed*
  value, so an alias to it yields the same typed object.
- `dump` does **not** emit tags — this is a one-way (read) conversion; a `Vector2` in a dumped
  tree would not round-trip.


## Limitations

- `%TAG` directive-defined shorthand handles (`!e!type`) and verbatim `!<uri>` tags are not
  resolved; only the literal `!` (local) and `!!` (core-schema) handles work. Directives
  (`%YAML`, `%TAG`) are otherwise recognised and ignored.
- A quote or bracket appearing part way through a plain scalar is treated as if it opened one, so a
  key like `bla"keks` is not read correctly.
- Errors inside a flow collection (a missing or doubled comma) are not detected. Only the
  collection's *delimiters* are checked.
- A flow mapping's keys are typed, so `{1: a}` has an **int** key, but `dump` writes `1: a`, which
  reads back as the **string** `"1"`. Non-string keys in flow mappings do not round-trip.

## Tests

```sh
godot --headless --script res://tests/ci_test.gd    # exits 0 on pass, 1 on failure
```

Suites live in `tests/suites/`; `tests/autorun/` is scanned automatically for `YAMLTest`
subclasses. CI runs the same entry point.

### YAML Spec Tests

The parser can also be scored against
[yaml-test-suite](https://github.com/yaml/yaml-test-suite). This is a report, not a gate: it always
exits 0, and CI does not run it.

```sh
python3 tests/yaml_test_suite/gen_suite.py     # build the test files (once)
godot --headless --script res://tests/yaml_test_suite/conformance_test.gd
```

It reports two numbers. 
 - **Correctness:** Currently 246/279 of tests that have a JSON target pass. The fails are mostly
   directive/`%TAG`-shorthand cases and a few exotic node-property placements (such as an anchor
   on a mapping key).
 - **Strictness:** of the 94 documents the suite says must be *rejected*, it rejects **39**. So there is the potential for malformed content to pass by undetected.

## Origin

Started as a fork of [YAML.gd](https://github.com/lowlevel-1989/YAML.gd) by Vinicio Valbuena. The
parser has diverged from origin and the API is no longer compatible.

MIT License, with
the original copyright retained.

If the original was useful to you, you can support its author:

[!["Buy Me A Coffee"](coffee.png)](https://ko-fi.com/lowlevel1989)
