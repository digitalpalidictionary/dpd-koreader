-- Run with KOReader's bundled LuaJIT from its extracted desktop directory:
-- ./luajit <plugin>/tools/check_families.lua <plugin> <official-mobile-db>
require("setupkoenv")
local root,path=assert(arg[1]),assert(arg[2])
package.path=root .. "/?.lua;" .. package.path
local DB=require("dpd/db")
local Families=require("dpd/families")
local db=DB.new(path)
local families=Families.new(db)
-- Counts/identities pinned to official mobile v0.4.20260926, schema 7.
local dhamma=db:sensesByLemma({"dhamma 1.01"})[1]
assert(dhamma and dhamma.id==34626)
local detail=db:query("SELECT root_key,family_root,family_word,family_compound,family_idioms"
    .. " FROM dpd_headwords WHERE id = ?",{dhamma.id})[1]
local groups=families:groupsForDetail(detail)
local compound,root_family,idiom
for _,group in ipairs(groups) do
    if group.kind=="compound" and group.key=="dhamma" then compound=group end
    if group.kind=="root" then root_family=group end
    if group.kind=="idiom" then idiom=group end
end
assert(compound and compound.count==578,"dhamma compound metadata")
assert(root_family and root_family.key=="√dhar 1 √dhar","numbered root identity")
assert(idiom and idiom.key=="dhamma")
local before=db.query_count
families:groupsForDetail(detail)
assert(db.query_count==before,"metadata discovery should be cached")
local first=families:page("compound","dhamma")
assert(first.total==578 and #first.items==20 and first.has_more and first.next_offset==20)
assert(db.query_count-before==2,"one opened payload and one exact batch for twenty members")
local all,offset={},0
repeat
    local page=families:page("compound","dhamma",offset)
    assert(#page.items<=20 and page.total==578 and not page.error)
    for _,item in ipairs(page.items) do
        all[#all+1]=item
        if item.available then
            assert(item.id and db:senses({item.id})[1].lemma_1==item.lemma,"family identity must stay exact")
        end
    end
    offset=page.next_offset
until not page.has_more
assert(#all==578)
local root_groups=families:groupsForRoot({root="√har 2"})
assert(#root_groups==6,"numbered root cards discover all their families")
for _,group in ipairs(root_groups) do assert(group.kind=="root" and group.key:sub(1,#"√har 2 ")=="√har 2 ") end
local word=families:page("word","kakkasa")
assert(word.total==6 and #word.items==6 and not word.has_more)
local numbered
for _,item in ipairs(word.items) do if item.lemma=="kakkasa 2" then numbered=item end end
assert(numbered and numbered.available and db:senses({numbered.id})[1].lemma_1=="kakkasa 2")
local absent=families:page("word","does-not-exist' OR 1=1 --")
assert(absent.total==0 and #absent.items==0,"hostile keys remain bound exact misses")
assert(not pcall(function()families:page("word;DROP TABLE lookup","x")end))
assert(not pcall(function()families:page("word","x",-1)end))
assert(not pcall(function()families:page("word","x",0,101)end))
-- Thematic sets: "; "-separated names containing spaces.
local sariputta=db:detail(db:sensesByLemma({"sāriputta"})[1].id)
local sets={}
for _,group in ipairs(families:groupsForDetail(sariputta)) do
    if group.kind=="set" then sets[#sets+1]=group.key end
end
assert(table.concat(sets,"|")=="great disciples|names of arahants|names of monks","sāriputta's thematic sets")
local disciples=families:page("set","great disciples")
assert(disciples.total==118 and #disciples.items==20 and disciples.has_more and disciples.items[1].available)
db:close()
print("PASS: optional-family metadata, 578 paged compounds, exact numbered members, root/word groups, thematic sets, and bound SQL")
