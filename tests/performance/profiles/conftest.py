"""Codec-only runtime: performance samples do not initialize frames or trackers."""
import importlib

import pytest

from tests.lua_runtime import ROOT


@pytest.fixture
def codec_runtime(lua_runtime_name):
    lua = importlib.import_module(f"lupa.{lua_runtime_name}").LuaRuntime(
        unpack_returned_tuples=True
    )
    ns = lua.eval("{ Kit = {}, CLASS_BLESSING = {} }")
    ns.ClassDefaults = lua.eval(
        "function() return { cd = {}, buff = {}, self = {}, ally = {} } end"
    )
    loader = lua.eval(
        "function(source, name, ns) assert(loadstring(source, '@' .. name))('CodecTests', ns) end"
    )
    for file in ("ProfileValidation.lua", "ProfileCodec.lua"):
        loader((ROOT / file).read_text(encoding="utf-8"), file, ns)
    measure = lua.eval("""function(operation, value, repeats)
        collectgarbage('collect')
        collectgarbage('stop')
        local before, start = collectgarbage('count'), os.clock()
        for _ = 1, repeats do operation(value) end
        local seconds = os.clock() - start
        local allocated = collectgarbage('count') - before
        collectgarbage('restart')
        return seconds / repeats, allocated / repeats
    end""")
    return lua, ns, measure
