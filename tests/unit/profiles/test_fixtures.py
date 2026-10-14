"""Retained compatibility fixtures contain portable profile data only."""
from pathlib import Path
import re

import pytest

FIXTURES = Path(__file__).with_name("fixtures")
STORAGE_KEYS = {"_owner", "_savedAt", "editLayouts", "profiles", "icons", "x", "y"}


@pytest.mark.parametrize("name", ("legacy-hunter.fct1", "legacy-paladin.fct1"))
def test_legacy_fixture_is_portable(lua_harness, name):
    raw = (FIXTURES / name).read_text(encoding="utf-8")
    assert not re.search(r"[A-Za-z]:[\\/]|/(?:Users|home)/|SavedVariables", raw)
    envelope = lua_harness.context.ns.Kit.Decode(raw.removeprefix("FCT1:"))
    assert set(envelope.keys()) == {"name", "data"}
    data = envelope["data"]
    assert set(data.keys()) == {"_class", "cd", "buff", "remind", "ranks"}
    assert data["_class"] == name.removeprefix("legacy-").removesuffix(".fct1").upper()
    for section in ("cd", "buff", "remind", "ranks"):
        assert STORAGE_KEYS.isdisjoint(data[section].keys())
