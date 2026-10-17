return function(ctx)
local ns = ctx.ns
local V, Kit = ns.ProfileValidation, ns.Kit
local function Equal(a, b) assert(Kit.Encode(a) == Kit.Encode(b), "data differs") end
local function Copy(value)
    if type(value) ~= "table" then return value end
    local out = {}; for key, item in pairs(value) do out[key] = Copy(item) end; return out
end
local function Same(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for key, value in pairs(a) do if not Same(value, b[key]) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end
local function Read(path) local f = assert(io.open(ctx.path(path), "rb")); local text = f:read("*a"); f:close(); return text end
local function ErrorContains(err, path) assert(type(err) == "string" and err:find(path, 1, true), tostring(err)) end
local function Bad(data, path)
    local settings, library, source = Kit.Encode(EUICT_DBC), Kit.Encode(EUICT_DB.profiles), Copy(data)
    local candidate, err = V.Validate(data)
    assert(candidate == nil); ErrorContains(err, path)
    local ok; ok, err = ns.Profiles.Apply(data)
    assert(not ok); ErrorContains(err, path)
    assert(Kit.Encode(EUICT_DBC) == settings, "failed application changed settings")
    assert(Kit.Encode(EUICT_DB.profiles) == library, "failed application changed library")
    assert(Same(data, source), "validation changed its input")
end
local function BadText(raw, path)
    local settings, library = Kit.Encode(EUICT_DBC), Kit.Encode(EUICT_DB.profiles)
    local candidate, err = ns.ProfileCodec.Decode(raw)
    assert(candidate == nil); ErrorContains(err, path)
    assert(Kit.Encode(EUICT_DBC) == settings and Kit.Encode(EUICT_DB.profiles) == library)
end

return { V = V, Kit = Kit, Equal = Equal, Copy = Copy, Read = Read,
    ErrorContains = ErrorContains, Bad = Bad, BadText = BadText }
end
