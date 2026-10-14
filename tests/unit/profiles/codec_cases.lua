local ctx = ...
local M, ns, Test = ctx.mocks, ctx.ns, ctx.Test
local H = dofile(ctx.path("tests/unit/profiles/support.lua"))(ctx)
local V, Kit, Equal, Copy, Read = H.V, H.Kit, H.Equal, H.Copy, H.Read
local ErrorContains, Bad, BadText = H.ErrorContains, H.Bad, H.BadText

Test("current default snapshot round trip", function()
    local snapshot = assert(ns.SnapshotProfile())
    local raw = "FCT1:" .. Kit.Encode({ name = "Current", data = snapshot })
    local decoded = assert(ns.DecodeProfile(raw))
    Equal(decoded.data, snapshot)
    assert(snapshot._class == "PALADIN" and snapshot.cd.items2 == nil)
end)
for _, class in ipairs({ "hunter", "paladin" }) do
    Test("legacy profile fixture re-export: " .. class, function()
        local decoded = assert(ns.DecodeProfile(Read("tests/unit/profiles/fixtures/legacy-" .. class .. ".fct1")))
        assert(decoded.data._class == class:upper())
        assert(decoded.data.cd.visibility == "target") -- absent in the captured legacy profiles
        assert(decoded.data.buff.texture == "atrocity") -- portable external texture identifier
        local again = assert(ns.DecodeProfile("FCT1:" .. Kit.Encode(decoded)))
        Equal(again, decoded)
        assert(ns.ApplyProfile(decoded.data))
    end)
