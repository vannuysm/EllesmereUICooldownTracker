local ctx = ...
local M, ns, Test = ctx.mocks, ctx.ns, ctx.Test
local H = dofile(ctx.path("tests/unit/profiles/support.lua"))(ctx)
local V, Kit, Equal, Copy, Read = H.V, H.Kit, H.Equal, H.Copy, H.Read
local ErrorContains, Bad, BadText = H.ErrorContains, H.Bad, H.BadText

Test("every explicit empty list survives normalization, application and late saved-data initialization", function()
    local empty = { cd = { spells = {} }, buff = { spells = {} }, remind = { self = {}, ally = {} }, ranks = { keep = {} } }
    local decoded = assert(ns.ProfileCodec.Decode("FCT1:" .. Kit.Encode({ data = empty })))
    assert(ns.Profiles.Apply(decoded.data))
    M.Fire("PLAYER_LOGIN")
    for _, pair in ipairs({ { "cd", "spells" }, { "buff", "spells" }, { "remind", "self" }, { "remind", "ally" }, { "ranks", "keep" } }) do
        assert(next(EUICT_DBC[pair[1]][pair[2]]) == nil)
    end
    assert(EUICT_DBC.cd.items2)
end)
Test("missing fields use class defaults rather than the current profile", function()
    EUICT_DBC.cd.size = 70
    local normalized = assert(V.Validate({ cd = { enabled = false } }))
    assert(normalized.cd.size == 36 and normalized.cd.spells[1] == ns.Defaults.ForPlayer().cd[1])
    assert(not normalized.cd.enabled)
end)
Test("unknown and storage fields are discarded; class badges remain separate", function()
    local candidate = assert(V.Validate({ _class = "MAGE", future = { option = true },
        x = 1, editLayouts = {}, _owner = "another", _savedAt = 99, profiles = { malicious = {} }, icons = {}, items2 = false,
        cd = { x = 999, y = 999, future = false, _owner = "other", items2 = false, profiles = {} },
        buff = { color = { r = 0.2, g = 0.3, b = 0.4, future = true } } }))
    assert(candidate.future == nil and candidate.cd.future == nil and candidate.cd.x == nil)
    assert(candidate._class == "MAGE" and candidate.buff.color.a == 1 and candidate.buff.color.future == nil)
    local owner, x, y = EUICT_DBC._owner, EUICT_DBC.cd.x, EUICT_DBC.cd.y
    assert(ns.Profiles.Apply(candidate))
    assert(EUICT_DBC._owner == owner and EUICT_DBC.cd.x == x and EUICT_DBC.cd.y == y and EUICT_DBC._class == nil)
end)
for _, section in ipairs({ "cd", "buff", "remind", "ranks" }) do
    for _, value in ipairs({ 1, false, "wrong" }) do
        Test("wrong section type " .. section .. "/" .. tostring(value), function() Bad({ [section] = value }, section) end)
    end
end
Test("wrong root type", function()
    for _, value in ipairs({ 1, false, "bad" }) do
        local candidate, err = V.Validate(value); assert(not candidate); ErrorContains(err, "profile")
        local before = Kit.Encode(EUICT_DBC)
        local ok; ok, err = ns.Profiles.Apply(value); assert(not ok); ErrorContains(err, "profile")
        assert(before == Kit.Encode(EUICT_DBC))
    end
end)
for _, pair in ipairs({ { "cd", "spells" }, { "buff", "spells" }, { "remind", "self" }, { "remind", "ally" }, { "ranks", "keep" } }) do
    Test("list types and density " .. pair[1] .. "." .. pair[2], function()
        local section, field = pair[1], pair[2]
        for _, value in ipairs({ 1, false, "spell", { "ok", 7 }, { "ok", false }, { [2] = "hole" }, { [0] = "zero" }, { named = "entry" } }) do
            -- Sparse tables cannot always be re-encoded by the original encoder; compare their source directly.
            if type(value) == "table" and value[2] == "hole" then
                local input = { [section] = { [field] = value } }
                local before = Kit.Encode(EUICT_DBC)
                local candidate, err = V.Validate(input); assert(not candidate); ErrorContains(err, section .. "." .. field)
                assert(not ns.Profiles.Apply(input) and before == Kit.Encode(EUICT_DBC) and value[2] == "hole")
            else Bad({ [section] = { [field] = value } }, section .. "." .. field) end
        end
    end)
end
for section, fields in pairs({ cd = { "enabled", "locked", "numbers", "rangeDim", "readyGlow", "borderEnabled" },
    buff = { "enabled", "locked", "showIcon", "showName", "showTime", "borderEnabled" },
    remind = { "enabled", "locked", "party", "target", "borderEnabled" }, ranks = { "enabled", "auto" } }) do
    for _, field in ipairs(fields) do
        Test("boolean " .. section .. "." .. field, function()
            Bad({ [section] = { [field] = 1 } }, section .. "." .. field)
            assert(V.Validate({ [section] = { [field] = false } })[section][field] == false)
        end)
    end
