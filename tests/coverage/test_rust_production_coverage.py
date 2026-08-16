"""Unit tests for scripts/rust-production-coverage.py.

Run with:  python -m unittest discover -s tests/coverage
"""

import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[2] / "scripts" / "rust-production-coverage.py"
spec = importlib.util.spec_from_file_location("rust_production_coverage", SCRIPT)
rpc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(rpc)


def write_rs(directory: Path, name: str, source: str) -> str:
    path = directory / name
    path.write_text(source, encoding="utf-8")
    return str(path)


class FindTestRangesTests(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.dir = Path(self._tmp.name)

    def ranges(self, source: str):
        path = write_rs(self.dir, "sample.rs", source)
        return rpc.find_test_ranges(path)

    def test_whole_tests_module_is_one_range(self):
        source = "\n".join(
            [
                "pub fn production_a() {}",
                "",
                "#[cfg(test)]",
                "mod tests {",
                "    #[test]",
                "    fn t() {}",
                "}",
                "",
                "pub fn production_b() {}",
            ]
        )
        # The module span covers the attribute line through the closing brace.
        self.assertEqual(self.ranges(source), [(3, 7)])

    def test_individual_cfg_test_helper(self):
        source = "\n".join(
            [
                "pub fn visible() {}",
                "",
                "#[cfg(test)]",
                "fn fixture() -> u32 { 7 }",
                "",
                "pub fn other() {}",
            ]
        )
        self.assertEqual(self.ranges(source), [(3, 4)])

    def test_production_before_and_after_is_kept(self):
        source = "\n".join(
            [
                "fn first() {}",
                "#[cfg(test)]",
                "mod tests { fn inner() {} }",
                "fn last() {}",
            ]
        )
        ranges = self.ranges(source)
        self.assertEqual(len(ranges), 1)
        start, end = ranges[0]
        self.assertLess(start, 4)
        self.assertGreaterEqual(end, 3)

    def test_nested_braces_do_not_close_the_module_early(self):
        source = "\n".join(
            [
                "#[cfg(test)]",
                "mod tests {",
                "    struct S { inner: Vec<String> }",
                "    fn make() -> S {",
                "        let closure = |v: u8| { v + 1 };",
                '        S { inner: vec![format!("{}", closure(1))] }',
                "    }",
                "}",
                "pub fn real() {}",
            ]
        )
        self.assertEqual(self.ranges(source), [(1, 8)])

    def test_braces_inside_comments_are_ignored(self):
        source = "\n".join(
            [
                "pub fn a() {} // } unbalanced in line comment",
                "/* { } /* nested comment braces */ */",
                "#[cfg(test)]",
                "mod tests {",
                "    // } fake close",
                "    /* } */ fn t() {}",
                "}",
            ]
        )
        self.assertEqual(self.ranges(source), [(3, 7)])

    def test_braces_inside_strings_are_ignored(self):
        source = "\n".join(
            [
                "#[cfg(test)]",
                "mod tests {",
                "    fn t() {",
                '        let s = "}{ \\" {";',
                "        let c = '{';",
                "    }",
                "}",
            ]
        )
        self.assertEqual(self.ranges(source), [(1, 7)])

    def test_braces_inside_raw_strings_are_ignored(self):
        source = "\n".join(
            [
                "#[cfg(test)]",
                "mod tests {",
                "    fn t() {",
                '        let raw = r#"{ " } "#;',
                '        let raw2 = r##"#" { "##;',
                "    }",
                "}",
            ]
        )
        self.assertEqual(self.ranges(source), [(1, 7)])

    def test_multiple_test_only_items(self):
        source = "\n".join(
            [
                "#[cfg(test)]",
                "fn helper_one() {}",
                "",
                "pub fn production() {}",
                "",
                "#[cfg(test)]",
                "mod more_tests {",
                "    fn inner() {}",
                "}",
            ]
        )
        self.assertEqual(self.ranges(source), [(1, 2), (6, 9)])

    def test_malformed_unbalanced_module_fails_closed(self):
        source = "#[cfg(test)]\nmod tests {\n    fn broken() {\n"
        with self.assertRaises(rpc.SourceError):
            self.ranges(source)

    def test_malformed_unterminated_string_fails_closed(self):
        source = '#[cfg(test)]\nmod tests { fn s() { let x = "unterminated; } }\n'
        with self.assertRaises(rpc.SourceError):
            self.ranges(source)


def make_export(functions):
    """functions: list of (name, count, filename, [(sl, sc, el, ec, count)])"""
    return {
        "data": [
            {
                "functions": [
                    {
                        "name": name,
                        "count": count,
                        "filenames": [filename],
                        "regions": [
                            [sl, sc, el, ec, cnt, 0, 0, 0]
                            for (sl, sc, el, ec, cnt) in regions
                        ],
                    }
                    for (name, count, filename, regions) in functions
                ]
            }
        ]
    }


class AnalyzeTests(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.dir = Path(self._tmp.name)

    def test_cfg_test_items_are_excluded_from_metrics(self):
        path = write_rs(
            self.dir,
            "a.rs",
            "\n".join(
                [
                    "pub fn production() {}",  # line 1
                    "#[cfg(test)]",
                    "mod tests {",
                    "    fn t() {}",  # line 4: test-only
                    "}",
                ]
            ),
        )
        export = make_export(
            [
                ("prod", 1, path, [(1, 1, 1, 26, 1)]),
                ("test_t", 1, path, [(4, 5, 4, 14, 1)]),
            ]
        )
        report = rpc.analyze(export)
        totals = report["totals"]
        # Only the production function's 1 line / 1 region counts.
        self.assertEqual(totals["lines"], [1, 1])
        self.assertEqual(totals["regions"], [1, 1])
        self.assertEqual(totals["functions"], [1, 1])

    def test_uncovered_production_stays_in_the_denominator(self):
        path = write_rs(self.dir, "a.rs", "pub fn production() {}\n")
        export = make_export([("prod", 0, path, [(1, 1, 1, 26, 0)])])
        totals = rpc.analyze(export)["totals"]
        self.assertEqual(totals["lines"], [0, 1])
        self.assertEqual(totals["regions"], [0, 1])

    def test_same_source_duplicate_functions_are_deduplicated(self):
        path = write_rs(self.dir, "a.rs", "pub fn production() {}\n")
        # Same function compiled into the lib (dev_nav) and bin (dev) crates:
        # different manglings, identical normalized name and regions.
        export = make_export(
            [
                ("Csaaaaaaaaaaa_1dev_nav3foo", 1, path, [(1, 1, 1, 26, 1)]),
                ("Csaaaaaaaaaaa_1dev3foo", 1, path, [(1, 1, 1, 26, 1)]),
            ]
        )
        totals = rpc.analyze(export)["totals"]
        self.assertEqual(totals["functions"], [1, 1])
        self.assertEqual(totals["lines"], [1, 1])

    def test_generic_instantiations_collapse_to_one_function(self):
        path = write_rs(
            self.dir,
            "a.rs",
            "pub fn generic<T>(x: T) -> T { x }\n",
        )
        export = make_export(
            [
                ("Csabc12345678_dev_navINtT_generic", 1, path, [(1, 1, 1, 33, 1)]),
                ("Csabc12345678_dev_navINtU_generic", 0, path, [(1, 1, 1, 33, 0)]),
            ]
        )
        totals = rpc.analyze(export)["totals"]
        self.assertEqual(totals["functions"], [1, 1])


class MainThresholdTests(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.dir = Path(self._tmp.name)
        self.rs = write_rs(self.dir, "a.rs", "pub fn production() {}\n")
        # 1 covered line out of 2 total -> 50%.
        self.export = make_export(
            [
                ("covered", 1, self.rs, [(1, 1, 1, 26, 1)]),
                ("missed", 0, self.rs, [(2, 1, 2, 26, 0)]),
            ]
        )
        self.export_path = self.dir / "export.json"
        self.export_path.write_text(json.dumps(self.export), encoding="utf-8")

    def run_main(self, *extra):
        argv = [str(self.export_path), *extra]
        code = rpc.main(argv)
        return code

    def test_threshold_pass_returns_zero(self):
        self.assertEqual(self.run_main("--threshold", "40"), 0)

    def test_threshold_fail_returns_one(self):
        self.assertEqual(self.run_main("--threshold", "99"), 1)

    def test_default_threshold_is_eighty(self):
        # 50% < 80% default -> failure.
        self.assertEqual(self.run_main(), 1)

    def test_ambiguous_source_fails_closed_with_two(self):
        bad_rs = write_rs(self.dir, "bad.rs", "#[cfg(test)]\nmod tests {\n")
        export = make_export([("f", 1, bad_rs, [(1, 1, 1, 10, 1)])])
        path = self.dir / "bad-export.json"
        path.write_text(json.dumps(export), encoding="utf-8")
        code = rpc.main([str(path), "--threshold", "10"])
        self.assertEqual(code, 2)


if __name__ == "__main__":
    unittest.main()