end
Test("constructed legacy profile without fork fields", function()
    local data = { cd = { spells = { "Judgement", "Healthstone" }, size = 28, gap = 2, numbers = true, locked = true },
        buff = { spells = { "Seal of" }, width = 240, height = 20, gap = 4, locked = true },
        remind = { self = {}, ally = {}, enabled = false }, ranks = { keep = {} } }
    local original = Copy(data)
    local decoded = assert(ns.DecodeProfile("FCT1:" .. Kit.Encode({ name = "Old", data = data })))
    assert(decoded.data.buff.orientation == "vertical" and decoded.data.buff.growth == "down")
    assert(decoded.data.cd.rangeDim and decoded.data.buff.showTime)
    Equal(data, original)
    assert(ns.ApplyProfile(decoded.data))
end)
Test("malformed import reports the field", function()
    BadText('FCT1:{name="Broken",data={cd={spells=1}}}', "cd.spells")
    BadText('FCT1:{data={cd={spells={[2]="Hole"}}}}', "cd.spells")
    BadText('FCT1:{data={cd={size=1e999}}}', "cd.size")
    BadText('FCT1:{data=1}', "data")
    BadText('FCT1:false', "profile")
    BadText('OTHER:{data={}}', "FCT1")
    BadText('FCT1:{name=1,data={}}', "name")
    BadText('FCT1:{name="' .. string.rep("x", V.Limits.name + 1) .. '",data={}}', "name")
end)
Test("complete parse and legacy literal syntax", function()
    for _, suffix in ipairs({ "junk", "{}", ";", "-- comment", " print(1)" }) do BadText('FCT1:{data={}}' .. suffix, "trailing garbage") end
    local parsed = assert(ns.DecodeProfile(" \nFCT1:{name='Old'; data={cd={spells={'Nature\\'s Swiftness',},};};} \t\r\n"))
    assert(parsed.data.cd.spells[1] == "Nature's Swiftness")
    BadText('FCT1:{data={},data={}}', "duplicate")
    BadText('FCT1:{data={},[true]=1}', "invalid table key")
    BadText('FCT1:{data={cd={spells={"unfinished}}}}', "unfinished")
    BadText('FCT1:{data={cd={spells={"\\999"}}}}', "escape")
end)
Test("input, nesting and collection limits", function()
    BadText('FCT1:{data={}}' .. string.rep(" ", V.Limits.input), "exceeds")
    BadText('FCT1:{data={future=' .. string.rep("{", V.Limits.depth + 1) .. string.rep("}", V.Limits.depth + 1) .. '}}', "nesting")
    local parts = {}; for i = 1, V.Limits.collection + 1 do parts[i] = "true" end
    BadText('FCT1:{data={future={' .. table.concat(parts, ",") .. '}}}', "collection")
    local large = {}; for i = 1, V.Limits.list + 1 do large[i] = "spell" end
    Bad({ cd = { spells = large } }, "cd.spells")
    large[#large] = nil
    assert(V.Validate({ cd = { spells = large } }))
    local whole = {}; for i = 1, 10 do whole[i] = {}; for j = 1, 450 do whole[i][j] = true end end
    local candidate, err = V.Validate({ future = whole }); assert(not candidate); ErrorContains(err, "collection")
    -- Construct oversized text independently: the public encoder now rejects oversized tables itself.
    local row = "{" .. string.rep("true,", 450) .. "},"
    BadText('FCT1:{data={future={' .. string.rep(row, 10) .. '}}}', "collection")
end)
Test("modified current profile round trip", function()
    ns.SetConfig("cd", "size", 44)
    ns.SetConfig("remind", "party", true)
    local snapshot = assert(ns.SnapshotProfile())
    local decoded = assert(ns.DecodeProfile("FCT1:" .. Kit.Encode({ name = "Current modified", data = snapshot })))
    Equal(decoded.data, snapshot)
end)
Test("encoder guards cycles, depth, collections and repeated shared subtrees", function()
    local cycle = {}; cycle.self = cycle
    local deep, shared = {}, {}
    local cursor = deep
    for _ = 1, V.Limits.depth + 1 do cursor.child = {}; cursor = cursor.child end
    for _ = 1, 9 do shared = { shared, shared, shared } end
    for _, case in ipairs({ { cycle, "cyclic" }, { deep, "nesting" }, { shared, "collection" } }) do
        local ok, err = pcall(Kit.Encode, case[1]); assert(not ok); ErrorContains(err, case[2])
    end
end)
Test("encoder sparse keys cannot trigger a numeric-range loop", function()
    local data = { "first", [2^40] = "far" }
    local raw = Kit.Encode(data)
    assert(#raw < 80)
    local decoded = assert(Kit.Decode(raw))
    assert(decoded[1] == "first" and decoded[2^40] == "far")
end)
Test("quoted text supports both delimiters, escapes and long runs", function()
    local expected = "a'b\"c\\d\n\t\r" .. string.char(65, 255)
    local decoded = assert(Kit.Decode([["a'b\"c\\d\n\t\r\065\255"]]))
    assert(decoded == expected)
    assert(Kit.Decode([['a\'b"c']]) == "a'b\"c")
    local long = string.rep("plain text ", 10000)
    assert(Kit.Decode(Kit.Encode(long)) == long)
    assert(Kit.Decode('"' .. long) == nil)
    assert(Kit.Decode('"trailing\\') == nil)
end)
Test("legacy fixture serialization stays byte-compatible", function()
    for _, class in ipairs({ "hunter", "paladin" }) do
        local raw = Read("tests/unit/profiles/fixtures/legacy-" .. class .. ".fct1"):gsub("%s+$", "")
        local envelope = assert(Kit.Decode(raw:sub(6)))
        assert("FCT1:" .. Kit.Encode(envelope) == raw)
    end
end)
Test("deep and malformed text terminate within an instruction budget", function()
    local cases = { string.rep("{", 10000) .. string.rep("}", 10000),
        "{", "[", "{a=", "{[", "{[1", "{[1]=", "{true,", "{false", "{1e+}", '"\\',
        "{} garbage", "{a=true a=false}", "{a={b={c={d={e={f={g={h={i={j={k={l={m={}}}}}}}}}}}}}}" }
    for _, text in ipairs(cases) do
        -- A test watchdog makes a future non-advancing Lua loop fail, rather than hang the suite.
        debug.sethook(function() error("instruction budget exceeded", 0) end, "", 100000)
        local ok, result, err = pcall(Kit.Decode, text)
        debug.sethook()
        assert(ok, result)
        assert(result == nil and type(err) == "string", "malformed text should fail cleanly")
        assert(not err:find("instruction budget exceeded", 1, true))
    end
end)
Test("export key order is stable across dense, odd-sized and maximum dictionaries", function()
    for _, size in ipairs({ 0, 1, 2, 3, 7, 31, V.Limits.collection }) do
        local data, expected = {}, {}
        for i = size, 1, -1 do
            local key = ("key%04d"):format(i)
            data[key] = true
            expected[i] = key .. "=true"
        end
        assert(Kit.Encode(data) == "{" .. table.concat(expected, ",") .. "}")
    end
end)
