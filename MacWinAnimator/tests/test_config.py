import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from macwin.config import Config  # noqa: E402


def test_roundtrip(tmp_path):
    path = tmp_path / "config.json"
    cfg = Config(effect="scale", duration_ms=700, enabled=False)
    cfg.save(path)
    loaded = Config.load(path)
    assert loaded.effect == "scale"
    assert loaded.duration_ms == 700
    assert loaded.enabled is False


def test_bad_values_are_normalized(tmp_path):
    path = tmp_path / "config.json"
    path.write_text('{"effect": "nope", "duration_ms": 99999, "fps": 1}', encoding="utf-8")
    cfg = Config.load(path)
    assert cfg.effect == "genie"
    assert cfg.duration_ms == 1500
    assert cfg.fps == 24


def test_missing_file_gives_defaults(tmp_path):
    cfg = Config.load(tmp_path / "absent.json")
    assert cfg.effect == "genie" and cfg.enabled is True
