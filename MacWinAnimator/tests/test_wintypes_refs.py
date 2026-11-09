"""Regression test for the v1.0.0 startup crash:
``AttributeError: module 'ctypes.wintypes' has no attribute 'HCURSOR'``.

The Windows-only code is guarded by ``if IS_WINDOWS:`` so it never
executes in cross-platform test runs — but every ``wintypes.X``
reference inside it is evaluated at import time on Windows.  This
test statically collects all such references from the source and
asserts each one really exists in ctypes.wintypes.
"""
import ast
import sys
from ctypes import wintypes
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def _referenced_wintypes_attrs() -> set:
    refs = set()
    sources = [ROOT / "main.py", *sorted((ROOT / "macwin").glob("*.py"))]
    for path in sources:
        tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
        for node in ast.walk(tree):
            if (isinstance(node, ast.Attribute)
                    and isinstance(node.value, ast.Name)
                    and node.value.id in ("wintypes", "_wt")):
                refs.add(node.attr)
    return refs


def test_all_wintypes_references_exist():
    missing = {name for name in _referenced_wintypes_attrs()
               if not hasattr(wintypes, name)}
    assert not missing, (
        f"code references ctypes.wintypes attributes that do not exist: "
        f"{sorted(missing)} — define them locally as ctypes.c_void_p instead")


def test_overlay_defines_handle_types_locally():
    source = (ROOT / "macwin" / "overlay.py").read_text(encoding="utf-8")
    tree = ast.parse(source)
    assigned = {t.id for node in ast.walk(tree)
                if isinstance(node, ast.Assign)
                for t in node.targets if isinstance(t, ast.Name)}
    # handles missing from (some) wintypes builds must be local aliases
    assert {"HICON", "HCURSOR", "HBRUSH"} <= assigned
