-- Configurable profile data only. No UI, serialization, saved-variable ownership or migration here.
local _, ns = ...
local V = {}
ns.ProfileValidation = V
V.Limits = { input = 131072, depth = 12, entries = 4096, collection = 512, list = 256, text = 1024, name = 128 }

local CLASSES = { WARRIOR = true, PALADIN = true, HUNTER = true, ROGUE = true, PRIEST = true,
    DEATHKNIGHT = true, SHAMAN = true, MAGE = true, WARLOCK = true, MONK = true, DRUID = true,
    DEMONHUNTER = true, EVOKER = true }
function V.IsClass(class) return type(class) == "string" and CLASSES[class] == true end

local function Bool(default) return { kind = "boolean", default = default } end
local function Number(default, low, high) return { kind = "number", default = default, low = low, high = high } end
local function Enum(default, values)
    local allowed = {}
    for value in values:gmatch("%S+") do allowed[value] = true end
    return { kind = "enum", default = default, allowed = allowed, choices = values:gsub(" ", ", ") }
end
local function Color(r, g, b, a) return { kind = "color", default = { r = r, g = g, b = b, a = a } } end
local function List() return { kind = "list", default = {} } end
local function Inherit() return Enum("none", "none MainBar Bar2 Bar3 Bar4 Bar5 Bar6 Bar7 Bar8 Bar9 Bar10") end
-- This is the entire allowlist. Unknown fields (including storage and position data) are discarded.
local schema = {
    cd = {
        spells = List(), enabled = Bool(true), numbers = Bool(true), locked = Bool(true),
        size = Number(36, 16, 80), gap = Number(4, 0, 30), fontSize = Number(0, 0, 32),
        orientation = Enum("horizontal", "horizontal vertical"), growth = Enum("right", "right left up down"),
        visibility = Enum("target", "always combat target"), inheritBar = Inherit(),
        rangeDim = Bool(true), readyGlow = Bool(true), textColor = Color(1, 1, 1, 1),
        borderEnabled = Bool(false), borderSize = Number(1, 1, 8), borderColor = Color(0, 0, 0, 1),
    },
    buff = {
        spells = List(), enabled = Bool(true), locked = Bool(true), width = Number(220, 80, 600),
        height = Number(24, 12, 64), gap = Number(4, 0, 30),
        orientation = Enum("vertical", "horizontal vertical"), growth = Enum("down", "right left up down"),
        visibility = Enum("always", "always combat target"), inheritBar = Inherit(),
        -- Texture keys belong to an optional external catalog. Unknown keys use the existing Blizzard fallback.
        texture = { kind = "text", default = "default" },
        color = Color(0.2, 0.5, 0.9, 1), background = Color(0, 0, 0, 0.6),
        borderEnabled = Bool(false), borderSize = Number(1, 1, 8), borderColor = Color(0, 0, 0, 1),
        showIcon = Bool(true), showName = Bool(true), showTime = Bool(true),
        fontSize = Number(12, 8, 32), timeFontSize = Number(12, 8, 32), textColor = Color(1, 1, 1, 1),
    },
    remind = {
        self = List(), ally = List(), byClass = { kind = "classes", default = {} },
        enabled = Bool(true), party = Bool(false), target = Bool(false), locked = Bool(true),
        size = Number(24, 12, 64), gap = Number(4, 0, 30), fontSize = Number(0, 0, 32), inheritBar = Inherit(),
        textColor = Color(1, 0.82, 0, 1), borderEnabled = Bool(false), borderSize = Number(1, 1, 8),
        borderColor = Color(0, 0, 0, 1),
    },
    ranks = { enabled = Bool(true), auto = Bool(false), keep = List() },
}

function V.IsConfigSection(section) return schema[section] ~= nil end
function V.IsConfigField(section, field) return schema[section] ~= nil and schema[section][field] ~= nil end

local function Copy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for key, item in pairs(value) do out[key] = Copy(item) end
    return out
end
function V.Defaults()
    local out = {}
    for section, fields in pairs(schema) do
        out[section] = {}
        for field, rule in pairs(fields) do out[section][field] = Copy(rule.default) end
    end
    local class = ns.ClassDefaults()
    out.cd.spells, out.buff.spells = Copy(class.cd), Copy(class.buff)
    out.remind.self, out.remind.ally = Copy(class.self), Copy(class.ally)
    out.remind.byClass = Copy(ns.CLASS_BLESSING)
    return out
end

