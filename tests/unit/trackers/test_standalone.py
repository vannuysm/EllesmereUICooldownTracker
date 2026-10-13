"""Behavior without the optional EllesmereUI adapter."""
import pytest

from tests.lua_runtime import LuaHarness

pytestmark = pytest.mark.regression


def test_standalone(lua_runtime_name):
    harness = LuaHarness.create(lua_runtime_name, standalone=True)
    harness.run_case(
        "tests/unit/trackers/standalone_cases.lua",
        "standalone controls, cooldowns, buffs and reminders",
    )
