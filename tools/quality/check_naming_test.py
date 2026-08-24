#!/usr/bin/env python3
import tempfile
import unittest
from pathlib import Path

from check_naming import check


class NamingCheckTest(unittest.TestCase):
    def test_accepts_project_style_names(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "src" / "demo"
            source.mkdir(parents=True)
            (source / "valid_name.mbt").write_text(
                "const MAX_ITEMS : Int = 1\nfn valid_name() -> Unit { () }\n",
                encoding="utf-8",
            )
            self.assertEqual(check(root), [])

    def test_reports_file_function_and_constant_names(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "src" / "demo"
            source.mkdir(parents=True)
            (source / "BadName.mbt").write_text(
                "const badValue : Int = 1\nfn BadFunction() -> Unit { () }\n",
                encoding="utf-8",
            )
            errors = check(root)
            self.assertEqual(len(errors), 3)
            self.assertTrue(any("file name" in error for error in errors))
            self.assertTrue(any("function" in error for error in errors))
            self.assertTrue(any("constant" in error for error in errors))


if __name__ == "__main__":
    unittest.main()