end
for section, fields in pairs({ cd = { size = {16,80}, gap = {0,30}, fontSize = {0,32}, borderSize = {1,8} },
    buff = { width = {80,600}, height = {12,64}, gap = {0,30}, fontSize = {8,32}, timeFontSize = {8,32}, borderSize = {1,8} },
    remind = { size = {12,64}, gap = {0,30}, fontSize = {0,32}, borderSize = {1,8} } }) do
    for field, bounds in pairs(fields) do
        Test("numeric bounds " .. section .. "." .. field, function()
            for _, value in ipairs({ bounds[1] - 0.1, bounds[2] + 0.1, "12", math.huge, -math.huge }) do
                Bad({ [section] = { [field] = value } }, section .. "." .. field)
            end
            local candidate, err = V.Validate({ [section] = { [field] = 0/0 } }); assert(not candidate); ErrorContains(err, section .. "." .. field)
            assert(V.Validate({ [section] = { [field] = bounds[1] } }))
            assert(V.Validate({ [section] = { [field] = bounds[2] } }))
        end)
    end
end
-- The cases below exercise the real UI callbacks as well as the read-only validator.
for section, fields in pairs({ cd = { "orientation", "growth", "visibility", "inheritBar" },
    buff = { "orientation", "growth", "visibility", "inheritBar" }, remind = { "inheritBar" } }) do
    for _, field in ipairs(fields) do
        Test("enum " .. section .. "." .. field, function() Bad({ [section] = { [field] = "invalid" } }, section .. "." .. field) end)
    end
end
for _, section in ipairs({ "cd", "buff" }) do
    Test("orientation/growth agreement " .. section, function()
        Bad({ [section] = { orientation = "horizontal", growth = "up" } }, section .. ".growth")
        Bad({ [section] = { orientation = "vertical", growth = "left" } }, section .. ".growth")
        assert(V.Validate({ [section] = { orientation = "vertical" } })[section].growth == "down")
        for _, growth in ipairs({ "up", "down" }) do assert(V.Validate({ [section] = { orientation = "vertical", growth = growth } })) end
        for _, growth in ipairs({ "left", "right" }) do assert(V.Validate({ [section] = { orientation = "horizontal", growth = growth } })) end
    end)
end
for section, fields in pairs({ cd = { "textColor", "borderColor" }, buff = { "color", "background", "textColor", "borderColor" },
    remind = { "textColor", "borderColor" } }) do
    for _, field in ipairs(fields) do
        Test("color " .. section .. "." .. field, function()
            for _, value in ipairs({ 1, false, "red", {}, { 1, 1, 1 }, { r = "1", g = 0, b = 0 },
                { r = 1.1, g = 0, b = 0 }, { r = 0, g = -1, b = 0 }, { r = 0, g = 0, b = math.huge },
                { r = 0, g = 0, b = 0, a = false }, { r = 0, g = 0, b = 0, a = 2 } }) do
                Bad({ [section] = { [field] = value } }, section .. "." .. field)
            end
            local c = assert(V.Validate({ [section] = { [field] = { r = 1, g = 0, b = 0, a = 0 } } }))
            assert(c[section][field].a == 0)
        end)
    end
end
Test("class mappings and badge metadata", function()
    Bad({ remind = { byClass = 1 } }, "remind.byClass")
    Bad({ remind = { byClass = { NOTACLASS = "Buff" } } }, "remind.byClass")
    Bad({ remind = { byClass = { MAGE = false } } }, "remind.byClass.MAGE")
    Bad({ remind = { byClass = { MAGE = {} } } }, "remind.byClass.MAGE")
    Bad({ remind = { byClass = { MAGE = "  " } } }, "remind.byClass.MAGE")
    Bad({ _class = "notaclass" }, "_class")
    Bad({ _class = 7 }, "_class")
    local candidate = assert(V.Validate({ _class = "EVOKER", remind = { byClass = { MAGE = "", EVOKER = "A / B" } } }))
    assert(candidate.remind.byClass.MAGE == "" and candidate.remind.byClass.EVOKER == "A / B")
end)
Test("bounded non-empty text", function()
    Bad({ buff = { texture = 1 } }, "buff.texture")
    Bad({ cd = { spells = { "" } } }, "cd.spells[1]")
    Bad({ cd = { spells = { "  " } } }, "cd.spells[1]")
    Bad({ cd = { spells = { "x\n" } } }, "cd.spells[1]")
    Bad({ cd = { spells = { string.rep("x", V.Limits.text + 1) } } }, "cd.spells[1]")
    assert(V.Validate({ buff = { texture = "catalog-key-from-another-install" }, cd = { spells = { "Nature's Swiftness", "Éclair" } } }))
end)
Test("direct inputs with metatables, cycles and secret values fail without mutation", function()
    local before, library = Kit.Encode(EUICT_DBC), Kit.Encode(EUICT_DB.profiles)
    local cyclic = {}; cyclic.future = cyclic
    for _, value in ipairs({ cyclic, setmetatable({}, {}), { future = function() end } }) do assert(not ns.Profiles.Apply(value)) end
    local old = issecretvalue
    issecretvalue = function(value) return value == "secret-profile-value" end
    local ok, err = ns.Profiles.Apply({ cd = { spells = { "secret-profile-value" } } }); assert(not ok); ErrorContains(err, "secret")
    issecretvalue = old
    assert(Kit.Encode(EUICT_DBC) == before and Kit.Encode(EUICT_DB.profiles) == library)
end)
Test("direct and saved data respect aggregate text and nesting limits", function()
    local deep = {}; local cursor = deep
    for _ = 1, V.Limits.depth + 1 do cursor.future = {}; cursor = cursor.future end
    Bad(deep, "nesting")
    Bad({ future = { string.rep("x", V.Limits.input / 2), string.rep("x", V.Limits.input / 2) } }, "total text")
end)
