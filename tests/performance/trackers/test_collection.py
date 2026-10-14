"""Deterministic API-call budgets with observational time and heap measurements."""
import pytest

from tests.lua_runtime import to_python

SCENARIOS = (
    "cooldown refresh",
    "20-event cooldown burst",
    "player full aura event",
    "two-second safety refresh",
    "cooldown text color",
    "cooldown preview draw",
)
COLLECTION_CALLS = ("spell", "known", "bagSlots", "bagItem")


@pytest.mark.parametrize(
    "scenario_index", [pytest.param(index, id=name) for index, name in enumerate(SCENARIOS, 1)]
)
def test_collection_budget(lua_harness, scenario_index, record_performance):
    measure = lua_harness.load("tests/performance/trackers/workloads.lua")
    result = to_python(measure(scenario_index))
    record_performance(**result)
    calls = result["calls"]
    assert all(calls.get(key, 0) == 0 for key in COLLECTION_CALLS)
    expected_cooldowns = {1: 800, 2: 100}
    expected_auras = {3: 2100, 4: 10500}
    assert calls.get("cooldown", 0) == expected_cooldowns.get(scenario_index, 0)
    assert calls.get("aura", 0) == expected_auras.get(scenario_index, 0)
    if scenario_index == 2:
        assert calls.get("itemCooldown", 0) == 0
        assert calls.get("layout", 0) == 0
