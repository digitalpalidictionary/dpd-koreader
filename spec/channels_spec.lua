local Json = require("json")
local Lookup = require("dpd/lookup")
local Render = require("ui/dpd_render")
local Navigation = require("dpd/navigation")
local Direct = require("dpd/direct")

local function fixture()
    local file = assert(io.open("spec/fixtures/lookup_channels.json", "rb"))
    local snapshot = Json.decode(file:read("*a")); file:close()
    local db = { rows=snapshot.lookup, records={}, root_records={}, fuzzy_calls=0, fuzzy_rows={} }
    for _, row in ipairs(snapshot.senses) do db.records[row.id] = row end
    for _, row in ipairs(snapshot.roots) do db.root_records[row.root] = row end
    function db:lookup(key) return self.rows[key] end
    function db:lookupMany(keys)
        local out={}; for _, key in ipairs(keys) do if self.rows[key] then out[#out+1]=self.rows[key] end end; return out
    end
    function db:senses(ids)
        local out={}; for _, id in ipairs(ids) do if self.records[id] then out[#out+1]=self.records[id] end end; return out
    end
    function db:sensesByLemma(lemmas)
        local out={}; for _, lemma in ipairs(lemmas) do for _, row in pairs(self.records) do
            if row.lemma_1==lemma then out[#out+1]=row end
        end end; return out
    end
    function db:roots(keys)
        local out={}; for _, key in ipairs(keys) do if self.root_records[key] then out[#out+1]=self.root_records[key] end end; return out
    end
    function db:fuzzy(_,_,offset,limit)
        self.fuzzy_calls=self.fuzzy_calls+1
        local out={}; for i=(offset or 0)+1,math.min(#self.fuzzy_rows,(offset or 0)+(limit or 20)) do out[#out+1]=self.fuzzy_rows[i] end; return out
    end
    function db:fuzzyCount() return #self.fuzzy_rows end
    return Lookup.new(db),db
end

local function html(value) return Render.render(value, Navigation.new(value):current()) end
local function row(key, fields) fields.lookup_key=key; return fields end

describe("upstream lookup channel semantics",function()
    it("continues beyond an English-only capitalized row to Pali senses",function()
        local lookup,db=fixture()
        local value=lookup:get("Buddha")
        assert.is_true(value.found); assert.equal("buddha",value.query)
        assert.equal("Buddha",value.original); assert.equal("ci",value.matched_via)
        assert.equal(2,#value.senses); assert.equal(0,db.fuzzy_calls)
        assert.is_truthy(html(value):find("buddha 1",1,true))
    end)
    it("preserves literal abbreviation metadata alongside lowercase lexical content",function()
        local lookup,db=fixture()
        db.rows.Buddha.abbrev_other='[{"source":"CST","meaning":"Example source abbreviation"}]'
        local value=lookup:get("Buddha")
        assert.equal(2,#value.senses); assert.equal(1,#value.abbrev_other)
        assert.is_truthy(html(value):find("Example source abbreviation",1,true))
        assert.is_truthy(html(value):find("buddha 1",1,true))
    end)
    it("resolves actual spelling references without hiding their target content",function()
        local lookup=fixture()
        local hoti=lookup:get("hotī")
        assert.equal("hotī",hoti.query); assert.equal("spelling",hoti.references[1].kind)
        assert.equal("hotīti",hoti.references[1].target)
        assert.is_true(hoti.references[1].model.found)
        assert.is_true(#hoti.references[1].model.senses>0)
        assert.is_truthy(html(hoti):gsub("<[^>]+>", ""):find("hoti + iti",1,true))
        local sajja=lookup:get("sajjasīti")
        assert.equal("sajjesīti",sajja.references[1].target)
        assert.equal(0,#sajja.references[1].model.senses)
        assert.is_true(#sajja.references[1].model.deconstructions>0)
        assert.is_truthy(html(sajja):find("Analyses",1,true))
    end)
    it("keeps headwords, deconstructions, references and metadata independent",function()
        local lookup,db=fixture()
        db.rows.mixed=row("mixed",{headwords='[48511]',deconstructor='["buddha + hotī"]',
            roots='["√har 2"]',spelling='["sajjasīti"]',abbrev=db.rows.loc.abbrev,
            grammar='[["buddha","noun","masc nom sg"]]',variant='{"CST":{"VIN1":[["context","reading note"]]}}'})
        local value=lookup:get("mixed")
        assert.equal(1,#value.senses); assert.equal(1,#value.deconstructions)
        assert.equal(1,#value.roots); assert.equal(1,#value.references)
        assert.equal(1,#value.grammar); assert.equal(1,#value.variants)
        assert.equal("locative case",value.abbrev.meaning)
        assert.is_true(value.components["hotī"].total>0)
        assert.is_truthy(html(value):find("Incorrect spelling of",1,true))
    end)
    it("recognizes numbered roots, structured abbreviations and other-source abbreviations",function()
        local lookup=fixture()
        local roots=lookup:get("√har")
        assert.equal(4,#roots.roots); assert.equal("√har 2",roots.roots[2].root)
        assert.equal("take, seize",roots.roots[2].root_meaning)
        assert.is_true(lookup:get("akkh").found)
        local loc=lookup:get("loc")
        assert.equal("locative case",loc.abbrev.meaning)
        assert.is_truthy(html(loc):find("<b>loc</b>",1,true))
        assert.is_falsy(html(loc):find('"meaning"',1,true))
        assert.is_true(#lookup:get("dī").abbrev_other>0)
        assert.is_true(lookup:get("di").references[1].model.found)
    end)
    it("distinguishes canonical equivalence and input aliases from approximation",function()
        local lookup,db=fixture()
        local matrix={
            {"dhammā","dhammā"},{"ānanda","ānanda"},{"saŋ","saṃ"},
            {"bhikkhave’ti","bhikkhaveti"},{"yo’dha","yodha"},{"tass’eva","tasseva"},
            {"akaṭa-anudhammena","akaṭaanudhammena"},{"akaṇha-asukkaṃ","akaṇhaasukkaṃ"},
        }
        for _,case in ipairs(matrix) do
            local value=lookup:get(case[1]); assert.is_true(value.found,case[1])
            assert.equal(case[2],value.query); assert.equal(case[1],value.original)
            assert.equal(0,#value.suggestions)
        end
        assert.equal("alias",lookup:get("akaṭa-anudhammena").matched_via)
        assert.equal("DN1-13",lookup:get("DN1-13").query)
        db.rows['a-b']=row('a-b',{headwords='[48511]'})
        db.rows.ab=row('ab',{headwords='[48512]'})
        assert.equal(48511,lookup:get('a-b').senses[1].id)
        assert.equal(0,db.fuzzy_calls)
    end)
    it("treats variant-only, grammar-only and help-only rows as their own content",function()
        local lookup,db=fixture()
        db.rows.context=row("context",{variant='{"CST":{"VIN1":[["quoted text","a textual reading"]]}}'})
        db.rows.parseonly=row("parseonly",{grammar='[["buddha","noun","masc nom sg"]]'})
        db.rows.helponly=row("helponly",{help='"Useful <b>help</b>"'})
        assert.is_true(lookup:get("context").found)
        assert.equal(0,#lookup:get("context").references)
        assert.equal("VIN1",lookup:get("context").variants[1].book)
        assert.is_true(lookup:get("parseonly").found)
        assert.is_truthy(html(lookup:get("helponly")):find("<b>DPD help:</b> Useful <b>help</b>",1,true))
    end)
    it("rescues the real variant-only vanditva without offering its own empty card",function()
        local lookup,db=fixture()
        db.fuzzy_rows={db.rows.vanditva,db.rows["vanditvā"]}
        local value=lookup:get("vanditva")
        assert.is_true(value.single_suggestion)
        assert.equal(1,#value.suggestions)
        assert.equal("vanditvā",value.suggestions[1].query)
        assert.equal(66262,value.suggestions[1].model.senses[1].id)
        assert.equal(1,#value.variants)
        assert.is_true(Lookup.directHit(value))
        local frame=Navigation.new(value):current()
        local rendered=Render.render(value,frame)
        assert.is_truthy(rendered:find("variant reading",1,true))
        assert.is_truthy(rendered:find("+2 more",1,true))
        assert.is_falsy(rendered:find("dpd:suggestion/",1,true))
        frame.suggestions[1].attestations_open=true
        rendered=Render.render(value,frame)
        local _,occurrences=rendered:gsub("CST VV: “vanditva %(sī%.%)”", "")
        assert.equal(1,occurrences,"duplicate source notes appear once")
        assert.is_truthy(rendered:find("MST VV:",1,true))
        assert.is_truthy(rendered:find("SYA VVa:",1,true))
        frame.variants_open=true
        assert.is_truthy(Render.render(value,frame):find("BJT · VV",1,true))
        assert.equal(0,#lookup:get("vanditva",{approximate=false}).suggestions)
    end)
    it("keeps unmatched context visible manually and lets direct lookup fall through",function()
        local lookup,db=fixture()
        db.fuzzy_rows={db.rows.vanditva}
        local value=lookup:get("vanditva")
        assert.is_true(value.found)
        assert.is_false(Lookup.directHit(value))
        assert.equal(0,#value.suggestions)
        assert.is_true(Navigation.new(value):current().variants_open)
        assert.is_truthy(html(value):find("BJT · VV",1,true))
        local dictionary={onLookupWord=function()return "normal" end}
        local hook=Direct.install(dictionary,function(word)return Lookup.directHit(lookup:get(word)) end)
        assert.equal("normal",dictionary:onLookupWord("vanditva"))
        assert.is_true(Lookup.directHit(lookup:get("loc")))
        assert.is_true(Lookup.directHit(lookup:get("√har")))
        hook:remove()
    end)
    it("keeps metadata-only neighbours out of variant rescue and preserves ambiguous choices",function()
        local lookup,db=fixture()
        db.rows.othercontext=row("othercontext",{variant=db.rows.vanditva.variant})
        db.fuzzy_rows={db.rows.vanditva,db.rows.othercontext,db.rows["vanditvā"],db.rows.buddha}
        local value=lookup:get("vanditva")
        assert.equal(2,#value.suggestions)
        assert.is_false(value.single_suggestion)
        assert.equal("vanditvā",value.suggestions[1].query)
        assert.equal(2,value.suggestion_total)
    end)
    it("removes soft hyphens without adding a rewrite notice or approximating",function()
        local lookup,db=fixture()
        local value=lookup:get("dham­ma")
        assert.equal("dhamma",value.query)
        assert.is_true(value.found)
        assert.equal(0,db.fuzzy_calls)
        assert.is_falsy(html(value):find("Selected:",1,true))
        assert.is_falsy(html(lookup:get("saṁ")):find("Selected:",1,true))
        assert.is_falsy(html(lookup:get("dhammā")):find("Selected:",1,true))
        assert.is_truthy(html(lookup:get("dham-ma")):find("Selected:",1,true))
        assert.is_truthy(html(lookup:get("bhikkhave’ti")):find("Selected:",1,true))
    end)
    it("keeps all real parses and resolves bare and numbered grammatical lemmas",function()
        local lookup=fixture()
        assert.equal(9,#lookup:get("dhammaṃ").grammar)
        assert.equal(28,#lookup:get("dhammā").grammar)
        assert.equal(19,#lookup:get("kā").grammar)
        assert.is_true(lookup:headword("dhamma").found)
        assert.is_true(lookup:headword("buddha").found)
        assert.equal(48511,lookup:headword("buddha 1").senses[1].id)
    end)
    it("bounds reference chains and cycles without caching a broken traversal",function()
        local lookup,db=fixture()
        db.rows.A=row("A",{see='["B"]'});db.rows.B=row("B",{spelling='["C"]'})
        db.rows.C=row("C",{headwords='[48511]'})
        assert.is_true(lookup:get("A",{approximate=false}).found)
        db.rows.C.headwords=nil;db.rows.C.see='["A"]'
        local fresh=Lookup.new(db)
        local cyclic=fresh:get("A",{approximate=false})
        assert.is_true(cyclic.found)
        local function terminal(value)
            local reference = value.references[1]
            return reference.model and terminal(reference.model) or reference
        end
        assert.equal("cycle",terminal(cyclic).status)
        assert.is_true(fresh:get("B",{approximate=false}).found)
        assert.is_truthy(html(cyclic):find("Circular DPD reference",1,true))
        for i=1,8 do db.rows["chain"..i]=row("chain"..i,{see=Json.encode({"chain"..(i+1)})}) end
        db.rows.chain9=row("chain9",{headwords='[48511]'})
        local deep=Lookup.new(db):get("chain1",{approximate=false})
        assert.is_true(deep.found);assert.equal("depth_limit",terminal(deep).status)
        assert.is_truthy(html(deep):find("DPD reference chain is too deep",1,true))
    end)
    it("shows terminal exact reference summaries for component chains without fuzzy substitutions",function()
        local lookup,db=fixture()
        db.rows.A=row("A",{spelling='["B"]'});db.rows.B=row("B",{see='["buddha 1"]'})
        db.rows.parent=row("parent",{deconstructor='["A + suffix"]'})
        db.fuzzy_rows={db.rows.buddha}
        local value=lookup:get("parent")
        assert.equal(48511,value.components.A.senses[1].id)
        assert.equal(0,value.components.suffix.total);assert.equal(0,db.fuzzy_calls)
        assert.is_false(lookup:get("suffix",{approximate=false}).found)
        assert.equal(0,db.fuzzy_calls)
        assert.is_true(lookup:get("suffix").found)
    end)
    it("bounds reference work while preserving the row's own reference before component summaries",function()
        local lookup,db=fixture()
        local targets={}
        for i=1,40 do
            local key="target"..i
            targets[i]=key;db.rows[key]=row(key,{headwords='[48511]'})
        end
        db.rows.parts=row("parts",{see=Json.encode(targets)})
        db.rows.priority=row("priority",{see='["buddha"]',deconstructor='["parts + suffix"]'})
        local value=lookup:get("priority",{approximate=false})
        assert.is_true(value.references[1].model.found)
        assert.equal("buddha",value.references[1].target)
        local bounded=Lookup.new(db):get("parts",{approximate=false})
        assert.equal(40,#bounded.references)
        assert.is_true(bounded.references[32].model.found)
        assert.equal("limit",bounded.references[33].status)
    end)
    it("accepts correction notes while unsupported exact rows still use fuzzy or normal fallback",function()
        local lookup,db=fixture()
        db.rows.dead=row("dead",{spelling='["absent"]'})
        local value=lookup:get("dead",{approximate=false})
        assert.is_true(value.found);assert.equal("missing",value.references[1].status)
        db.rows.shadow=row("shadow",{epd='[["English","Pali"]]'})
        db.fuzzy_rows={db.rows.buddha}
        assert.is_true(lookup:get("shadow").found)
        assert.equal("fuzzy",lookup:get("shadow").matched_via)
        db.fuzzy_rows={}
        local calls=0;local dictionary={onLookupWord=function() calls=calls+1;return "normal" end}
        local fresh=Lookup.new(db)
        local hook=Direct.install(dictionary,function(word)return Lookup.directHit(fresh:get(word)) end)
        assert.is_true(dictionary:onLookupWord("dead"));assert.equal(0,calls)
        assert.equal("normal",dictionary:onLookupWord("shadow"));assert.equal(1,calls)
        hook:remove()
    end)

    it("preserves unresolved component corrections without approximate definitions",function()
        local lookup,db=fixture()
        db.rows.mistake=row("mistake",{spelling='["correct phrase"]'})
        db.rows.compound=row("compound",{deconstructor='["mistake + suffix"]'})
        db.fuzzy_rows={db.rows.buddha}
        local value=lookup:get("compound")
        assert.equal(0,value.components.mistake.total)
        assert.same({{kind="spelling",target="correct phrase"}},value.components.mistake.reference_targets)
        assert.equal(0,db.fuzzy_calls)
        assert.is_truthy(html(value):find("Incorrect spelling of correct phrase",1,true))
    end)
    it("keeps every ranked fuzzy candidate reachable without mutating cached result state",function()
        local lookup,db=fixture()
        for i=1,25 do
            local key="choice"..i
            local fields=i%3==0 and {deconstructor='["buddha + suffix"]'} or
                i%3==1 and {headwords='[48511]'} or {headwords='[48511]',deconstructor='["buddha + suffix"]'}
            db.rows[key]=row(key,fields);db.fuzzy_rows[i]=db.rows[key]
        end
        local value=lookup:get("missing")
        assert.equal(20,#value.suggestions);assert.equal(25,value.suggestion_total)
        local more=lookup:more(value)
        assert.equal(25,#more.suggestions);assert.equal(20,#value.suggestions)
        assert.equal(25,more.suggestion_offset)
        assert.equal(25,#lookup:more(more).suggestions)
        assert.equal(20,#lookup:get("missing").suggestions)
        for _,suggestion in ipairs(more.suggestions) do assert.is_true(suggestion.model.found) end
    end)
    it("batches page senses and shared component rows while retaining exact reference summaries",function()
        local lookup,db=fixture()
        local senses_calls,component_calls=0,0
        local senses,lookupMany=db.senses,db.lookupMany
        function db:senses(ids) senses_calls=senses_calls+1;return senses(self,ids) end
        function db:lookupMany(keys) component_calls=component_calls+1;return lookupMany(self,keys) end
        for i=1,20 do
            local key="choice"..i
            db.rows[key]=row(key,{headwords='[48511]',deconstructor='["buddha + hotī + suffix"]'})
            db.fuzzy_rows[i]=db.rows[key]
        end
        local value=lookup:get("missing")
        assert.equal(20,#value.suggestions)
        -- Ordinary IDs/components are batched; curated references may fetch
        -- additional rows, but never one sense query per candidate.
        assert.is_true(senses_calls<5)
        assert.is_true(component_calls<5)
        for _,suggestion in ipairs(value.suggestions) do
            assert.equal(48511,suggestion.model.senses[1].id)
            assert.is_true(suggestion.model.components["hotī"].total>0)
            assert.equal(0,suggestion.model.components.suffix.total)
        end
    end)
    it("reuses exact lemma senses but resolves complete clean-lemma homonyms",function()
        local lookup,db=fixture()
        local numbered=lookup:get("buddha")
        local original=db.sensesByLemma
        function db:sensesByLemma() error("exact known sense must not query") end
        assert.equal(48511,lookup:headword("buddha 1",numbered).senses[1].id)
        db.sensesByLemma=original
        local full=lookup:headword("buddha",{senses={numbered.senses[1]}})
        assert.equal(2,#full.senses)
    end)
    it("skips blank-reference fuzzy pages and adjusts counts without dropping useful notes",function()
        local lookup,db=fixture()
        for i=1,20 do
            local key="deadchoice"..i
            db.rows[key]=row(key,{see='["", " "]'});db.fuzzy_rows[i]=db.rows[key]
        end
        db.fuzzy_rows[21]=db.rows.buddha
        local value=lookup:get("missing")
        assert.is_true(value.found);assert.equal(1,#value.suggestions)
        assert.equal("buddha",value.suggestions[1].query)
        assert.equal(1,value.suggestion_total);assert.equal(21,value.suggestion_offset)
        assert.is_falsy(html(value):find("Show more",1,true))
    end)
end)

describe("prior-art lookup fixes",function()
    it("finds corpus closing-double-quote ti spellings while keeping literal precedence",function()
        local lookup,db=fixture()
        for _, input in ipairs({"hotī”ti",'hotī"ti'}) do
            local value=lookup:get(input)
            assert.is_true(value.found,input); assert.equal("hotīti",value.query)
            assert.equal("alias",value.matched_via); assert.equal(0,db.fuzzy_calls)
            assert.is_truthy(html(value):find("DPD form",1,true))
        end
        local literal,literal_db=fixture()
        literal_db.rows['hotī"ti']=row('hotī"ti',{headwords='[48511]'})
        assert.equal('hotī"ti',literal:get('hotī"ti').query)
    end)
    it("keeps valid senses when an optional channel is damaged",function()
        local lookup,db=fixture()
        db.rows.damaged=row("damaged",{headwords='[48511]',variant='{"CST":',help='"ok"'})
        local value=lookup:get("damaged")
        assert.is_true(value.found); assert.equal(1,#value.senses)
        assert.equal(0,#value.variants); assert.equal("ok",value.help)
        assert.same({"variant readings"},value.damaged)
        assert.is_truthy(html(value):find("Some DPD details could not be read. Affected data: variant readings",1,true))
        assert.is_falsy(html(lookup:get("hoti")):find("Unreadable",1,true))
    end)
    it("still rejects damaged headword identities",function()
        local lookup,db=fixture()
        db.rows.badids=row("badids",{headwords='[48511,'})
        assert.has_error(function() lookup:get("badids") end)
        db.rows.badtype=row("badtype",{headwords='["x"]'})
        assert.has_error(function() lookup:get("badtype") end)
    end)
    it("rejects missing referenced headwords instead of dropping definitions",function()
        for _, ids in ipairs({'[999999]', '[48511,999999]'}) do
            local lookup,db=fixture()
            db.rows.dangling=row("dangling",{headwords=ids})
            assert.has_error(function() lookup:get("dangling") end, "Missing DPD headword for ID 999999")
        end
    end)
    it("flags incomplete grammar records while preserving valid senses",function()
        for _, ids in ipairs({'', '[48511]'}) do
            local lookup,db=fixture()
            db.rows.badgrammar=row("badgrammar",{headwords=ids,grammar='[["buddha","noun"]]'})
            local value=lookup:get("badgrammar",{approximate=false})
            assert.same({"grammar"},value.damaged)
            assert.equal(ids=='' and 0 or 1,#value.senses)
            assert.is_truthy(html(value):find("Affected data: grammar",1,true))
        end
    end)
    it("resolves a typed numbered headword through the exact headword route",function()
        local lookup,db=fixture()
        local value=lookup:get("dhamma 1.01")
        assert.is_true(value.found); assert.equal("headword",value.matched_via)
        assert.equal(1,#value.senses); assert.equal("dhamma 1.01",value.senses[1].lemma_1)
        assert.equal(0,db.fuzzy_calls)
        assert.is_false(lookup:get("dhamma 99").found)
        -- A bare number is not reinterpreted as a headword or ID.
        local calls=0; local original=db.sensesByLemma
        function db:sensesByLemma(...) calls=calls+1; return original(self,...) end
        lookup:get("48511")
        assert.equal(0,calls)
    end)
end)
