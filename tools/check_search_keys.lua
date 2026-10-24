-- Check Search other dictionaries against the dictionaries' own headword
-- lists, so its rules (docs/DEVELOPMENT.md, "Dictionary search rules") are
-- measured on data rather than on examples chosen to fit them.
--
-- 1. Every headword of Monier-Williams, Apte and Edgerton, typed as it is
--    stored, must be found exactly. Misses with a documented cause (too long,
--    spaces at the ends, characters the search folds) are counted, not failed.
-- 2. Every Monier-Williams headword (a stem) is typed with only Apte chosen.
--    Apte entries that are such a stem plus the endings the search adds
--    (ḥ after a vowel, ṃ after a) must be found exactly.
-- 3. Report only: Apte headwords that a Monier-Williams headword plus one or
--    two letters would spell but the search doesn't reach, grouped by those
--    letters. Most are other words (ghaṭa, ghaṭaka); a common group that is
--    the same word in another form is a gap in the rules. With an output
--    directory, all of them are written to unreached.tsv.
-- ./luajit <plugin>/tools/check_search_keys.lua <plugin> <dpd-mobile.db> [outdir]
require("setupkoenv")
local root, path, out = assert(arg[1]), assert(arg[2]), arg[3]
package.path = root .. "/?.lua;" .. package.path
local Lookup = require("dpd/lookup")
local Normalize = require("dpd/normalize")
local lookup = Lookup.new(require("dpd/db").new(path))

local started = os.clock()
local failures = 0
local function fail(message)
    failures = failures + 1
    if failures <= 20 then print("FAIL " .. message) end
end
local function exact(text, id)
    local found = {}
    for _, group in ipairs(lookup:searchDictionaries(text, { id }).dictionaries.groups) do
        for _, entry in ipairs(group.entries) do
            if not entry.approximate then found[entry.word] = true end
        end
    end
    return found
