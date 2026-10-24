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

-- The exporter's raw fold, before Pāḷi selection cleanup: English keys keep
-- apostrophes and boundary punctuation (one's, etc.) in their fuzzy index.
function English.indexKey(text)
    local key = Normalize.lower(Normalize.nfc(text)):gsub("√", ""):gsub(" ", "")
    key = key:gsub("[%z\1-\127\194-\244][\128-\191]*", function(char)
        local first, second = char:byte(1, 2)
        if first == 204 or (first == 205 and second and second <= 175) then return "" end
        return Normalize.base(char)
    end)
    return (key:gsub("([kgcjtdpb])h", "%1"):gsub("([bcdfghjklmnpqrstvwxyz])%1", "%1"))
end

-- The mobile database has a case-sensitive key index, but its fuzzy index
-- groups case variants too. Use that index only to find candidate spellings:
-- the final comparison retains spaces, punctuation and every diacritic.
-- Exact searches read one complete bucket (at most 29 rows in the tested
-- release). Autocomplete's wider prefix range is capped before inspecting
-- payloads, so a common Pāḷi prefix cannot turn typing into a table scan.
function English.caseKeys(db, text, prefix_limit)
    if not (db.columns.lookup and db.columns.lookup.fuzzy_key) then return {} end
    local folded = English.indexKey(text)
    if folded == "" then return {} end
    local rows
    if prefix_limit then
        rows = db:query("SELECT lookup_key, length(epd) AS epd_bytes FROM (SELECT lookup_key, epd FROM lookup"
            .. " WHERE fuzzy_key >= ? AND fuzzy_key < ? ORDER BY fuzzy_key LIMIT ?)"
            .. " WHERE coalesce(epd, '') NOT IN ('', '[]')",
            { folded, folded .. "\244\143\191\191", prefix_limit })
    else
        rows = db:query("SELECT lookup_key, length(epd) AS epd_bytes FROM lookup WHERE fuzzy_key = ?"
            .. " AND coalesce(epd, '') NOT IN ('', '[]') ORDER BY lookup_key", { folded })
    end
    local out, lower = {}, Normalize.lower(text)
    for _, row in ipairs(rows) do
        local candidate = Normalize.lower(row.lookup_key)
        if candidate == lower or (prefix_limit and candidate:sub(1, #lower) == lower) then
            out[#out + 1] = row
        end
    end
    return out
end

--- The decoded items for a typed English word: exactly as typed, then
--- lowercase, then with a capital first letter (names such as Sanskrit);
--- then without trailing punctuation (monk.), any remaining case variants,
--- and finally an alias.
function English:_items(word)
    if self.last and self.last.word == word then return self.last.items, self.last.key end
    if not (self.db.columns.lookup and self.db.columns.lookup.epd) then return {}, word end
    local tried, items, key = {}, {}, word
    local lower = Normalize.lower(word)
    local bare = word:gsub("[%.,;:!?]+$", "")
    local bare_lower = Normalize.lower(bare)
    local candidates = { word, lower, Dictionaries.capitalized(lower), bare, bare_lower, Dictionaries.capitalized(bare_lower) }
    local function decode(raw, candidate)
        if type(raw) ~= "string" or raw == "" or raw == "[]" then return false end
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
        return true
    end
    local function read(candidate)
        if tried[candidate] then return false end
        tried[candidate] = true
        local row = self.db:query("SELECT epd FROM lookup WHERE lookup_key = ?", { candidate })[1]
        return decode(row and row.epd, candidate)
    end
    -- Probe the few literal candidates together, returning only the first
    -- usable payload. Its column identifies the winning candidate without
    -- fetching every matching payload or adding a key to the result bytes.
    local keys, columns, probes = {}, {}, {}
    for _, candidate in ipairs(candidates) do
        if not tried[candidate] then
            tried[candidate] = true
            keys[#keys + 1] = candidate
            columns[#keys] = "epd_" .. #keys
        end
    end
    for i = 1, #keys do
        local values = {}
        for j, column in ipairs(columns) do
            values[j] = (i == j and "epd" or "NULL") .. " AS " .. column
        end
        probes[i] = "SELECT " .. table.concat(values, ", ") .. ", " .. i .. " AS priority"
            .. " FROM lookup WHERE lookup_key = ? AND coalesce(epd, '') NOT IN ('', '[]')"
    end
    local row = self.db:query("SELECT " .. table.concat(columns, ", ") .. " FROM ("
        .. table.concat(probes, " UNION ALL ") .. ") ORDER BY priority LIMIT 1", keys)[1]
    local matched = false
    if row then
        for i, candidate in ipairs(keys) do
            if decode(row[columns[i]], candidate) then matched = true; break end
        end
    end
    if not matched then
        for _, query in ipairs(word == bare and { word } or { word, bare }) do
            for _, row in ipairs(English.caseKeys(self.db, query)) do
                if read(row.lookup_key) then matched = true; break end
            end
            if matched then break end
        end
    end
    if not matched and English.aliases[bare_lower] then read(English.aliases[bare_lower]) end
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
