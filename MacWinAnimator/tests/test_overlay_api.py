"""Regression tests for the v1.1.0 self-test failure:
``AttributeError: 'LayeredOverlay' object has no attribute 'pump_messages'``

animator.py called overlay.pump_messages() and read
overlay._ulw_error_logged, but the methods/attributes didn't exist in
overlay.py — and no test noticed.  These AST tests check, on any OS,
that the overlay class actually provides everything the animator
(and capture pipeline) uses.
"""
import ast
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))


def _tree(name):
    return ast.parse((ROOT / "macwin" / name).read_text(encoding="utf-8"))


def _class_methods(tree, class_name):
    for node in ast.walk(tree):
        if isinstance(node, ast.ClassDef) and node.name == class_name:
            return {n.name for n in node.body if isinstance(n, ast.FunctionDef)}
    raise AssertionError(f"class {class_name} not found")


def test_overlay_provides_methods_animator_calls():
    overlay_methods = _class_methods(_tree("overlay.py"), "LayeredOverlay")
    # every overlay.<method> the animator calls must exist
    called = set()
    for node in ast.walk(_tree("animator.py")):
        if (isinstance(node, ast.Attribute)
                and isinstance(node.value, ast.Name)
                and node.value.id == "overlay"):
            called.add(node.attr)
    assert called, "animator should call overlay methods"
    missing = called - overlay_methods - {"hwnd"}
    assert not missing, f"animator calls missing overlay methods: {missing}"
    assert {"show_frame", "pump_messages", "destroy"} <= overlay_methods


def test_overlay_init_sets_error_flag():
    """show_frame reads self._ulw_error_logged — __init__ must set it."""
    tree = _tree("overlay.py")
    for node in ast.walk(tree):
        if isinstance(node, ast.ClassDef) and node.name == "LayeredOverlay":
            for fn in node.body:
                if isinstance(fn, ast.FunctionDef) and fn.name == "__init__":
                    assigned = {t.attr for n in ast.walk(fn)
                                if isinstance(n, ast.Assign)
                                for t in n.targets
                                if isinstance(t, ast.Attribute)
                                and isinstance(t.value, ast.Name)
                                and t.value.id == "self"}
                    assert "_ulw_error_logged" in assigned
                    return
    raise AssertionError("__init__ not found")


def test_capture_detailed_api_exists():
    tree = _tree("capture.py")
    funcs = {n.name for n in ast.walk(tree) if isinstance(n, ast.FunctionDef)}
    assert "capture_window" in funcs
    assert "capture_window_detailed" in funcs