local function Fail(path, message) error(path .. ": " .. message, 0) end
local function Finite(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end
local function Text(value, path, empty)
    if type(value) ~= "string" then Fail(path, "expected a string") end
    if #value > V.Limits.text then Fail(path, "text exceeds " .. V.Limits.text .. " bytes") end
    if value:find("%c") then Fail(path, "control characters are not allowed") end
    if not (empty and value == "") and not value:find("%S") then Fail(path, "expected non-empty text") end
    return value
end

function V.ValidateName(name)
    if type(name) ~= "string" or #name > V.Limits.name or name:find("%c") or not name:find("%S") then
        return nil, "name: expected non-empty text of at most " .. V.Limits.name .. " bytes without control characters"
    end
    return name
end

-- Apply the same resource limits to decoded, saved and directly supplied tables, including ignored fields.
function V.CheckStructure(data)
    local active, entries, bytes = {}, 0, 0
    local function CountText(text, path)
        bytes = bytes + #text
        if bytes > V.Limits.input then Fail(path, "total text exceeds " .. V.Limits.input .. " bytes") end
    end
    local function Visit(value, path, depth)
        if issecretvalue and issecretvalue(value) then Fail(path, "secret values are not profile data") end
        local kind = type(value)
        if kind ~= "table" then
            if kind ~= "string" and kind ~= "number" and kind ~= "boolean" then Fail(path, "expected plain data") end
            if kind == "string" then CountText(value, path) end
            return
        end
        if depth > V.Limits.depth then Fail(path, "nesting limit exceeded") end
        if getmetatable(value) ~= nil then Fail(path, "expected a plain table") end
        if active[value] then Fail(path, "cyclic table") end
        active[value] = true
        local count = 0
        for key, item in pairs(value) do
            if (issecretvalue and issecretvalue(key)) or (type(key) ~= "string" and not Finite(key)) then
                Fail(path, "expected string or finite numeric keys")
            end
            count, entries = count + 1, entries + 1
            if count > V.Limits.collection or entries > V.Limits.entries then Fail(path, "collection limit exceeded") end
            if type(key) == "string" then CountText(key, path) end
            Visit(item, path .. "[" .. tostring(key):sub(1, 80) .. "]", depth + 1)
        end
        active[value] = nil
    end
    Visit(data, "profile", 0)
end

local function ValidateField(value, rule, path, default)
    if value == nil then return Copy(default) end
    local kind = rule.kind
    if kind == "boolean" then
        if type(value) ~= "boolean" then Fail(path, "expected a boolean") end
    elseif kind == "number" then
        if not Finite(value) or value < rule.low or value > rule.high then
            Fail(path, "expected a finite number from " .. rule.low .. " to " .. rule.high)
        end
    elseif kind == "enum" then
        if type(value) ~= "string" or not rule.allowed[value] then Fail(path, "expected one of: " .. rule.choices) end
    elseif kind == "text" then return Text(value, path)
    elseif kind == "list" then
        if type(value) ~= "table" then Fail(path, "expected a dense string list") end
        local out, count, highest = {}, 0, 0
        for key, item in pairs(value) do
            if not Finite(key) or key < 1 or key % 1 ~= 0 then Fail(path, "expected consecutive integer keys starting at 1") end
            if key > V.Limits.list then Fail(path, "list exceeds " .. V.Limits.list .. " entries") end
            count, highest = count + 1, math.max(highest, key)
            out[key] = Text(item, path .. "[" .. key .. "]")
        end
        if highest ~= count then Fail(path, "expected a dense list without holes") end
        return out
    elseif kind == "color" then
        if type(value) ~= "table" then Fail(path, "expected an r/g/b color table") end
        local out = {}
        for _, channel in ipairs({ "r", "g", "b", "a" }) do
            local component = value[channel]
            if channel == "a" and component == nil then component = 1 end
            if not Finite(component) or component < 0 or component > 1 then Fail(path .. "." .. channel, "expected a finite number from 0 to 1") end
            out[channel] = component
        end
        return out
    elseif kind == "classes" then
        if type(value) ~= "table" then Fail(path, "expected a class-to-buff table") end
        local out = Copy(default)
        for class, buff in pairs(value) do
            if not V.IsClass(class) then Fail(path, "invalid class key " .. tostring(class)) end
            out[class] = Text(buff, path .. "." .. class, true)
        end
        return out
    end
    return value
end

-- Returns a detached, complete candidate or nil plus a field-specific error. Never mutates its input.
function V.Validate(data)
    local ok, candidate = pcall(function()
        if type(data) ~= "table" then Fail("profile", "expected a table") end
        V.CheckStructure(data)
        local defaults, out = V.Defaults(), {}
        for section, fields in pairs(schema) do
            local source = data[section]
            if source ~= nil and type(source) ~= "table" then Fail(section, "expected a table") end
            source = source or {}
            out[section] = {}
            for field, rule in pairs(fields) do
                out[section][field] = ValidateField(source[field], rule, section .. "." .. field, defaults[section][field])
            end
            if section == "cd" or section == "buff" then
                local c = out[section]
                local vertical = c.orientation == "vertical"
                if source.growth == nil then c.growth = vertical and "down" or "right" end
                if (vertical and c.growth ~= "up" and c.growth ~= "down")
                    or (not vertical and c.growth ~= "left" and c.growth ~= "right") then
                    Fail(section .. ".growth", "incompatible with " .. c.orientation .. " orientation")
                end
            end
        end
        if data._class ~= nil then
            if not V.IsClass(data._class) then Fail("_class", "invalid class metadata") end
            out._class = data._class -- profile badge only; Commit never copies it into character settings
        end
        return out
    end)
    if not ok then return nil, candidate end
    return candidate
end

function V.Snapshot(db, class)
    local data = { _class = class }
    for section, fields in pairs(schema) do
        data[section] = {}
        for field in pairs(fields) do data[section][field] = db[section] and db[section][field] end
    end
    return V.Validate(data)
end

-- Only called with a detached validated candidate. Keep DB and section identities for storage and callbacks.
function V.Commit(db, candidate)
    for section, fields in pairs(schema) do
        db[section] = db[section] or {}
        for field in pairs(fields) do db[section][field] = candidate[section][field] end
    end
    db.cd.items2 = true -- normalized lists already include defaults; never migrate an intentional empty list
end
