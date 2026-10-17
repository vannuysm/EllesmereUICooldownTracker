local _, ns = ...
local Kit = ns.Kit
local Codec = {}
ns.ProfileCodec = Codec
local ESCAPES = { n = "\n", t = "\t", r = "\r" }

-- Settings as text that can be pasted into chat or Discord and back: "<tag>:" followed by a Lua-like table literal.
-- Read back with a small parser (never loadstring), so a pasted string can only ever produce plain data.
local function SortKeys(keys)
    -- Bottom-up merge sort: bounded O(k log k) comparisons and no recursive sorting stack.
    -- Keep the original tostring ordering used by FCT1 exports.
    local count, width, source, target = #keys, 1, keys, {}
    while width < count do
        for left = 1, count, 2 * width do
            local middle, last = math.min(left + width, count + 1), math.min(left + 2 * width - 1, count)
            local i, j = left, middle
            for at = left, last do
                if i < middle and (j > last or tostring(source[i]) <= tostring(source[j])) then
                    target[at] = source[i]; i = i + 1
                else target[at] = source[j]; j = j + 1 end
            end
        end
        source, target, width = target, source, width * 2
    end
    return source
end

local function Encode(data)
    -- Guard even direct Kit.Encode calls. CheckStructure caps depth/work and rejects cycles and metatables.
    ns.ProfileValidation.CheckStructure(data)
    local parts = {}
    local function Append(text) parts[#parts + 1] = text end
    local function Write(v)
        local kind = type(v)
        if kind == "string" then Append((("%q"):format(v):gsub("\\\n", "\\n"))); return end
        if kind == "number" or kind == "boolean" then Append(tostring(v)); return end
        Append("{")
        -- Count only the dense prefix. Lua's # is ambiguous for sparse tables and could drive a huge loop.
        local n = 0
        while rawget(v, n + 1) ~= nil do n = n + 1 end
        local first = true
        local function Separator()
            if not first then Append(",") end
            first = false
        end
        for i = 1, n do Separator(); Write(v[i]) end
        local keys = {}
        for key in pairs(v) do
            if not (type(key) == "number" and key >= 1 and key <= n and key % 1 == 0) then keys[#keys + 1] = key end
        end
        keys = SortKeys(keys)
        for _, key in ipairs(keys) do
            Separator()
            if type(key) == "string" and key:match("^[%a_][%w_]*$") then Append(key)
            else Append("["); Write(key); Append("]") end
            Append("="); Write(v[key])
        end
        Append("}")
    end
    -- One shared output buffer avoids repeatedly copying an entire encoded subtree at each ancestor.
    Write(data)
    return table.concat(parts)
end
Kit.Encode = Encode

function Kit.Decode(s)
    local limits = ns.ProfileValidation.Limits
    if type(s) ~= "string" then return nil, "input: expected text" end
    if #s > limits.input then return nil, "input: exceeds " .. limits.input .. " bytes" end
    local pos, entries = 1, 0
    -- Forward-only cursor: each successful value consumes input; table loops consume a value/separator or return.
    -- Anchored token patterns scan only the current token, not a copied suffix or every previous token.
    local function ws() pos = s:find("[^%s]", pos) or #s + 1 end
    local value
    local function str()
        local q = s:sub(pos, pos)
        pos = pos + 1
        local out = {}
        local special = "[\\" .. q .. "]"
        while pos <= #s do
            -- Copy whole unescaped runs, rather than allocating an output slot for each ordinary byte.
            local stop = s:find(special, pos)
            if not stop then error("unfinished text", 0) end
            if stop > pos then out[#out + 1] = s:sub(pos, stop - 1) end
            pos = stop
            if s:sub(pos, pos) == q then pos = pos + 1; return table.concat(out) end
            local nx = s:sub(pos + 1, pos + 1)
            local d = s:match("^%d%d?%d?", pos + 1)
            if d then
                local code = tonumber(d) or 256
                if code > 255 then error("invalid character escape", 0) end
                out[#out + 1] = string.char(code); pos = pos + 1 + #d
            else out[#out + 1] = ESCAPES[nx] or nx; pos = pos + 2 end
        end
        error("unfinished text", 0)
    end
    function value(depth)
        if depth > limits.depth then error("nesting limit exceeded", 0) end
        ws()
        local ch = s:sub(pos, pos)
        if ch == "{" then
            pos = pos + 1
            local t, i, count = {}, 1, 0
            while true do
                ws()
                if s:sub(pos, pos) == "}" then pos = pos + 1; return t end
                local key
                if s:sub(pos, pos) == "[" then
                    pos = pos + 1; key = value(depth + 1); ws()
                    if s:sub(pos, pos) ~= "]" then error("expected ]") end
                    pos = pos + 1; ws()
                    if s:sub(pos, pos) ~= "=" then error("expected =") end
                    pos = pos + 1
                else
                    local name = s:match("^[%a_][%w_]*", pos)
                    if name and name ~= "true" and name ~= "false" and s:match("^%s*=", pos + #name) then
                        key = name
                        pos = s:find("=", pos + #name, true) + 1
                    end
                end
                if key == nil then key = i; i = i + 1 end
                if type(key) ~= "string" and type(key) ~= "number" then error("invalid table key", 0) end
                if type(key) == "number" and (key ~= key or key == math.huge or key == -math.huge) then error("invalid table key", 0) end
                if t[key] ~= nil then error("duplicate table key", 0) end
                count, entries = count + 1, entries + 1
                if count > limits.collection or entries > limits.entries then error("collection limit exceeded", 0) end
                t[key] = value(depth + 1)
                ws()
                local sep = s:sub(pos, pos)
                if sep == "," or sep == ";" then pos = pos + 1
                elseif sep ~= "}" then error("expected , or }") end
            end
        elseif ch == "\"" or ch == "'" then return str()
        elseif s:match("^true", pos) then pos = pos + 4; return true
        elseif s:match("^false", pos) then pos = pos + 5; return false
        else
            local num = s:match("^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
            if num and num ~= "" and tonumber(num) then pos = pos + #num; return tonumber(num) end
            error("unexpected " .. (ch ~= "" and ch or "end"))
        end
    end
    local ok, v = pcall(function()
        local result = value(0)
        ws()
        if pos <= #s then error("trailing garbage at byte " .. pos, 0) end
        return result
    end)
    if not ok then return nil, v end
    return v
end

-- Parsing and normalization are read-only. The caller stores this candidate only after success.
function Codec.Decode(raw)
    local limits = ns.ProfileValidation.Limits
    if type(raw) ~= "string" then return nil, "input: expected text" end
    if #raw > limits.input then return nil, "input: exceeds " .. limits.input .. " bytes" end
    local body = raw:match("^%s*FCT1:(.*)$")
    if not body then return nil, "input: expected an FCT1 profile" end
    local envelope, err = Kit.Decode(body)
    if envelope == nil then return nil, "input: " .. err end
    if type(envelope) ~= "table" then return nil, "profile: expected a name/data table" end
    if type(envelope.data) ~= "table" then return nil, "data: expected a profile table" end
    local name = envelope.name
    if name == nil or name == "" then name = "Imported" end
    name, err = ns.ProfileValidation.ValidateName(name)
    if not name then return nil, err end
    local candidate
    candidate, err = ns.ProfileValidation.Validate(envelope.data)
    if not candidate then return nil, err end
    return { name = name, data = candidate }
end
