-- Run from desktop/device KOReader: ./luajit <plugin>/tools/check_prefix.lua <plugin> <database>
-- Uses the real SQLite/JSON binding, leaves the official database read-only.
require("setupkoenv")
local root, path = assert(arg[1], "plugin directory required"), assert(arg[2], "DPD database required")
package.path = root .. "/?.lua;" .. package.path
local DB = require("dpd/db")
local Lookup = require("dpd/lookup")
local Render = require("ui/dpd_render")
local Navigation = require("dpd/navigation")
local SQ3 = require("lua-ljsqlite3/init")
local time = require("ui/time")

local temporary = os.tmpname()
os.remove(temporary)
local fixture = SQ3.open(temporary)
fixture:exec([[CREATE TABLE lookup(lookup_key TEXT PRIMARY KEY, headwords TEXT, deconstructor TEXT);
CREATE TABLE dpd_headwords(id INTEGER PRIMARY KEY, lemma_1 TEXT, pos TEXT, meaning_1 TEXT, meaning_2 TEXT);
INSERT INTO lookup VALUES('dhammā','[1]','');
INSERT INTO lookup VALUES('dhammāti','[1]','');
INSERT INTO lookup VALUES('dhammī','[1]','');
INSERT INTO lookup VALUES('dham%','[1]','');
INSERT INTO dpd_headwords VALUES(1,'dhamma','masc','teaching','');]])
fixture:close()
local minimal = DB.new(temporary)
local rows = minimal:prefix("dhammā")
assert(#rows == 2 and rows[1].lookup_key == "dhammā" and rows[2].lookup_key == "dhammāti",
    "Unicode prefix range must exclude the next letter")
assert(#minimal:prefix("dham%") == 1, "wildcards must stay literal")
assert(#minimal:prefix("dham' OR 1=1") == 0, "prefix parameters must be bound")
assert(#minimal:prefix("dham", 1) == 1)
for _, limit in ipairs({0,21,1.5,-1,math.huge}) do
    assert(not pcall(minimal.prefix,minimal,"dham",limit))
end
assert(not pcall(minimal.prefix,minimal,"",20))
local value = Lookup.new(minimal):get("dhammāx")
assert(value.matched_via == "prefix" and value.suggestions[1].query == "dhammā",
    "prefix rescue must work without an optional fuzzy_key column")
minimal:close()
os.remove(temporary)

local db = DB.new(path)
-- Check the range's query plan separately with desktop SQLite. KOReader's
-- stripped SQLite build does not provide reliable EXPLAIN results.
local value = Lookup.new(db):get("bhikkhux")
assert(value.matched_via == "prefix" and value.single_suggestion and #value.suggestions == 1)
assert(value.suggestions[1].query == "bhikkhu" and #value.suggestions[1].model.senses > 0)
assert(not Lookup.directHit(value))
local body = Render.render(value, Navigation.new(value):current())
assert(body:find("bhikkhux → bhikkhu · approximate · shortened prefix",1,true))
-- The dictionary action is a fixed native button, exercised by check_learning.
assert(not body:find("dpd:normal",1,true))
assert(Lookup.new(db):get("bhikkhuxy").suggestions[1].query == "bhikkhu")
-- A complete shorter word outranks continuations of the longer prefix.
local dhamma = Lookup.new(db):get("dhammatq")
assert(dhamma.single_suggestion and dhamma.suggestions[1].query == "dhamma", "dhammatq must offer dhamma")
local footnote = Lookup.new(db):get("bhikkhu1")
assert(footnote.single_suggestion and footnote.suggestions[1].query == "bhikkhu"
    and footnote.suggestions[1].reason == "digits" and not Lookup.directHit(footnote))
assert(Render.render(footnote, Navigation.new(footnote):current())
    :find("bhikkhu1 → bhikkhu · approximate · trailing digits removed",1,true))
assert(not Lookup.new(db):get("bhi1khu").found, "embedded digits stay unmatched")
assert(not Lookup.new(db):get("bhikkhux",{prefix=false}).found)
assert(not Lookup.new(db):get("bhikkhux",{approximate=false}).found)
assert(not Lookup.new(db):get("dpdtestnomatch").found)
assert(Lookup.new(db):get("pacchima").matched_via == "exact")
assert(Lookup.new(db):get("indakhile").matched_via == "fuzzy")

-- Rebuild the model each time: bypass the plugin's result cache, while reusing
-- its prepared statements. Report host timings, never infer Kindle timings.
for _, sample in ipairs({{"bhikkhux",nil},{"bhikkhuxy",nil},{"dhammatq",nil},{"bhikkhu1",nil},{"dpdtestnomatch",nil},
    {"bhikkhux",{prefix=false}},{"pacchima",nil}}) do
    local samples, queries, html_bytes = {}, {}, 0
    for i=1,20 do
        local lookup = Lookup.new(db)
        local started, count = time.monotonic(), db.query_count
        local result = lookup:get(sample[1], sample[2])
        samples[i], queries[i] = time.to_us(time.monotonic() - started) / 1000, db.query_count - count
        html_bytes = #Render.render(result, Navigation.new(result):current())
    end
    table.sort(samples)
    local sum = 0
    for _, elapsed in ipairs(samples) do sum = sum + elapsed end
    print(string.format("%s%s: mean %.3f ms, p95 %.3f ms, queries %d, HTML %d bytes (20 uncached models)",
        sample[1], sample[2] and " (direct/folded only)" or "", sum/#samples, samples[19],queries[20],html_bytes))
end
db:close()
print("Bounded prefix ranges, labels, priorities, direct fallback and official database checks passed")
