-- Run with KOReader's bundled LuaJIT from its extracted desktop directory:
-- ./luajit <plugin>/tools/check_inflection.lua <plugin> <official-mobile-db>
require("setupkoenv")
local root,path=assert(arg[1]),assert(arg[2])
package.path=root .. "/?.lua;" .. package.path
local DB=require("dpd/db")
local Inflection=require("dpd/inflection")
local Lookup=require("dpd/lookup")
local db=DB.new(path)
local inflection=Inflection.new(db)

-- Unique form counts of DPD's own generated tables, same release
-- (v0.4.20260926), from the October 2026 feature-parity research.
local expected={["buddha 1"]=19,["buddha 2"]=24,["gacchati 1"]=57,["ahaṃ"]=20,["atthi 1.1"]=17,
    ["atthi 1.2"]=17,bhikkhu=20,["bhikkhunā"]=20,["sabba 1"]=29,["dhamma 1.01"]=19,["khādati"]=57,
    arahant=20,["mātar"]=22,pitar=18,["santa 1.1"]=36,["sīlavant"]=32}
for lemma,count in pairs(expected) do
    local row=db:sensesByLemma({lemma})[1]
    assert(row,"missing headword " .. lemma)
    local result=inflection:paradigm(db:detail(row.id),lemma,nil)
    assert(not result.error,lemma .. ": " .. tostring(result.error))
    assert(#result.forms==count,lemma .. " has " .. #result.forms .. " forms, expected " .. count)
end

-- Every template must decode to the shape the generator expects.
local templates=0
for _,row in ipairs(db:query("SELECT pattern FROM inflection_templates")) do
    assert(not inflection:_template(row.pattern).error,"unreadable template " .. row.pattern)
    templates=templates+1
end

-- Every patterned headword must produce a table without errors.
local started=os.clock()
local tables,indeclinable,cells=0,0,0
for _,row in ipairs(db:query("SELECT id,lemma_1,stem,pattern FROM dpd_headwords")) do
    if Inflection.available(row) then
        local result=inflection:paradigm(row,row.lemma_1,nil)
        assert(not result.error,row.lemma_1 .. ": " .. tostring(result.error))
        assert(#result.forms>0 and #result.sections>0,row.lemma_1 .. " has an empty table")
        tables=tables+1
        cells=cells+#result.forms
    else indeclinable=indeclinable+1 end
end
local elapsed=os.clock()-started

-- The selected form is highlighted, and the sense detail offers the link.
local lookup=Lookup.new(db)
local dhamma=db:sensesByLemma({"dhamma 1.01"})[1].id
local detail=lookup:detail(dhamma)
assert(detail.paradigm_kind=="Declension" and detail.ipa_line and detail.ipa_line:match("^/.+/$"))
local model=lookup:paradigm(dhamma,"dhammassa")
assert(model.paradigm.selected_count==2,"dhammassa is dative and genitive singular")
local gacchati=lookup:paradigm(db:sensesByLemma({"gacchati 1"})[1].id,"gacche")
assert(gacchati.paradigm.kind=="Conjugation" and #gacchati.paradigm.sections==2)
local ca=db:sensesByLemma({"pana"})[1]
assert(ca and not lookup:detail(ca.id).paradigm_kind,"indeclinables have no table")

print(string.format("PASS: %d templates, %d tables (%d forms, %.1f µs each), %d without a table, 16 reference form sets",
    templates,tables,cells,elapsed/tables*1e6,indeclinable))
db:close()
