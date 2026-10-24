-- Recent lookups: the query, search mode and optional literal dictionary
-- draft of manual, book and in-popup lookups, newest first, kept in the
-- settings table (written with KOReader's normal flush, not on every lookup). Opening
-- tables, families or pages is navigation, not a lookup, and is not kept.
local Normalize = require("dpd/normalize")
local History = {}
History.__index = History
History.limit = 50
-- Keep complete headwords and compounds, including multibyte Pāḷi. This is a
-- storage bound for pasted text, not a shorter query to run from Recent.
History.max_query = 4096

local function valid(item)
    return type(item) == "table" and type(item.query) == "string"
        and item.query ~= "" and #item.query <= History.max_query
        and (item.draft == nil or type(item.draft) == "string" and #item.draft <= History.max_query)
end

local function dictionaryDraft(query, mode, draft)
    if mode ~= "dictionaries" or draft == nil then return end
    -- Match searchDictionaries' literal fallback normalization, so a pasted
    -- space or decomposed accent does not create a second identical lookup.
    draft = Normalize.trim(Normalize.nfc(draft))
    if draft ~= "" and draft ~= query then return draft end
end

--- @param settings table the plugin's settings (history stored at settings.history)
function History.new(settings, limit)
    return setmetatable({ settings = settings, limit = limit or History.limit }, History)
end

function History:enabled() return self.settings.history_off ~= true end

--- Adds a query at the front, moving an older duplicate; trims to the limit.
function History:add(query, mode, draft)
    query, mode = tostring(query or ""):gsub("^%s+", ""):gsub("%s+$", ""), mode or "pali"
    if query == "" or #query > History.max_query or not self:enabled() then return end
    -- Dictionary search also tries the literal draft when Velthuis converted
    -- it (vacuum → vacūm). Replay both strings, without converting them again.
    if mode ~= "dictionaries" then draft = nil end
    if draft ~= nil and (type(draft) ~= "string" or #draft > History.max_query) then return end
    draft = dictionaryDraft(query, mode, draft)
    local list = {}
    list[1] = { query = query, mode = mode, draft = draft }
    for _, item in ipairs(self.settings.history or {}) do
        if #list >= self.limit then break end
        if valid(item)
            and not (item.query == query and (item.mode or "pali") == mode
                and dictionaryDraft(item.query, item.mode, item.draft) == draft) then
            list[#list + 1] = item
        end
    end
    self.settings.history = list
end

--- @return table { { query, mode, draft? } }, newest first, at most the limit
function History:list()
    local out = {}
    for _, item in ipairs(self.settings.history or {}) do
        -- Hand-edited or older settings may hold more than add() keeps.
        if #out >= self.limit then break end
        if valid(item) then out[#out + 1] = item end
    end
    return out
end

function History:clear() self.settings.history = nil end

--- Turning history off also forgets what was kept.
function History:setEnabled(on)
    self.settings.history_off = not on or nil
    if not on then self:clear() end
end

return History