end
local headwords = {}
for _, id in ipairs({ "mw", "apte", "bhs" }) do
    local list, set = {}, {}
    for _, row in ipairs(lookup.db:query("SELECT DISTINCT word FROM dict_entries WHERE dict_id = ?", { id })) do
        local word = tostring(row.word)
        list[#list + 1] = word; set[word] = true
    end
    table.sort(list)
    headwords[id] = { list = list, set = set }
end

print("1. Headwords typed as stored")
for _, id in ipairs({ "mw", "apte", "bhs" }) do
    local found, causes = 0, {}
    for _, word in ipairs(headwords[id].list) do
        if exact(word, id)[word] then
            found = found + 1
        else
            local cause = #word > Lookup.max_dictionary_query and "longer than the search keeps"
                or word ~= Normalize.trim(word) and "spaces at the ends"
                or word:find("\194\173") and "soft hyphen"
                or word:find("ṁ") and "ṁ (searched as ṃ)"
                or word ~= Normalize.nfc(word) and "not NFC"
            if cause then causes[cause] = (causes[cause] or 0) + 1
            else fail(id .. " " .. word .. ": not found typed as stored") end
        end
    end
    print(("  %-5s %6d of %6d found exactly"):format(id, found, #headwords[id].list))
    for cause, n in pairs(causes) do print(("        %6d not: %s"):format(n, cause)) end
end

-- One UTF-8 character at the end of a word, and the word without it.
local function lastChar(word) return word:match("[%z\1-\127\194-\244][\128-\191]*$") or "" end
local function dropLast(word) return word:sub(1, #word - #lastChar(word)) end
local nominative = { a = true, ["ā"] = true, i = true, ["ī"] = true, u = true, ["ū"] = true,
    e = true, o = true, ["ṛ"] = true, ["ṝ"] = true }

print("2. Monier-Williams stems typed with only Apte chosen")
local mw, apte = headwords.mw, headwords.apte
local reached = {} -- Apte headword -> true when some typed stem found it
local typed, literal, ending = 0, 0, 0
for _, stem in ipairs(mw.list) do
    -- Lower-case words only: capitalized ones are names, typed as names.
    if Normalize.lower(stem) == stem and not stem:find("[%s%p%d]") then
        typed = typed + 1
        local found = exact(stem, "apte")
        if found[stem] then literal = literal + 1 end
        local other = false
        for word in pairs(found) do
            reached[word] = true
            if word ~= stem then other = true end
        end
        if other then ending = ending + 1 end
        local last = lastChar(stem)
        for _, form in ipairs({ nominative[last] and stem .. "ḥ", last == "a" and stem .. "ṃ" }) do
            if form and apte.set[form] and not found[form] then fail("apte " .. form .. ": not found by typing " .. stem) end
        end
    end
end
print(("  %d stems typed: Apte has %d as typed, %d also or only with an added ending"):format(typed, literal, ending))

print("3. Apte headwords a Monier-Williams stem plus one or two letters spells, not reached")
local tails, examples, unreached = {}, {}, {}
for _, word in ipairs(apte.list) do
    if not reached[word] then
        local stem = dropLast(word)
        for _ = 1, 2 do
            if stem == "" then break end
            if mw.set[stem] and not apte.set[stem] then
                local tail = lastChar(stem) .. " + " .. word:sub(#stem + 1)
                tails[tail] = (tails[tail] or 0) + 1
                examples[tail] = examples[tail] or {}
                if #examples[tail] < 4 then examples[tail][#examples[tail] + 1] = stem .. " → " .. word end
                unreached[#unreached + 1] = tail .. "\t" .. stem .. "\t" .. word
                break
            end
            stem = dropLast(stem)
        end
    end
end
local order = {}
for tail in pairs(tails) do order[#order + 1] = tail end
table.sort(order, function(a, b) return tails[a] > tails[b] or tails[a] == tails[b] and a < b end)
print(("  %d headwords in %d groups; the largest:"):format(#unreached, #order))
for i = 1, math.min(12, #order) do
    print(("  %-10s %5d  %s"):format(order[i], tails[order[i]], table.concat(examples[order[i]], ", ")))
end
if out then
    local file = assert(io.open(out .. "/unreached.tsv", "w"))
    file:write("stem ending + letters\tstem\tapte\n", table.concat(unreached, "\n"), "\n")
    file:close()
end

-- Spelled alike when diacritics, aspiration and doubled letters are ignored
-- (the close-spelling key) and a nasal before a stop is one letter.
local function loose(word) return (Normalize.fuzzy(word):gsub("[mn]([kgcjtdpb])", "n%1")) end
print("4. Apte headwords spelled like a Monier-Williams headword but not reached by typing it")
local spellings = {}
for _, word in ipairs(mw.list) do
    local key = loose(word)
    spellings[key] = spellings[key] or word
end
local class = { k = "ṅ", g = "ṅ", c = "ñ", j = "ñ", ["ṭ"] = "ṇ", ["ḍ"] = "ṇ", t = "n", d = "n", p = "m", b = "m" }
local kinds, kind_examples, variants = {}, {}, {}
for _, word in ipairs(apte.list) do
    local spelled = not reached[word] and not mw.set[word] and spellings[loose(word)]
    if spelled then
        -- Apte's ṃ where Monier-Williams writes a nasal letter: a stop's own
        -- nasal before it (abaṃdhu, abandhu), else m (saṃmūḍha, abhidakṣiṇaṃ).
        local nasal = word:gsub("ṃ([kgcjtdpb])", function(stop) return class[stop] .. stop end)
        nasal = nasal:gsub("ṃṭ", "ṇṭ"):gsub("ṃḍ", "ṇḍ"):gsub("ṃ", "m")
        local kind = mw.set[nasal] and "ṃ where Monier-Williams has a nasal letter" or "other spelling"
        kinds[kind] = (kinds[kind] or 0) + 1
        kind_examples[kind] = kind_examples[kind] or {}
        if #kind_examples[kind] < 5 then kind_examples[kind][#kind_examples[kind] + 1] = spelled .. " → " .. word end
        variants[#variants + 1] = kind .. "\t" .. spelled .. "\t" .. word
    end
end
for _, kind in ipairs({ "ṃ where Monier-Williams has a nasal letter", "other spelling" }) do
    if kinds[kind] then print(("  %5d %s: %s"):format(kinds[kind], kind, table.concat(kind_examples[kind], ", "))) end
end
if out then
    local file = assert(io.open(out .. "/variants.tsv", "w"))
    file:write("kind\tmw\tapte\n", table.concat(variants, "\n"), "\n")
    file:close()
end

print(("%.0f s"):format(os.clock() - started))
if failures > 0 then print(("FAIL %d headwords not found"):format(failures)); os.exit(1) end
print("PASS: every Sanskrit headword is found as stored, and Apte's ḥ and ṃ forms by their stems")
