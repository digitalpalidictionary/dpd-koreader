-- Verify the data assumptions behind the frequency, sutta, family and
-- other-dictionary views against a DPD release.
-- Run with KOReader's bundled LuaJIT from its extracted desktop directory:
-- ./luajit <plugin>/tools/check_parity_data.lua <plugin> <official-mobile-db>
-- Read-only. Prints measurements; fails only when an assumption is broken.
require("setupkoenv")
local root, path = assert(arg[1]), assert(arg[2])
package.path = root .. "/?.lua;" .. package.path
local DB = require("dpd/db")
local Json = require("json")
local db = DB.new(path)
local function q(sql, params) return db:query(sql, params) end
local function columns(table_name)
    local out = {}
    for _, row in ipairs(q("PRAGMA table_info(" .. table_name .. ")")) do out[row.name] = true end
    return out
end
local function need(table_name, names)
    local found = columns(table_name)
    for _, name in ipairs(names) do assert(found[name], "missing " .. table_name .. "." .. name) end
end
-- lua-ljsqlite3 returns no rows for EXPLAIN QUERY PLAN, so check that an
-- index (or the primary key) leads with the queried columns instead.
local function indexed(table_name, wanted)
    for _, index in ipairs(q("PRAGMA index_list(" .. table_name .. ")")) do
        local names = {}
        for _, column in ipairs(q("PRAGMA index_info(" .. index.name .. ")")) do names[#names + 1] = column.name end
        if table.concat(names, ","):sub(1, #wanted) == wanted then return index.name end
    end
end
local function report(label, value) print(string.format("%-34s %s", label, tostring(value))) end
print("Release " .. tostring(db.info.dpd_release_version))

-- Phase 1
need("dpd_headwords", { "lemma_1", "stem", "pattern", "meaning_1", "source_1", "ebt_count", "freq_data" })
need("dpd_roots", { "root_in_comps", "root_has_verb", "sanskrit_root_class", "dhatupatha_num",
    "dhatupatha_root", "dhatupatha_pali", "dhatupatha_english", "dhatumanjusa_num", "dhatumanjusa_root",
    "dhatumanjusa_pali", "dhatumanjusa_english", "dhatumala_root", "dhatumala_pali", "dhatumala_english",
    "panini_root", "panini_sanskrit", "panini_english", "root_count" })
-- The webapp's traditional lemma differs only for these patterns (tools/lemma_traditional.py).
local traditional = q("SELECT count(*) AS n FROM dpd_headwords WHERE instr(stem,'!') = 0 AND pattern IN "
    .. "('ant adj','ant masc','ar fem','ar masc','ar2 masc','arahant masc','as masc','bhavant masc','mātar fem')")[1].n
report("traditional lemma differs", traditional)
assert(traditional > 0)

-- Frequency
local Layout = require("dpd/frequency_layout")
local vectors = { cst = "CstFreq", bjt = "BjtFreq", sya = "SyaFreq", sc = "ScFreq" }
local frequency, longest = 0, 0
for _, row in ipairs(q("SELECT id, freq_data FROM dpd_headwords WHERE freq_data != ''")) do
    longest = math.max(longest, #row.freq_data)
    local data = Json.decode(row.freq_data)
    assert(type(data.FreqHeading) == "string", "heading " .. row.id)
    for corpus, name in pairs(vectors) do
        local counts, grades = data[name], data[name:gsub("Freq", "Grad")]
        assert(type(counts) == "table" and type(grades) == "table" and #counts == #grades, name .. " " .. row.id)
        -- An empty vector means "only in compounds"; otherwise its length is fixed.
        assert(#counts == 0 or #counts == Layout.lengths[corpus], name .. " length " .. #counts .. " " .. row.id)
    end
    frequency = frequency + 1
end
report("frequency rows / longest bytes", frequency .. " / " .. longest)

-- Sutta information: every canonical name is a headword's exact lemma.
local suttas = q("SELECT count(*) AS n FROM sutta_info")[1].n
local matched = q("SELECT count(*) AS n FROM sutta_info s JOIN dpd_headwords h ON h.lemma_1 = s.dpd_sutta")[1].n
report("suttas / matching lemma_1", suttas .. " / " .. matched)
assert(suttas > 0 and matched == suttas, "a sutta name is not an exact headword")
assert(indexed("sutta_info", "dpd_sutta"), "sutta_info primary key")

-- Root matrix: bounded per-root subsets through the root_key index.
local largest = q("SELECT root_key, count(*) AS n FROM dpd_headwords WHERE root_key != ''"
    .. " GROUP BY root_key ORDER BY n DESC LIMIT 1")[1]
report("largest root", largest.root_key .. " " .. largest.n)
assert(indexed("dpd_headwords", "root_key"), "root_key index")

-- English→Pāḷi
local epd, epd_max = 0, 0
for _, row in ipairs(q("SELECT lookup_key, epd FROM lookup WHERE epd != ''")) do
    local items = Json.decode(row.epd)
    assert(type(items) == "table" and #items > 0, "epd " .. row.lookup_key)
    for _, item in ipairs(items) do
        assert(type(item) == "table" and #item == 3 and type(item[1]) == "string", "epd item " .. row.lookup_key)
    end
    epd, epd_max = epd + 1, math.max(epd_max, #items)
end
report("EPD keys / most items", epd .. " / " .. epd_max)

-- Autocomplete: headword prefixes (dpd/suggest.lua tier 1) and both lookup
-- prefix ranges use an index.
assert(indexed("dpd_headwords", "lemma_1"), "lemma_1 index")
for _, column in ipairs({ "lookup_key", "fuzzy_key" }) do
    local sql = "SELECT lookup_key FROM lookup WHERE " .. column .. " >= ? AND " .. column .. " < ? LIMIT 8"
    assert(indexed("lookup", column), column .. " index")
    local started = os.clock()
    for _ = 1, 200 do q(sql, { "dham", "dhan" }) end
    report("prefix " .. column .. " ms", string.format("%.3f", (os.clock() - started) / 200 * 1000))
end
-- Script spellings exist but have no index; reverse lookup would scan.
report("sinhala/devanagari/thai indexed", tostring(indexed("lookup", "sinhala") or indexed("lookup", "devanagari")
    or indexed("lookup", "thai") or false) .. " (false: reverse lookup would scan)")

-- Other dictionaries: composite index, and exact-hit rates keyed by DPD's clean lemma.
local dictionaries = q("SELECT dict_id, entry_count FROM dict_meta ORDER BY dict_id")
assert(#dictionaries > 0, "no other dictionaries")
assert(indexed("dict_entries", "dict_id,word"), "(dict_id, word) index")
local sample = q("SELECT DISTINCT lemma_1 FROM dpd_headwords WHERE id % 40 = 0")
-- DPPN capitalizes its headwords; word_fuzzy is a heavy fold (dhamma -> dama).
local upper = { ["ā"]="Ā", ["ī"]="Ī", ["ū"]="Ū", ["ṭ"]="Ṭ", ["ḍ"]="Ḍ", ["ṇ"]="Ṇ", ["ñ"]="Ñ", ["ṅ"]="Ṅ", ["ḷ"]="Ḷ", ["ṃ"]="Ṃ" }
local function capitalized(word)
    local first = word:match("^[%z\1-\127\194-\244][\128-\191]*")
    return (upper[first] or first:upper()) .. word:sub(#first + 1)
end
for _, dictionary in ipairs(dictionaries) do
    local hits, capital = 0, 0
    for _, row in ipairs(sample) do
        local clean = row.lemma_1:gsub(" %d[%d.]*$", "")
        local function found(word)
            return #q("SELECT 1 FROM dict_entries WHERE dict_id = ? AND word = ? LIMIT 1", { dictionary.dict_id, word }) > 0
        end
        if found(clean) then hits = hits + 1 elseif found(capitalized(clean)) then capital = capital + 1 end
    end
    local largest_entry = q("SELECT max(length(definition_html)) AS n FROM dict_entries WHERE dict_id = ?",
        { dictionary.dict_id })[1].n
    report(dictionary.dict_id .. " exact/capitalized hits",
        string.format("%d / %d of %d sample lemmas; largest article %d bytes", hits, capital, #sample, largest_entry))
end
db:close()
print("PASS: parity data assumptions hold for this release")
