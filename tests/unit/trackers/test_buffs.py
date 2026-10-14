"""Buffs regression cases against the real addon."""
import pytest

from tests.lua_runtime import cases_for

CASES = "tests/unit/trackers/buffs_cases.lua"
pytestmark = pytest.mark.regression


@pytest.mark.parametrize("case_name", cases_for(CASES))
def test_buffs(lua_harness, case_name):
    lua_harness.run_case(CASES, case_name)
