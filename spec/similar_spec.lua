local Json = require("json")
local Lookup = require("dpd/lookup")
local Variant = require("dpd/variant")
local Render = require("ui/dpd_render")
local Navigation = require("dpd/navigation")

local function fixture()
    local file=assert(io.open("spec/fixtures/lookup_channels.json","rb"))
    local snapshot=Json.decode(file:read("*a"));file:close()
    local db={rows=snapshot.lookup,records={},fuzzy_calls=0,groups={}}
    for _,record in ipairs(snapshot.senses) do db.records[record.id]=record end
    function db:lookup(key) return self.rows[key] end
    function db:lookupMany(keys)
        local out={};for _,key in ipairs(keys) do if self.rows[key] then out[#out+1]=self.rows[key] end end;return out
    end
    function db:senses(ids)
        local out={};for _,id in ipairs(ids) do if self.records[id] then out[#out+1]=self.records[id] end end;return out
    end
    function db:fuzzy(key,_,offset,limit)
        self.fuzzy_calls=self.fuzzy_calls+1
        local values,out=self.groups[key] or {},{}
        for i=offset+1,math.min(#values,offset+limit) do out[#out+1]=values[i] end
        return out
    end
    function db:fuzzyCount(key) return #(self.groups[key] or {}) end
    db.groups.indakile={db.rows['indakhīle']}
    db.groups.avaharisama={db.rows['avaharissāma']}
    db.groups.samantayitva={db.rows['sammantayitvā'],db.rows['samantayitvā']}
    return Lookup.new(db),db
end

local function html(value) return Render.render(value,Navigation.new(value):current()) end

describe("similar-form paging limits and filtering",function()
    it("never offers a neighbour that has only variant readings",function()
        local lookup,db=fixture()
        db.rows["onlyreading"]={lookup_key="onlyreading",variant='{"CST":{"VIN1":[["ctx","onlyreading"]]}}'}
        db.groups[require("dpd/normalize").fuzzy("onlyredding")]={db.rows["onlyreading"]}
        local value=lookup:get("onlyredding")
        assert.equal(0,#value.suggestions)
        assert.is_false(value.found)
    end)
    it("treats Show more past the last candidate and an empty group as no-ops",function()
        local lookup,db=fixture()
        local value=lookup:get("avaharissāmā")
        local calls=db.fuzzy_calls
        local again=lookup:more(value)
        assert.equal(calls,db.fuzzy_calls)
        assert.equal(1,#again.suggestions)
        local empty=lookup:get("nothinghere")
        calls=db.fuzzy_calls
        assert.equal(0,#lookup:more(empty).suggestions)
        assert.equal(calls,db.fuzzy_calls)
    end)
    it("evicts the oldest cached result after 100 lookups and rebuilds it on demand",function()
        local lookup,db=fixture()
        local reads=0
        local read=db.lookup
        function db:lookup(key) reads=reads+1; return read(self,key) end
        lookup:get("avaharissāma")
        reads=0
        lookup:get("avaharissāma")
        assert.equal(0,reads)
        for i=1,100 do lookup:get("missing"..i,{approximate=false}) end
        assert.equal(100,#lookup.order)
        reads=0
        local again=lookup:get("avaharissāma")
        assert.is_true(reads>0)
        assert.equal("avaharati",again.senses[1].lemma_1)
    end)
end)
local function reading(note,context) return {source="CST",book="VIN1",note=note,context=context or "context"} end

describe("DPD reading attestation",function()
    it("keeps reading labels when inline formatting splits the word",function()
        local lookup,db=fixture()
        db.rows['indakhīle'].variant='{"CST":{"VIN1":[["context","inda<b>khile</b> (ka.)"]]}}'
        local value=lookup:get("indakhile")
        assert.equal(1,#value.suggestions[1].attestations)
        local page=html(value)
        assert.is_truthy(page:find("variant reading (CST VIN1)",1,true))
        assert.is_falsy(page:find("· similar form",1,true))
        assert.equal(0,#Variant.matches("indakhile",{reading("another (inda<b>khile</b>)")}))
    end)
    it("keeps words across HTML line breaks separate instead of attesting their concatenation",function()
        for _, tag in ipairs({"<br>","<br/>","<br />","<BR>"}) do
            local note="inda"..tag.."khile (ka.)"
            assert.equal(0,#Variant.matches("indakhile",{reading(note)}),tag)
            assert.equal(1,#Variant.matches("khile",{reading(note)}),tag)
            local lookup,db=fixture()
            db.rows['indakhīle'].variant=Json.encode({CST={VIN1={{"context",note}}}})
            local value=lookup:get("indakhile")
            assert.equal(0,#value.suggestions[1].attestations,tag)
            local page=html(value)
            assert.is_truthy(page:find("· similar form",1,true),tag)
            assert.is_falsy(page:find("variant reading (CST VIN1)",1,true),tag)
        end
    end)
    it("matches whole reading words with canonical normalization and preserved vowel length",function()
        local record=reading("indakhile (ka.)")
        assert.equal(record,Variant.matches("indakhile",{record})[1])
        assert.equal(record,Variant.matches("INDAKHILE",{record})[1])
        assert.equal(1,#Variant.matches("dhammā",{reading("dhammā (ka.)")}))
        assert.equal(0,#Variant.matches("dhamma",{reading("dhammā (ka.)")}))
        assert.equal(1,#Variant.matches("saṁ",{reading("saṃ (ka.)")}))
    end)
    it("does not attest substrings, context, provenance or text following annotations",function()
        for _,record in ipairs({reading("xindakhile (ka.)"),reading("indakhilex (ka.)"),
            reading("another reading","indakhile"),reading("another (indakhile)"),
            reading("another (ka.) indakhile is discussed later"),reading("another [indakhile]")}) do
            assert.equal(0,#Variant.matches("indakhile",{record}))
        end
        assert.equal(0,#Variant.matches("ka",{reading("indakhile (ka.)")}))
        assert.equal(0,#Variant.matches("foo",{reading("fooébar (ka.)")}))
    end)
    it("ignores grammar citations and source lists but keeps every reading entry",function()
        for _,form in ipairs({"ka","rū","nī","60"}) do
            assert.equal(0,#Variant.matches(form,{reading("ka. 60; rū. 177; nī. 207")}))
        end
        assert.equal(0,#Variant.matches("pāci",{reading("pāci. 130")}))
        assert.equal(0,#Variant.matches("saṃ",{reading("kimaṅga (sī.) cūḷava. 331; saṃ. ni. 5.1020")}))
        assert.equal(0,#Variant.matches("machasaṃ",{reading("tā – machasaṃ")}))
        assert.equal(1,#Variant.matches("tā",{reading("tā – machasaṃ")}))
        -- Later entries after ";" are readings too.
        assert.equal(1,#Variant.matches("mūsikukkuro",{reading("mūsikukkaro – machasaṃ; mūsikukkuro – sīmu8, syā")}))
        -- SYA writes sources first and ends the reading with a period.
        assert.equal(1,#Variant.matches("gāvī",{reading("ma. gāvī.")}))
    end)
end)

describe("single similar-form main view",function()
    it("shows indakhīle's two senses with both actual source readings and no chooser",function()
        local lookup,db=fixture()
        local value=lookup:get("indakhile")
        assert.is_true(value.single_suggestion)
        assert.equal("indakhile",value.query)
        assert.equal("fuzzy",value.matched_via)
        assert.equal(2,#value.suggestions[1].model.senses)
        assert.equal(2,#value.suggestions[1].attestations)
        local frame=Navigation.new(value):current()
        local body=Render.render(value,frame)
        assert.is_truthy(body:find("indakhile → indakhīle</p>",1,true))
        assert.is_truthy(body:find("variant reading (CST VIN1) · +1 more",1,true))
        assert.is_falsy(body:find("indakhile (ka.)",1,true))
        frame.suggestions[1].attestations_open=true
        body=Render.render(value,frame)
        assert.is_truthy(body:find("CST VIN1: “indakhile (ka.)”",1,true))
        assert.is_truthy(body:find("MST VIN1: “indakhile (mr)”",1,true))
        assert.is_truthy(body:find("indakhīla 1",1,true))
        assert.is_truthy(body:find("indakhīla 2",1,true))
        assert.is_falsy(body:find("KOReader dictionary",1,true))
        assert.is_falsy(body:find('class="similar"',1,true))
        assert.is_falsy(body:find("dpd:suggestion/1",1,true))
        assert.is_falsy(body:find('dpd:similar/1"',1,true))
        local count=db.fuzzy_calls;lookup:get("“indakhile”")
        assert.equal(count,db.fuzzy_calls)
    end)
    it("uses the similar-form label for avaharissāmā and opens ambiguous results",function()
        local lookup=fixture()
        local single=lookup:get("avaharissāmā")
        assert.is_true(single.single_suggestion)
        assert.is_truthy(html(single):find("avaharissāmā → avaharissāma · similar form",1,true))
        assert.is_truthy(html(single):find("avaharati",1,true))
        assert.is_falsy(html(single):find("variant reading",1,true))
        local multiple=lookup:get("saṃmantayitvā")
        assert.is_false(multiple.single_suggestion)
        local frame=Navigation.new(multiple):current()
        assert.is_true(frame.suggestions[1].open);assert.is_true(frame.suggestions[2].open)
        assert.is_truthy(html(multiple):find("dpd:suggestion/2",1,true))
        assert.equal(0,#multiple.suggestions[1].attestations,"context alone must not upgrade the label")
    end)
    it("retains exact matches and exact-only component misses",function()
        local lookup,db=fixture()
        local exact=lookup:get("indakhīle")
        assert.is_nil(exact.single_suggestion);assert.equal(2,#exact.senses)
        local component=lookup:get("indakhile",{approximate=false})
        assert.is_false(component.found);assert.equal(0,#component.suggestions)
        assert.equal(0,db.fuzzy_calls)
    end)
    it("preserves the direct main view's detail and parent scroll state on Back",function()
        local lookup=fixture()
        local value=lookup:get("indakhile")
        local nav=Navigation.new(value)
        local frame,action=nav:resolve("dpd:similar/1/sense/13724")
        assert.equal("dpd:sense/13724",action)
        nav:toggleSense(13724,{grammar_line="masc, in comps"},frame)
        nav:push(lookup:get("buddha"),.45)
        assert.is_true(nav:back())
        assert.equal("indakhile",nav:current().model.query)
        assert.equal(.45,nav:current().ratio)
        assert.is_true(nav:current().suggestions[1].expanded[13724])
        assert.is_truthy(Render.render(value,nav:current()):find("in comps",1,true))
    end)
    it("puts attested alternatives first while preserving the original rank of other candidates",function()
        local lookup,db=fixture()
        db.rows.other={lookup_key="other",headwords='[13724]'}
        db.rows.last={lookup_key="last",headwords='[13725]'}
        db.groups.indakile={db.rows.other,db.rows['indakhīle'],db.rows.last}
        local value=lookup:get("indakhile")
        assert.is_false(value.single_suggestion)
        assert.equal("indakhīle",value.suggestions[1].query)
        assert.equal("other",value.suggestions[2].query)
        assert.equal("last",value.suggestions[3].query)
    end)
    it("appends a ranked batch without moving displayed candidates or opening a third card",function()
        local lookup,db=fixture()
        local values={}
        for i=1,41 do
            local key="choice"..i;db.rows[key]={lookup_key=key,headwords='[13724]'};values[i]=db.rows[key]
        end
        values[22]=db.rows['indakhīle'];db.groups.indakile=values
        local value=lookup:get("indakhile")
        local nav=Navigation.new(value)
        local old=nav:current().suggestions[1]
        old.expanded[13724]=true
        local more=lookup:more(value);nav:extend(more)
        for i=1,20 do
            assert.equal(value.suggestions[i],more.suggestions[i],"displayed order must stay unchanged")
        end
        assert.equal("indakhīle",more.suggestions[21].query,"attested forms lead their new batch")
        assert.equal("choice21",more.suggestions[22].query)
        assert.equal("choice23",more.suggestions[23].query)
        assert.equal(old,nav:current().suggestions[1])
        assert.is_true(old.expanded[13724])
        local opened=0
        for _,child in ipairs(nav:current().suggestions) do
            if child.open then opened=opened+1 end
        end
        assert.equal(2,opened)
        assert.equal(20,#value.suggestions,"cached array must remain unchanged")

        -- Manual open/closed state also survives another append.
        nav:toggleSuggestion(1);nav:toggleSuggestion(21)
        local last=lookup:more(more);nav:extend(last)
        for i=1,40 do assert.equal(more.suggestions[i],last.suggestions[i]) end
        assert.is_false(nav:current().suggestions[1].open)
        assert.is_true(nav:current().suggestions[21].open)
        assert.is_false(nav:current().suggestions[41].open)
        assert.is_true(old.expanded[13724])
    end)
    it("waits for the complete set before flattening one valid candidate among blank notes",function()
        local lookup,db=fixture()
        local values={db.rows['indakhīle']}
        for i=2,21 do
            local key="dead"..i;db.rows[key]={lookup_key=key,see='["", " "]'};values[i]=db.rows[key]
        end
        db.groups.indakile=values
        local value=lookup:get("indakhile")
        assert.equal(1,#value.suggestions);assert.is_false(value.single_suggestion)
        local nav=Navigation.new(value)
        assert.is_true(nav:current().suggestions[1].open)
        local more=lookup:more(value);nav:extend(more)
        assert.is_true(more.single_suggestion);assert.equal(1,more.suggestion_total)
        assert.is_true(nav:current().suggestions[1].open)
        assert.is_truthy(Render.render(more,nav:current()):find("indakhīla 1",1,true))
    end)
end)
