local Lookup = require("dpd/lookup")
local Render = require("ui/dpd_render")
local Navigation = require("dpd/navigation")
local Direct = require("dpd/direct")

local function fixture()
    local rows = {
        ["ajjha"] = {lookup_key="ajjha",headwords="[1254]"},
        ["dashlit"] = {lookup_key="dashlit",headwords="[1255]"},
        ["saṃvidāvahāro"] = {lookup_key="saṃvidāvahāro",headwords="[61939]",
            grammar='[["saṃvidāvahāra","noun","masc nom sg"]]'},
        ["avaharissāma"] = {lookup_key="avaharissāma",headwords="[10432]",
            grammar='[["avaharati","verb","fut 1st pl"]]'},
        ["avaharissāmāti"] = {lookup_key="avaharissāmāti",headwords="[10432]",
            deconstructor='["avaharissāma + iti"]'},
        -- Headwords a part only partly covers (rakkhatiyeva, rakkhatiyā + eva).
        ["avaharissāmāpi"] = {lookup_key="avaharissāmāpi",headwords="[10432, 60749]",
            deconstructor='["avaharissāma + iti"]'},
        ["sammantayitvā"] = {lookup_key="sammantayitvā",headwords="[60749]"},
        ["samantayitvā"] = {lookup_key="samantayitvā",deconstructor='["sa + mantayitvā"]'},
        ["sammantayitvāti"] = {lookup_key="sammantayitvāti",headwords="[60749]",
            deconstructor='["sammantayitvā + iti"]'},
        -- Official mobile v0.4.20260926: two spellings lead to the same entries.
        ["rūpiyappaṭiggahaṇāpatti"] = {lookup_key="rūpiyappaṭiggahaṇāpatti",
            deconstructor='["rūpiya + paṭiggahaṇā + patti", "rūpiya + paṭiggahaṇa + āpatti"]'},
        ["rūpiya"] = {lookup_key="rūpiya",headwords="[9001]"},
        ["paṭiggahaṇā"] = {lookup_key="paṭiggahaṇā",headwords="[9002,9003]"},
        ["paṭiggahaṇa"] = {lookup_key="paṭiggahaṇa",headwords="[9003,9002]"},
        ["patti"] = {lookup_key="patti",headwords="[9004]"},
        ["āpatti"] = {lookup_key="āpatti",headwords="[9005]"},
        ["overlap"] = {lookup_key="overlap",deconstructor='["rūpiya + patti", "rūpiya + pattika"]'},
        ["pattika"] = {lookup_key="pattika",headwords="[9004,9006]"},
        ["subset"] = {lookup_key="subset",deconstructor='["pattika + patti"]'},
        ["pattikā"] = {lookup_key="pattikā",headwords="[9006]"},
        ["subset-other"] = {lookup_key="subset-other",deconstructor='["pattika + pattikā"]'},
        ["headword-subsets"] = {lookup_key="headword-subsets",headwords="[9004,9006,9007]",
            deconstructor='["pattika + iti", "middhi + iti", "middhī + iti"]'},
        ["headword-overlap"] = {lookup_key="headword-overlap",headwords="[9004,9007]",
            deconstructor='["pattika + iti"]'},
        ["headword-superset"] = {lookup_key="headword-superset",headwords="[9004]",
            deconstructor='["pattika + iti"]'},
        ["combined"] = {lookup_key="combined",deconstructor='["rūpiya + patti", "mixed + iti"]'},
        ["same-size"] = {lookup_key="same-size",deconstructor='["pattika + mixed"]'},
        ["preview"] = {lookup_key="preview",deconstructor='["broad + rūpiya"]'},
        ["mixed"] = {lookup_key="mixed",headwords="[9001,9004]"},
        ["broad"] = {lookup_key="broad",headwords="[9001,9002,9003]"},
        -- Official mobile v0.4.20260926: middhī repeats middhi's senses but
        -- adds a correction whose target has no entry.
        ["middhīti"] = {lookup_key="middhīti",deconstructor='["middhi + iti", "middhī + iti"]'},
        ["middhi"] = {lookup_key="middhi",headwords="[9007]"},
        ["middhī"] = {lookup_key="middhī",headwords="[9007]",spelling='["atthassamiddhī"]'},
        ["iti"] = {lookup_key="iti",headwords="[9008]"},
        -- midhekacce's "m + idha + ekacce": m has only other-dictionary abbreviations.
        ["mitizz"] = {lookup_key="mitizz",deconstructor='["m + iti + zz"]'},
        ["m"] = {lookup_key="m",abbrev_other='[{"source":"Cone","meaning":"masculine","notes":null}]'},
    }
    local senses = {
        [61939]={id=61939,lemma_1="saṃvidāvahāra",pos="masc",meaning_1="organized theft"},
        [10432]={id=10432,lemma_1="avaharati",pos="pr",meaning_1="takes away"},
        [1254]={id=1254,lemma_1="ajjha",pos="prefix",meaning_1="-",meaning_2="-"},
        [1255]={id=1255,lemma_1="dashlit",pos="adj",meaning_1="-",meaning_2="",meaning_lit="literal"},
        [60749]={id=60749,lemma_1="sammantayitvā",pos="abs",meaning_2="having consulted"},
        [9001]={id=9001,lemma_1="rūpiya 1",pos="nt",meaning_1="silver"},
        [9002]={id=9002,lemma_1="paṭiggahaṇa 1",pos="nt",meaning_1="accepting"},
        [9003]={id=9003,lemma_1="paṭiggahaṇa 2",pos="nt",meaning_1="learning"},
        [9004]={id=9004,lemma_1="patti 1.1",pos="fem",meaning_1="attainment"},
        [9005]={id=9005,lemma_1="āpatti 2",pos="fem",meaning_1="offence"},
        [9006]={id=9006,lemma_1="pattika",pos="adj",meaning_1="on foot"},
        [9007]={id=9007,lemma_1="middha",pos="nt",meaning_1="torpor"},
        [9008]={id=9008,lemma_1="iti",pos="ind",meaning_1="thus"},
    }
    local db = {fuzzy_calls=0}
    function db:lookup(key) return rows[key] end
    function db:lookupMany(keys)
        local out = {}
        for _, key in ipairs(keys) do if rows[key] then out[#out+1]=rows[key] end end
        return out
    end
    function db:senses(ids)
        local out = {}
        for _, id in ipairs(ids) do if senses[id] then out[#out+1]=senses[id] end end
        return out
    end
    function db:fuzzy(key)
        self.fuzzy_calls = self.fuzzy_calls + 1
        if key == "avaharisama" then return {rows["avaharissāma"]} end
        if key == "samantayitva" then return {rows["sammantayitvā"], rows["samantayitvā"]} end
        return {}
    end
    function db:detail(id)
        return {construction=id == 61939 and "saṃvida + avahāra" or ""}
    end
    return Lookup.new(db), db
end

describe("reported lookup routing", function()
    it("tells a part without a definition from one DPD lacks", function()
        local model = fixture():get("mitizz")
        local html = Render.render(model, Navigation.new(model):current())
        local _, rows = html:gsub("No DPD definition; tap the word for what DPD has.", "")
        local _, missing = html:gsub("No DPD entry for this component.", "")
        assert.same({1, 1}, {rows, missing})
        assert.is_true(html:find("<b>m</b>", 1, true) < html:find("No DPD definition", 1, true))
    end)

    it("keeps a repeated component that adds a correction note", function()
        local model = fixture():get("middhīti")
        assert.same({true, true}, model.deconstructions[1].unique)
        assert.same({true, false}, model.deconstructions[2].unique)
        local navigation = Navigation.new(model)
        navigation:toggleAnalysis(2)
        local html = Render.render(model, navigation:current())
        assert.is_truthy(html:find("Incorrect spelling of atthassamiddhī", 1, true))
    end)

    it("explains an entry once when two spellings lead to it", function()
        local lookup = fixture()
        local model = lookup:get("rūpiyappaṭiggahaṇāpatti")
        assert.same({true, true, true}, model.deconstructions[1].unique)
        -- paṭiggahaṇa is spelled differently but leads to paṭiggahaṇā's senses.
        assert.same({false, false, true}, model.deconstructions[2].unique)
        assert.is_true(model.deconstructions[2].has_new)
        local navigation = Navigation.new(model)
        navigation:toggleAnalysis(2)
        local html = Render.render(model, navigation:current())
        local _, accepting = html:gsub("accepting", "")
        assert.equal(1, accepting)
        -- Its row names the spelling that explains it; rūpiya, spelled the same, has none.
        assert.same({[2]={form="paṭiggahaṇā"}}, model.deconstructions[2].same)
        assert.is_truthy(html:find('href="dpd:component/2/2"><b>paṭiggahaṇa</b></a> '
            .. '<span class="count">· same as paṭiggahaṇā above</span>', 1, true))
        assert.is_truthy(html:find("offence", 1, true))
        -- Again from the cached model, and keeping a part that adds any new sense.
        assert.same({false, false, true}, lookup:get("rūpiyappaṭiggahaṇāpatti").deconstructions[2].unique)
        assert.same({false, true}, lookup:get("overlap").deconstructions[2].unique)
    end)
    it("names a subset's senses instead of repeating an earlier component's rows", function()
        -- patti's only sense is pattika's first, already a shown row (kammā after kamma).
        local model = fixture():get("subset")
        assert.same({true, true}, model.deconstructions[1].unique)
        assert.same({[2]=true}, model.deconstructions[1].compact)
        local html = Render.render(model, Navigation.new(model):current())
        assert.is_truthy(html:find("· only patti 1.1</span>", 1, true))
        assert.is_falsy(html:find("dpd:component-sense/1/2/9004", 1, true))
        -- pattikā picks pattika's second sense instead: its own row shows that reading.
        model = fixture():get("subset-other")
        assert.is_nil(model.deconstructions[1].compact)
        html = Render.render(model, Navigation.new(model):current())
        assert.is_truthy(html:find("dpd:component-sense/1/2/9006", 1, true))
        assert.is_falsy(html:find("· only", 1, true))
    end)
    it("compacts headword subsets including a later headword, but preserves new notes", function()
        local model = fixture():get("headword-subsets")
        local navigation = Navigation.new(model)
        local state = navigation:current()
        assert.same({true, false, false}, state.analyses)
        navigation:toggleAnalysis(2)
        navigation:toggleAnalysis(3)
        local html = Render.render(model, state)
        for i = 1, 2 do assert.same({[1]=true}, model.deconstructions[i].compact) end
        assert.is_truthy(html:find("· only patti 1.1, pattika</span>", 1, true))
        assert.is_truthy(html:find("· only middha</span>", 1, true))
        assert.is_falsy(html:find("dpd:component-sense/1/1/9004", 1, true))
        assert.is_falsy(html:find("dpd:component-sense/2/1/9007", 1, true))
        assert.is_nil(model.deconstructions[3].compact)
        assert.is_truthy(html:find("dpd:component-sense/3/1/9007", 1, true))
        assert.is_truthy(html:find("Incorrect spelling of atthassamiddhī", 1, true))
        assert.is_truthy(html:find("dpd:component/2/1", 1, true))
    end)
    it("keeps leading definitions for headword overlaps and supersets", function()
        for _, word in ipairs({"headword-overlap", "headword-superset"}) do
            local model = fixture():get(word)
            assert.is_nil(model.deconstructions[1].compact)
            local html = Render.render(model, Navigation.new(model):current())
            assert.is_truthy(html:find("dpd:component-sense/1/1/9004", 1, true))
            assert.is_truthy(html:find("dpd:component-sense/1/1/9006", 1, true))
        end
    end)
    it("names a compact part's senses briefly, up to eight", function()
        local senses = {}
        for _, lemma in ipairs({"vajja 1.1", "vajja 1.2", "vajjati", "kamma 1", "kamma 2", "a", "b", "c", "d"}) do
            senses[#senses + 1] = {lemma_1=lemma}
        end
        assert.equal("vajja 1.1, 1.2, vajjati, kamma 1, 2, a, b, c, …", Render.senseNames(senses))
    end)
    it("keeps a combination of entries shown in separate earlier parts", function()
        local model = fixture():get("combined")
        assert.same({true, true}, model.deconstructions[2].unique)
        assert.is_true(model.deconstructions[2].has_new)
    end)
    it("compares full entry sets rather than their sizes or two-sense previews", function()
        local lookup = fixture()
        assert.same({true, true}, lookup:get("same-size").deconstructions[1].unique)
        local model = lookup:get("preview")
        assert.equal(3, model.components.broad.total)
        assert.same({true, true}, model.deconstructions[1].unique)
        assert.equal(9001, model.components.broad.senses[3].id)
        local html = Render.render(model, Navigation.new(model):current())
        assert.is_truthy(html:find("dpd:component-sense/1/2/9001", 1, true))
    end)
    it("treats DPD's dash meanings as empty", function()
        local lookup = fixture()
        assert.equal("", lookup:get("ajjha").senses[1].meaning_combo)
        assert.equal("lit. literal", lookup:get("dashlit").senses[1].meaning_combo)
    end)
    it("omits official grammar placeholders without losing real grammatical attributes", function()
        local details = {
            -- Official mobile v0.4.20260926: akaḍḍhi, id 21.
            [21] = {grammar="aor of akaḍḍhati",neg="",verb="",trans="-",plus_case=""},
            [22] = {grammar="-",neg="neg",verb="caus",trans="intrans",plus_case="acc"},
            [23] = {grammar=" - ",neg="-",verb=" - ",trans="-",plus_case="-"},
        }
        local lookup = Lookup.new{detail=function(_, id) return details[id] end}
        assert.equal("aor of akaḍḍhati", lookup:detail(21).grammar_line)
        assert.equal("neg, caus, intrans (acc)", lookup:detail(22).grammar_line)
        assert.equal("", lookup:detail(23).grammar_line)
    end)
    it("keeps exact inflected headwords in DPD without inventing deconstructor data", function()
        local lookup, db = fixture()
        local model = lookup:get("saṃvidāvahāro")
        assert.is_true(model.found)
        assert.equal("saṃvidāvahāro", model.query)
        assert.equal("saṃvidāvahāra", model.senses[1].lemma_1)
        assert.equal(0, #model.deconstructions)
        assert.equal(0, db.fuzzy_calls)
        assert.equal("saṃvida + avahāra", lookup:detail(61939).construction)
    end)
    it("does not let a caller's changes reach the next cached lookup", function()
        local lookup = fixture()
        for _, word in ipairs({ "saṃvidāvahāro", "avaharissāmā" }) do
            -- Both the first (stored) and later (cached) results are the caller's own.
            for _ = 1, 2 do
                local first = lookup:get(word)
                first.id_query, first.original = true, "changed"
                table.remove(first.senses); table.remove(first.suggestions)
                first.senses[5], first.suggestions[5] = {}, {}
                local again = lookup:get(word)
                assert.is_nil(again.id_query); assert.equal(word, again.original)
                assert.is_nil(again.senses[5]); assert.is_nil(again.suggestions[5])
            end
            local value = lookup:get(word)
            assert.is_true(#value.senses + #value.suggestions > 0)
        end
    end)

    it("opens the single avaharissāmā candidate directly with a similar-form label", function()
        local lookup = fixture()
        local model = lookup:get("avaharissāmā")
        assert.is_true(model.found)
        assert.equal("avaharissāmā", model.query)
        assert.equal("fuzzy", model.matched_via)
        assert.equal("avaharissāma", model.suggestions[1].query)
        assert.equal(0, #model.senses)
        assert.equal("avaharati", lookup:get(model.suggestions[1].query).senses[1].lemma_1)
        local html = Render.render(model, Navigation.new(model):current())
        assert.is_true(model.single_suggestion)
        assert.is_truthy(html:find("avaharissāmā → avaharissāma · similar form",1,true))
        assert.is_truthy(html:find("takes away",1,true))
        assert.is_falsy(html:find("dpd:suggestion/1",1,true))
    end)
    it("searches other dictionaries for the single similar form it displays", function()
        local lookup = fixture()
        local searched
        lookup.dictionaries = { max_keys = 5, lookup = function(_, keys) searched = keys; return {} end }
        local result = lookup:otherDictionaries(lookup:get("avaharissāmā"))
        assert.same({ "avaharati" }, searched)
        assert.equal("avaharissāmā", result.query)
    end)
    it("passes the shown senses' plain Sanskrit equivalents to the other dictionaries", function()
        local lookup, db = fixture()
        local sanskrit
        lookup.dictionaries = { max_keys = 5, lookup = function(_, _, _, words) sanskrit = words; return {} end }
        function db:sanskrit(ids)
            assert.same({ 10432 }, ids)
            return { { id = 10432, sanskrit = "avaharati, apaharati [avahṛ]" } }
        end
        lookup:otherDictionaries(lookup:get("avaharissāmā"))
        assert.same({ "avaharati", "apaharati" }, sanskrit)
    end)
    it("retains both the headword-only and deconstructor-only fuzzy candidates", function()
        local lookup = fixture()
        local model = lookup:get("saṃmantayitvā")
        assert.equal(2, #model.suggestions)
        assert.equal(1, #model.suggestions[1].model.senses)
        assert.equal(1, #model.suggestions[2].model.deconstructions)
        assert.equal("sa + mantayitvā", lookup:get(model.suggestions[2].query).deconstructions[1].raw)
        local nav = Navigation.new(model)
        nav:push(lookup:get(model.suggestions[2].query), .3)
        assert.is_true(nav:back())
        assert.equal("saṃmantayitvā", nav:current().model.query)
        assert.equal(.3, nav:current().ratio)
    end)
    it("starts similar choices open and preserves independently toggled controls", function()
        local lookup = fixture()
        local model = lookup:get("saṃmantayitvā")
        local nav = Navigation.new(model)
        local frame = nav:current()
        assert.is_true(frame.suggestions[1].open)
        assert.is_true(frame.suggestions[2].open)
        assert.is_true(frame.suggestions[2].analyses[1])
        local html = Render.render(model, frame)
        assert.is_truthy(html:find("having consulted",1,true))
        assert.is_truthy(html:gsub("<[^>]+>", ""):find("sa + mantayitvā",1,true))
        assert.is_truthy(html:find("dpd:similar/1/sense/60749",1,true))
        assert.is_truthy(html:find("dpd:similar/2/component/1/2",1,true))
        nav:toggleSense(60749, {grammar_line="abs, of saṃmanteti"}, frame.suggestions[1])
        assert.is_nil(frame.expanded[60749])
        assert.is_true(frame.suggestions[1].expanded[60749])
        nav:toggleSuggestion(1)
        html = Render.render(model, frame)
        assert.is_falsy(html:find("having consulted",1,true))
        assert.is_truthy(html:gsub("<[^>]+>", ""):find("sa + mantayitvā",1,true))
        nav:push(model.suggestions[2].model, .5)
        assert.is_true(nav:back())
        assert.is_false(nav:current().suggestions[1].open)
        assert.is_true(nav:current().suggestions[1].expanded[60749])
        assert.is_true(nav:current().suggestions[2].open)
        assert.equal(.5,nav:current().ratio)
        nav:toggleSuggestion(1)
        assert.is_truthy(Render.render(model,frame):find("of saṃmanteti",1,true))
    end)
    it("shows headwords and deconstructors together for real exact-match controls", function()
        local lookup = fixture()
        for _, word in ipairs({"avaharissāmāti", "sammantayitvāti"}) do
            local model = lookup:get(word)
            assert.equal(1, #model.senses)
            assert.equal(1, #model.deconstructions)
            local html = Render.render(model, Navigation.new(model):current())
            assert.is_truthy(html:find("Headwords",1,true))
            assert.is_truthy(html:find("Analyses",1,true))
            -- The headword part repeats the definition above; only iti is new.
            assert.same({false, true}, model.deconstructions[1].unique)
            assert.is_true(model.deconstructions[1].has_new)
        end
        -- A part naming some of the headwords shows which one it takes.
        assert.same({true, true}, lookup:get("avaharissāmāpi").deconstructions[1].unique)
    end)
    it("intercepts suggestions and preserves normal-dictionary fallback for true misses", function()
        local lookup = fixture()
        local calls = 0
        local dictionary = {onLookupWord=function() calls=calls+1; return "normal" end}
        local hook = Direct.install(dictionary, function(word) return lookup:get(word).found end)
        assert.is_true(dictionary:onLookupWord("avaharissāmā"))
        assert.is_true(dictionary:onLookupWord("saṃmantayitvā"))
        assert.equal(0,calls)
        assert.equal("normal",dictionary:onLookupWord("dpdtestnomatch"))
        assert.equal(1,calls)
        hook:remove()
    end)
end)
