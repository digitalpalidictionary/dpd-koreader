-- Recent lookups: the query and search mode of manual, book and in-popup
-- word lookups, newest first, kept in the plugin's settings table (written
-- with KOReader's normal settings flush, not on every lookup). Opening
-- tables, families or pages is navigation, not a lookup, and is not kept.
local History = {}
History.__index = History
History.limit = 50
History.max_query = 100

--- @param settings table the plugin's settings (history stored at settings.history)
function History.new(settings, limit)
    return setmetatable({ settings = settings, limit = limit or History.limit }, History)
end

function History:enabled() return self.settings.history_off ~= true end

--- Adds a query at the front, moving an older duplicate; trims to the limit.
function History:add(query, mode)
    query, mode = tostring(query or ""):gsub("^%s+", ""):gsub("%s+$", ""), mode or "pali"
    if query == "" or not self:enabled() then return end
    -- A pasted paragraph is not worth keeping in full in the settings file.
    if #query > History.max_query then
        local cut = History.max_query
        while cut > 0 and query:byte(cut + 1) >= 0x80 and query:byte(cut + 1) < 0xC0 do cut = cut - 1 end
        query = query:sub(1, cut)
    end
    local list = {}
    list[1] = { query = query, mode = mode }
    for _, item in ipairs(self.settings.history or {}) do
        if #list >= self.limit then break end
        if type(item) == "table" and type(item.query) == "string"
            and not (item.query == query and (item.mode or "pali") == mode) then
            list[#list + 1] = item
        end
    end
    self.settings.history = list
end

--- @return table { { query, mode } }, newest first, at most the limit
function History:list()
    local out = {}
    for _, item in ipairs(self.settings.history or {}) do
        -- Hand-edited or older settings may hold more than add() keeps.
        if #out >= self.limit then break end
        if type(item) == "table" and type(item.query) == "string" then out[#out + 1] = item end
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
