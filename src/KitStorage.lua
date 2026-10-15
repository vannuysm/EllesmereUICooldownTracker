-- Shared saved-data selection and logout stamping.
local _, ns = ...
local Kit = ns.Kit
local Page = Kit.Page

-- Saved data ---------------------------------------------------------------------------
-- The Forever beta can fail to load SavedVariables when the game starts. A copy of the data may then come
-- from the account file, the per-character file, or an existing !ForeverData folder (which loads the
-- same files as plain addon files). Every copy is stamped when the game writes it at logout; the newest wins.
-- Returns the newest non-empty table among the candidates, ignoring own (the addon's live table).
function Kit.PickSaved(own, ...)
    local best
    for i = 1, select("#", ...) do
        local t = select(i, ...)
        if type(t) == "table" and t ~= own and next(t) ~= nil
            and (not best or (tonumber(t._savedAt) or 0) > (tonumber(best._savedAt) or 0)) then
            best = t
        end
    end
    return best
end

-- getter: returns the table to stamp (tables can be replaced during a session, so look them up at logout).
local stamped = {}
local stamper = CreateFrame("Frame")
stamper:RegisterEvent("PLAYER_LOGOUT")   -- also fires on /reload, just before the game writes
stamper:SetScript("OnEvent", function()
    local now = time()
    for _, get in ipairs(stamped) do
        local t = get()
        if type(t) == "table" then t._savedAt = now end
    end
end)
function Kit.StampOnLogout(getter) stamped[#stamped + 1] = getter end

-- A settings-page line saying whether the startup fallback is in place.
function Page:SaveStatus()
    self:Section("Saved settings")
    self:Text(function()
        if ForeverData and ForeverData.active then
            return "|cff60ff60Protected.|r Forever Data Protect loads settings from disk, so they survive a restart "
                .. "even while the Forever beta fails to load them itself."
        end
        return "|cffffd100Not protected.|r The Forever beta currently forgets addon settings when the game restarts. "
            .. "To keep them, install and configure Forever Data Protect using its installation instructions."
    end, "GameFontHighlightSmall")
end
