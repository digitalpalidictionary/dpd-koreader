-- Check the Sanskrit-equivalent fallback of Other dictionaries for a release:
-- for every DPD headword (its clean lemma, as Lookup:otherDictionaries
-- searches it), look up Edgerton, MW and Apte without and with the senses'
-- Sanskrit words. Fails if an exact match of the Pāḷi spelling changes, if
-- Edgerton loses near spellings, or if a group found by Sanskrit is not
-- exact. Prints what changed per dictionary and the added time; with an
-- output directory, also writes every change as <dict>.tsv for reading.
-- ./luajit <plugin>/tools/check_sanskrit.lua <plugin> <dpd-mobile.db> [outdir]
require("setupkoenv")
local root, path, out = assert(arg[1]), assert(arg[2]), arg[3]
package.path = root .. "/?.lua;" .. package.path
local db = require("dpd/db").new(path)
local Dictionaries = require("dpd/dictionaries")
local reader = Dictionaries.new(db)
local dicts = { "bhs", "mw", "apte" }

-- Clean lemma -> its senses' Sanskrit words, in sense order.
local words, order = {}, {}
for _, row in ipairs(db:query("SELECT lemma_1, sanskrit FROM dpd_headwords ORDER BY id")) do
    local key = tostring(row.lemma_1):gsub(" %d[%d.]*$", "")
    if not words[key] then words[key] = { list = {}, seen = {}, fields = {} }; order[#order + 1] = key end
    local entry = words[key]
    if row.sanskrit and tostring(row.sanskrit):find("%S") then entry.fields[#entry.fields + 1] = tostring(row.sanskrit) end
    for _, word in ipairs(Dictionaries.sanskritWords(row.sanskrit)) do
        if not entry.seen[word] then entry.seen[word] = true; entry.list[#entry.list + 1] = word end
    end
end

local function byId(groups)
    local map = {}
    for _, group in ipairs(groups) do map[group.id] = group end
    return map
end
local function ids(group)
    local list = {}
    for _, e in ipairs(group and group.entries or {}) do list[#list + 1] = e.id end
    return table.concat(list, ",")
end
local function shown(group)
    local list = {}
    for _, e in ipairs(group and group.entries or {}) do
        list[#list + 1] = (e.approximate and "≈ " or "") .. e.word .. " · " .. (e.preview or "")
    end
    return (table.concat(list, "  ||  "):gsub("[\t\n]", " "))
end

local failures, counts, files = 0, {}, {}
local function fail(message)
    failures = failures + 1
    if failures <= 20 then print("FAIL " .. message) end
end
for _, d in ipairs(dicts) do
    counts[d] = {}
    if out then
        files[d] = assert(io.open(out .. "/" .. d .. ".tsv", "w"))
        files[d]:write("change\tlemma\tsanskrit\tnow\tbefore\n")
    end
end
local before_s, after_s, searched = 0, 0, 0
for _, key in ipairs(order) do
    local entry = words[key]
    local started = os.clock()
    local before = byId(reader:lookup({ key }, dicts))
    -- Time both lookups over the same headwords: those with Sanskrit words.
    if #entry.list > 0 then before_s = before_s + os.clock() - started end
    local after = before
    if #entry.list > 0 then
        searched = searched + 1
        started = os.clock()
        after = byId(reader:lookup({ key }, dicts, entry.list))
        after_s = after_s + os.clock() - started
    end
    for _, d in ipairs(dicts) do
        local old, new = before[d], after[d]
        local old_exact = old and not old.entries[1].approximate
        local change
        if old_exact then
            change = "exact match: unchanged"
            if ids(old) ~= ids(new) or new.via then fail(d .. " " .. key .. ": exact match changed") end
        elseif ids(old) == ids(new) then
            change = old and "near spellings: unchanged" or "none: unchanged"
        else
            if not (new and new.via and #new.via > 0) then fail(d .. " " .. key .. ": changed without a Sanskrit word") end
            for _, e in ipairs(new and new.entries or {}) do
                if e.approximate then fail(d .. " " .. key .. ": Sanskrit group has a near spelling") end
            end
            if d == "bhs" and old then fail("bhs " .. key .. ": near spellings replaced") end
            change = old and "near spellings → Sanskrit" or "none → Sanskrit"
        end
        counts[d][change] = (counts[d][change] or 0) + 1
        if files[d] and change:find("Sanskrit", 1, true) then
            files[d]:write(table.concat({ change, key, table.concat(entry.fields, " / "), shown(new), shown(old) }, "\t") .. "\n")
        end
    end
end
for _, d in ipairs(dicts) do if files[d] then files[d]:close() end end

print(("%d headwords, %d with Sanskrit words"):format(#order, searched))
for _, d in ipairs(dicts) do
    print(d)
    local names = {}
    for name in pairs(counts[d]) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do print(("  %-28s %6d"):format(name, counts[d][name])) end
end
local n = math.max(1, searched)
print(("ms per lookup of the %d: %.3f without Sanskrit, %.3f with, %.3f extra (desktop CPU time)"):format(
    searched, before_s * 1000 / n, after_s * 1000 / n, (after_s - before_s) * 1000 / n))
if failures > 0 then print(("FAIL %d invariant violations"):format(failures)); os.exit(1) end
print("PASS Sanskrit fallback: exact matches and Edgerton near spellings kept, Sanskrit groups exact")
