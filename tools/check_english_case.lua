-- Case-insensitive English lookup and autocomplete against the mobile DB.
-- Run from a copied desktop KOReader directory with its bundled LuaJIT:
-- ./luajit <plugin>/tools/check_english_case.lua <plugin> <mobile.db>
require("setupkoenv")
local root, path = assert(arg[1]), assert(arg[2])
package.path = root .. "/?.lua;" .. package.path
local DB = require("dpd/db")
local English = require("dpd/english")
local Suggest = require("dpd/suggest")
local Normalize = require("dpd/normalize")
local Dictionaries = require("dpd/dictionaries")
local db = DB.new(path)
local english, suggest = English.new(db), Suggest.new(db)

-- Both new query shapes constrain the fuzzy index before filtering case.
local indexed = false
for _, index in ipairs(db:query("PRAGMA index_list(lookup)")) do
    local columns = db:query("PRAGMA index_info(" .. index.name .. ")")
    if columns[1] and columns[1].name == "fuzzy_key" then indexed = true end
end
assert(indexed, "English case lookup needs the mobile fuzzy_key index")

for _, case in ipairs({
    { "awakened one", "Awakened One", 2 }, { "AWAKENED ONE", "Awakened One", 2 },
    { "Awakened One.", "Awakened One", 2 }, { "epithet of the buddha", "epithet of the Buddha", 41 },
    { "epithet of the Buddha.", "epithet of the Buddha", 41 }, { "NIBBĀNA", "Nibbāna" },
    { "nibba\204\132na", "Nibbāna" },
    { "name of kakusandha buddha's father", "name of Kakusandha Buddha's father" },
}) do
    local before = db.query_count
    local page = english:page(case[1])
    assert(page.query == case[2] and page.total > 0 and (not case[3] or page.total == case[3]), case[1])
    assert(db.query_count - before <= 9, "bounded case discovery: " .. case[1])
end

local function has(items, word)
    for _, item in ipairs(items) do if item.text == word then return true end end
end
for _, case in ipairs({
    { "awakened o", "Awakened One" }, { "awakened one", "Awakened One" },
    { "AWAKENED ONE", "Awakened One" }, { "Awakened One.", "Awakened One" },
    { "epithet of the b", "epithet of the Buddha" }, { "epithet of the buddha", "epithet of the Buddha" },
    { "name of kakusandha buddha's f", "name of Kakusandha Buddha's father" },
    { "aṅguttara nikāya", "Aṅguttara Nikāya" }, { "nibbāna", "Nibbāna" }, { "meditate.", "meditate" },
}) do
    assert(has(suggest:complete(case[1], "english"), case[2]), "suggestion: " .. case[1])
end
assert(not has(suggest:complete("anguttara ni", "english"), "Aṅguttara Nikāya"), "keep diacritics")
assert(not has(suggest:complete("awakenedone", "english"), "Awakened One"), "keep spaces")

-- Every internally capitalized English key must remain reachable when its
-- capitals are not typed. A literal lowercase homograph may take precedence.
local checked, keys, started = 0, 0, os.clock()
for _, row in ipairs(db:query("SELECT lookup_key, fuzzy_key FROM lookup WHERE coalesce(epd, '') NOT IN ('', '[]')")) do
    assert(English.indexKey(row.lookup_key) == row.fuzzy_key, "English index fold: " .. row.lookup_key)
    keys = keys + 1
    local lower = Normalize.lower(row.lookup_key)
    if row.lookup_key ~= lower and row.lookup_key ~= Dictionaries.capitalized(lower) then
        local page = english:page(lower)
        assert(not page.error and page.total > 0, "case-only lookup lost " .. row.lookup_key)
        checked = checked + 1
    end
end
assert(checked > 5000, "expected the pinned release's internally capitalized English keys")

-- Broad existing prefixes remain bounded and responsive. Report CPU timings
-- for comparison on desktop/device rather than imposing a device-specific gate.
local samples, max_rows, max_queries = {}, 0, 0
for _, prefix in ipairs({ "sam", "par", "med", "awa", "awakened o", "epithet of the b" }) do
    local before, queries, tick = db.row_count, db.query_count, os.clock()
    local items = Suggest.new(db):complete(prefix, "english")
    local rows = db.row_count - before
    assert(#items > 0 and rows <= Suggest.limit + Suggest.english_case_scan + 29, prefix .. " candidate bound")
    max_rows, max_queries = math.max(max_rows, rows), math.max(max_queries, db.query_count - queries)
    samples[#samples + 1] = prefix .. "=" .. string.format("%.2f", (os.clock() - tick) * 1000) .. "ms"
end
print(string.format("PASS: %d English index keys, %d internally capitalized keys, exact/punctuation/prefix regressions (%.2fs)",
    keys, checked, os.clock() - started))
print(string.format("Autocomplete: at most %d returned candidate rows / %d queries; %s",
    max_rows, max_queries, table.concat(samples, ", ")))
db:close()
