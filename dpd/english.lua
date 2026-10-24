-- English→Pāḷi from lookup.epd, for the lookup dialog's English mode only
-- (never long-press: English book words also have epd rows). Each item is
-- [clean lemma, pos, meaning]; a lemma opens all its senses. A key holds at
-- most a few hundred items (27 KB of JSON), decoded once and paged.
local Json = require("json")
local Dictionaries = require("dpd/dictionaries")
local Normalize = require("dpd/normalize")
local English = {}
English.__index = English
English.page_size = 20
local MAX_DATA = 262144
local DAMAGE = "Unreadable DPD English data. Replace the database with a fresh DPD mobile download."
-- Common spellings of English keys that differ only by diacritics, which
-- English lookup does not fold (it would merge different English words).
English.aliases = { nibbana = "Nibbāna", nirvana = "Nibbāna" }

function English.new(db) return setmetatable({ db = db }, English) end

--- The decoded items for a typed English word: exactly as typed, then
--- lowercase, then with a capital first letter (names such as Sanskrit);
--- then the same without trailing punctuation (monk.), then an alias.
function English:_items(word)
    if self.last and self.last.word == word then return self.last.items, self.last.key end
    if not (self.db.columns.lookup and self.db.columns.lookup.epd) then return {}, word end
    local tried, items, key = {}, {}, word
    local lower = Normalize.lower(word)
    local bare = Normalize.lower(word:gsub("[%.,;:!?]+$", ""))
    local candidates = { word, lower, Dictionaries.capitalized(lower), bare, Dictionaries.capitalized(bare),
        English.aliases[bare] }
    for _, candidate in ipairs(candidates) do
        if not tried[candidate] then
            tried[candidate] = true
            local row = self.db:query("SELECT epd FROM lookup WHERE lookup_key = ?", { candidate })[1]
            local raw = row and row.epd
            if type(raw) == "string" and raw ~= "" and raw ~= "[]" then
                assert(#raw <= MAX_DATA, DAMAGE)
                local ok, data = pcall(Json.decode, raw)
                -- A list of items: an object ({"key": ...}) is a changed export.
                assert(ok and type(data) == "table" and #data > 0, DAMAGE)
                local count = 0
                for _ in pairs(data) do count = count + 1 end
                assert(count == #data, DAMAGE)
                for _, item in ipairs(data) do
                    assert(type(item) == "table" and type(item[1]) == "string", DAMAGE)
                    items[#items + 1] = { lemma = item[1], pos = tostring(item[2] or ""), meaning = tostring(item[3] or "") }
                end
                key = candidate
                break
            end
        end
    end
    self.last = { word = word, items = items, key = key }
    return items, key
end

--- @return table { query, items = { { lemma, pos, meaning } }, total, offset, has_more, next_offset, error }
function English:page(word, offset, limit)
    -- Keys hold single spaces ("good deed"); a doubled space is not a different word.
    word = Normalize.trim(Normalize.nfc(tostring(word or ""))):gsub("%s+", " ")
    offset, limit = offset or 0, limit or English.page_size
    local ok, items, key = pcall(self._items, self, word)
    if not ok then return { query = word, items = {}, total = 0, offset = 0, error = DAMAGE } end
    local out = { query = key, items = {}, total = #items, offset = offset }
    for i = offset + 1, math.min(#items, offset + limit) do out.items[#out.items + 1] = items[i] end
    out.next_offset = offset + #out.items
    out.has_more = out.next_offset < #items
    return out
end

return English
