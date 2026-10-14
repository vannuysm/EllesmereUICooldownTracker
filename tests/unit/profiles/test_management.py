"""Account profile management and Ellesmere settings interactions."""
import pytest

from tests.lua_runtime import LuaHarness, cases_for

CASES = "tests/unit/profiles/management_cases.lua"


@pytest.mark.parametrize("case_name", cases_for(CASES))
def test_management(lua_harness, case_name):
    lua_harness.run_case(CASES, case_name)


def test_profiles_slash_without_ellesmere(lua_runtime_name):
    harness = LuaHarness.create(lua_runtime_name, standalone=True)
    harness.lua.eval("""function(ctx)
        local opened
        ctx.ns.Kit.Open = function(page) opened = page end
        SlashCmdList.EUICT("profiles")
        assert(opened == ctx.ns.settingsPages.profiles)
        assert(ctx.ns.Profiles.Save("Standalone"))
        ctx.ns.SetConfig("cd", "size", 61)
        assert(EUICT_DB.profiles.Standalone.cd.size == 61)
    end""")(harness.context)
