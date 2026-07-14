#!/usr/bin/env python3
"""Build suite.json from the official YAML test suite.

    python3 tests/yaml_test_suite/gen_suite.py

Downloads the pinned tag below and folds all 402 cases into a single JSON file that
conformance.gd can read with Godot's built-in JSON class.

The `data` branch layout is used rather than main's `src/*.yaml`, because reading the
latter would require a YAML parser -- the very thing under test. Here every case is a
directory of plain files:

    ===       the test name
    in.yaml   the input
    in.json   the expected value, when one is representable in JSON
    error     present (and empty) when the input MUST fail to parse

Holding the corpus as JSON also keeps it out of reach of the `* text=auto eol=lf` rule
in .gitattributes, which would otherwise rewrite the CR and CRLF that some cases test.
"""

import json
import os
import pathlib
import sys
import tarfile
import tempfile
import urllib.request

TAG = "data-2022-01-17"
URL = f"https://github.com/yaml/yaml-test-suite/archive/refs/tags/{TAG}.tar.gz"
OUT = pathlib.Path(__file__).parent / "suite.json"


def json_stream(text):
    """in.json holds one JSON value per YAML document, concatenated, not an array."""
    decoder = json.JSONDecoder()
    docs = []
    i, n = 0, len(text)
    while i < n:
        while i < n and text[i] in " \t\r\n":
            i += 1
        if i >= n:
            break
        value, i = decoder.raw_decode(text, i)
        docs.append(value)
    return docs


def collect(root):
    cases = []
    for dirpath, _dirnames, filenames in os.walk(root):
        if "in.yaml" not in filenames:
            continue
        d = pathlib.Path(dirpath)
        case = {
            "id": str(d.relative_to(root)),
            "name": (d / "===").read_text(encoding="utf-8").strip()
                    if "===" in filenames else "",
            "yaml": (d / "in.yaml").read_text(encoding="utf-8"),
            "fail": "error" in filenames,
        }
        # Three cases (9MQT/01, DK95/01, DK95/06) ship an in.json *and* an error file,
        # a leftover of how subtests inherit keys from the preceding one. `error` wins,
        # so drop the expectation here rather than leave the runner to break the tie.
        if "in.json" in filenames and not case["fail"]:
            case["json"] = json_stream((d / "in.json").read_text(encoding="utf-8"))
        cases.append(case)
    cases.sort(key=lambda c: c["id"])
    return cases


def main():
    with tempfile.TemporaryDirectory() as tmp:
        tmp = pathlib.Path(tmp)
        archive = tmp / "suite.tar.gz"
        print(f"fetching {TAG} ...")
        urllib.request.urlretrieve(URL, archive)
        with tarfile.open(archive) as tar:
            tar.extractall(tmp)
        root = next(p for p in tmp.iterdir() if p.is_dir())
        cases = collect(root)

    OUT.write_text(json.dumps(cases, ensure_ascii=False), encoding="utf-8")

    failing = sum(1 for c in cases if c["fail"])
    scored = sum(1 for c in cases if "json" in c)
    print(f"wrote {OUT.name}: {len(cases)} cases, {OUT.stat().st_size // 1024} KB")
    print(f"  {scored} with a JSON expectation (scored)")
    print(f"  {failing} must-fail (reported, not scored)")
    print(f"  {len(cases) - scored - failing} with no expectation (skipped)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
