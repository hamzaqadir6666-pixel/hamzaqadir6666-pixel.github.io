"""Cross-platform tests for the Animator's bookkeeping (the parts
that don't need Windows): per-kind de-duplication."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from macwin.animator import Animator  # noqa: E402
from macwin.config import Config  # noqa: E402


def _animator():
    return Animator(lambda: Config())


def test_duplicate_minimize_claims_blocked():
    a = _animator()
    assert a._claim(123, "min") is True
    assert a._claim(123, "min") is False     # same kind, still running
    a._release(123, "min")
    assert a._claim(123, "min") is False     # inside the 0.9s dedupe window


def test_minimize_then_quick_restore_not_blocked():
    """Regression: restore claims used to share the minimize dedupe key,
    so a fast minimize->restore could eat the restore animation."""
    a = _animator()
    assert a._claim(456, "min") is True
    assert a._claim(456, "res") is True
    a._release(456, "min")
    a._release(456, "res")


def test_different_windows_independent():
    a = _animator()
    assert a._claim(1, "min") is True
    assert a._claim(2, "min") is True
