local Lookup = require("dpd/lookup")
local Normalize = require("dpd/normalize")
local Render = require("ui/dpd_render")
local Navigation = require("dpd/navigation")
local Direct = require("dpd/direct")

local function fixture()
    local db = { rows = {}, groups = {}, prefix_calls = {}, fuzzy_calls = 0 }
    function db:lookup(key) return self.rows[key] end
    function db:lookupMany(keys)
        local out = {}
        for _, key in ipairs(keys) do if self.rows[key] then out[#out+1] = self.rows[key] end end
        return out
    end
    function db:senses(ids)
        local out = {}
        for _, id in ipairs(ids) do
            out[#out+1] = { id=id, lemma_1="bhikkhu", pos="masc", meaning_1="monk" }
        end
        return out
    end
    function db:fuzzy(key)
        self.fuzzy_calls = self.fuzzy_calls + 1
        return self.groups[key] or {}
    end
    function db:fuzzyCount(key) return #(self.groups[key] or {}) end
    function db:english(keys)
        for _, key in ipairs(keys) do if self.rows[key] and self.rows[key].epd then return true end end
        return false
    end
    function db:prefix(key, limit)
        self.prefix_calls[#self.prefix_calls+1] = key
        local keys, out = {}, {}
        for word in pairs(self.rows) do
            if word:sub(1,#key) == key then keys[#keys+1] = word end
        end
        table.sort(keys)
        for i=1,math.min(limit,#keys) do out[#out+1] = self.rows[keys[i]] end
        return out
    end
    db.rows.bhikkhu = { lookup_key="bhikkhu", headwords="[1]" }
    return Lookup.new(db), db
end
local function html(value) return Render.render(value, Navigation.new(value):current()) end

describe("bounded shortened-prefix rescue", function()
    it("drops Unicode characters with NFC, case and corpus-alias normalization", function()
        assert.same({"bhikkhu","bhikkh"}, Normalize.shortenedPrefixes("“BHIKKHUX”"))
        assert.same({"dhammā","dhamm"}, Normalize.shortenedPrefixes("dham-māx"))
        assert.same({"saṃga","saṃg"}, Normalize.shortenedPrefixes("saŋgax"))
        assert.same({"dhamm","dham"}, Normalize.shortenedPrefixes("dhammā"))
        for _, word in ipairs({"dham", "dhamma 1", "√dhamma", "dha1mma", "dhamma1234", "dha1", "dhamma–x", string.rep("a",65)}) do
            assert.same({}, Normalize.shortenedPrefixes(word), word)
        end
    end)
    it("drops up to three trailing digits and keeps the bare word first", function()
        local prefixes, digits = Normalize.shortenedPrefixes("bhikkhu12")
        assert.same({"bhikkhu","bhikkh","bhikk"}, prefixes)
        assert.equal("12", digits)
        assert.same({"dham"}, Normalize.shortenedPrefixes("dham1"))
        assert.is_nil(select(2, Normalize.shortenedPrefixes("bhikkhux")))
    end)
    it("prefers the complete shortened word and labels it as approximate", function()
        local lookup, db = fixture()
        db.rows.bhikkhucompound = { lookup_key="bhikkhucompound", headwords="[2]" }
        local value = lookup:get("bhikkhux")
        assert.is_true(value.found)
        assert.equal("bhikkhux", value.query)
        assert.equal("prefix", value.matched_via)
        assert.equal("bhikkhu", value.shortened_prefix)
        assert.is_true(value.single_suggestion)
        assert.equal(1,#value.suggestions)
        assert.equal("monk", value.suggestions[1].model.senses[1].meaning_combo)
        assert.is_truthy(html(value):find("bhikkhux → bhikkhu · approximate · shortened prefix",1,true))
        assert.is_falsy(html(value):find("KOReader dictionary",1,true))
        assert.same({}, db.prefix_calls)
        assert.is_false(Lookup.directHit(value))
    end)
    it("tries one then two trailing characters, and stops before unrelated shorter prefixes", function()
        local lookup, db = fixture()
        assert.equal("bhikkhu", lookup:get("bhikkhuxy").shortened_prefix)
        assert.same({}, db.prefix_calls)
        db.prefix_calls = {}
        assert.is_false(lookup:get("bhikkhuxyz").found)
        assert.same({"bhikkhuxy","bhikkhux"}, db.prefix_calls)
        db.prefix_calls = {}
        lookup:get("xyzq")
        assert.equal(0,#db.prefix_calls)
    end)
    it("prefers a complete word at either length over continuations of a longer prefix", function()
        local lookup, db = fixture()
        db.rows.bhikkhuta = { lookup_key="bhikkhuta", headwords="[1]" }
        local value = lookup:get("bhikkhutq")
        assert.equal("bhikkhu", value.shortened_prefix)
        assert.is_true(value.single_suggestion)
        assert.equal("bhikkhu", value.suggestions[1].query)
        assert.same({}, db.prefix_calls)
    end)
    it("rescues a word followed by trailing digits and labels the removal", function()
        local lookup, db = fixture()
        local value = lookup:get("bhikkhu1")
        assert.equal("bhikkhu1", value.query)
        assert.equal("bhikkhu", value.shortened_prefix)
        assert.equal("digits", value.suggestions[1].reason)
        assert.is_truthy(html(value):find("bhikkhu1 → bhikkhu · approximate · trailing digits removed",1,true))
        assert.is_false(Lookup.directHit(value))
        assert.equal("prefix", lookup:get("bhikkhux1").suggestions[1].reason)
        assert.is_false(lookup:get("bhi1khu").found)
    end)
    it("retains exact and folded equality priority and exact-only component misses", function()
        local lookup, db = fixture()
        assert.equal("exact",lookup:get("bhikkhu").matched_via)
        db.groups.bikux = { db.rows.bhikkhu }
        assert.equal("fuzzy",lookup:get("bhikkhux").matched_via)
        assert.is_false(lookup:get("bhikkhux",{approximate=false}).found)
        assert.equal(0,#db.prefix_calls)
    end)
    it("keeps folded-only direct lookups separate from explicit DPD cache entries", function()
        local lookup, db = fixture()
        assert.is_true(lookup:get("bhikkhux").found)
        assert.is_false(lookup:get("bhikkhux",{prefix=false}).found)
        local calls = #db.prefix_calls
        assert.is_true(lookup:get("“bhikkhux”").found)
        assert.equal(calls,#db.prefix_calls)
        assert.is_false(lookup:get("bhikkhux",{approximate=false}).found)
    end)
    it("skips empty, excluded, variant-only and broken-reference neighbours", function()
        local lookup, db = fixture()
        db.rows.bhikkhu = nil
        db.rows.bhikkhua = { lookup_key="bhikkhua", epd="[1]" }
        db.rows.bhikkhub = { lookup_key="bhikkhub", variant='{"CST":{"VIN1":[["ctx","note"]]}}' }
        db.rows.bhikkhuc = { lookup_key="bhikkhuc", see='["absent"]' }
        assert.is_false(lookup:get("bhikkhux").found)
    end)
    it("offers lexical continuations from the longest useful prefix as bounded choices", function()
        local lookup, db = fixture()
        db.rows.bhikkhu = nil
        for i=1,25 do
            local key=string.format("bhikkhu%02d",i)
            db.rows[key]={lookup_key=key,headwords="[1]"}
        end
        local value=lookup:get("bhikkhux")
        assert.equal(20,#value.suggestions)
        assert.same({"bhikkhu"},db.prefix_calls)
        assert.is_true(value.prefix_limited)
        assert.is_false(value.single_suggestion)
        assert.is_truthy(html(value):find("Approximate matches for shortened prefix “bhikkhu”",1,true))
        assert.is_truthy(html(value):find("Only the first 20 lookup forms",1,true))
        assert.is_falsy(html(value):find("Show more",1,true))
        local calls=db.fuzzy_calls
        assert.equal(20,#lookup:more(value).suggestions)
        assert.equal(calls,db.fuzzy_calls)
    end)
    it("does not claim a single continuation is unique after scanning a bounded range", function()
        local lookup, db=fixture()
        db.rows.bhikkhu=nil
        db.rows.bhikkhuti={lookup_key="bhikkhuti",headwords="[1]"}
        local value=lookup:get("bhikkhux")
        assert.equal(1,#value.suggestions)
        assert.is_false(value.single_suggestion)
    end)
    it("preserves literal contextual readings while rescuing a shortened lexical form", function()
        local lookup, db=fixture()
        db.rows.bhikkhux={lookup_key="bhikkhux",variant='{"CST":{"VIN1":[["ctx","note"]]}}'}
        local value=lookup:get("bhikkhux")
        assert.is_true(value.variant_rescue)
        assert.equal(1,#value.variants)
        assert.equal("prefix",value.matched_via)
    end)
    it("restores the prefix route, expansions and scroll after Back", function()
        local lookup=fixture()
        local value=lookup:get("bhikkhux")
        local nav=Navigation.new(value)
        local frame,action=nav:resolve("dpd:similar/1/sense/1")
        assert.equal("dpd:sense/1",action)
        nav:toggleSense(1,{grammar_line="masc"},frame)
        nav:push(lookup:get("bhikkhu"),.4)
        assert.is_true(nav:back())
        assert.equal(.4,nav:current().ratio)
        assert.is_true(nav:current().suggestions[1].expanded[1])
        assert.is_truthy(Render.render(value,nav:current()):find("approximate · shortened prefix",1,true))
    end)
    it("falls through to the normal dictionary for prefix-only direct results", function()
        local lookup=fixture()
        local normal_calls=0
        local dictionary={onLookupWord=function() normal_calls=normal_calls+1;return "normal" end}
        local wrapper=Direct.install(dictionary,function(word)
            return Lookup.directHit(lookup:get(word))
        end)
        assert.equal("normal",dictionary:onLookupWord("bhikkhux"))
        assert.equal(1,normal_calls)
        wrapper:remove()
    end)
end)

describe("ti fused to the next word after a closing quote", function()
    local Popup = require("dpd/popup")
    it("checks the English index only for eligible rescue shapes", function()
        local lookup, db = fixture()
        local probes = 0
        function db:english() probes = probes + 1; return false end
        for _, word in ipairs({"dpdtestnomatch", "timing", "in", "tia", "tiā", "tilā"}) do
            lookup:get(word, Popup.selection_options)
        end
        assert.equal(0, probes)
        for _, word in ipairs({"tiettha", "NTIĀDINĀ", "saccan", "Yaṅ", "dhammañ"}) do
            lookup:get(word, Popup.selection_options)
        end
        assert.equal(5, probes)
    end)
    local function tiFixture()
        local lookup, db = fixture()
        db.rows.ettha = { lookup_key="ettha", headwords="[3]" }
        db.rows["ādinā"] = { lookup_key="ādinā", headwords="[4]" }
        db.rows.vacanato = { lookup_key="vacanato", headwords="[5]" }
        return lookup, db
    end
    it("splits ti or nti before a vowel and opens DPD on long-press", function()
        local lookup = tiFixture()
        local value = lookup:get("tiettha", Popup.selection_options)
        assert.equal("ti", value.matched_via)
        assert.is_true(value.single_suggestion)
        assert.equal("ettha", value.suggestions[1].query)
        assert.is_true(Lookup.directHit(value))
        assert.equal("dpd", Popup.route(value))
        assert.is_truthy(html(value):find("tiettha → ti + ettha · ti split from the next word",1,true))
        local nti = lookup:get("ntiādinā", Popup.selection_options)
        assert.equal("ādinā", nti.suggestions[1].query)
        assert.equal("nti", nti.suggestions[1].particle)
        -- All-caps headings split too, keeping the printed particle.
        local caps = lookup:get("TIETTHA", Popup.selection_options)
        assert.equal("ti", caps.matched_via)
        assert.equal("ettha", caps.suggestions[1].query)
        assert.equal("TI", caps.suggestions[1].particle)
        assert.equal("ādinā", lookup:get("Ntiādinā", Popup.selection_options).suggestions[1].query)
    end)
    it("leaves consonants, bare particles, hits and unknown remainders alone", function()
        local lookup, db = tiFixture()
        assert.is_false(lookup:get("tivacanato", Popup.selection_options).found)
        assert.is_false(lookup:get("tia", Popup.selection_options).found)
        assert.is_false(lookup:get("tiexyz", Popup.selection_options).found)
        db.rows.tiettha = { lookup_key="tiettha", headwords="[1]" }
        lookup.cache, lookup.order = {}, {}
        assert.equal("exact", lookup:get("tiettha").matched_via)
    end)
    it("never splits an English word from DPD's English index", function()
        local lookup, db = tiFixture()
        db.rows.ara = { lookup_key="ara", headwords="[6]" }
        db.rows.es = { lookup_key="es", roots='["√es"]' }
        assert.equal("ti", lookup:get("tiara", Popup.selection_options).matched_via)
        lookup, db = tiFixture()
        db.rows.ara = { lookup_key="ara", headwords="[6]" }
        db.rows.tiara = { lookup_key="tiara", headwords="", epd='[["sīsūpaga","nt","diadem; tiara"]]' }
        for _, word in ipairs({ "tiara", "Tiara", "TIARA" }) do
            local value = lookup:get(word, Popup.selection_options)
            assert.is_false(value.found, word)
            assert.equal("dictionary", Popup.route(value), word)
        end
    end)
    it("runs only after fuzzy matching finds nothing and before prefix rescue", function()
        local lookup, db = tiFixture()
        db.rows.tiettham = { lookup_key="tiettham", headwords="[1]" }
        db.groups[Normalize.fuzzy("tiettha")] = { db.rows.tiettham }
        assert.equal("fuzzy", lookup:get("tiettha").matched_via)
        lookup, db = tiFixture()
        db.rows.tietthaxx = { lookup_key="tietthaxx", headwords="[1]" }
        assert.equal("ti", lookup:get("tiettha").matched_via)
        assert.same({}, db.prefix_calls)
    end)
end)

describe("ṃ printed as n before ti", function()
    local Popup = require("dpd/popup")
    local function niggahitaFixture()
        local lookup, db = fixture()
        db.rows["saccaṃ"] = { lookup_key="saccaṃ", headwords="[3]" }
        return lookup, db
    end
    it("looks up ṃ for a final n and opens DPD on long-press", function()
        local lookup = niggahitaFixture()
        assert.equal("saccaṃ", lookup:get("SACCAN", Popup.selection_options).suggestions[1].query)
        local value = lookup:get("saccan", Popup.selection_options)
        assert.equal("niggahita", value.matched_via)
        assert.equal("saccaṃ", value.suggestions[1].query)
        assert.is_true(Lookup.directHit(value))
        assert.equal("dpd", Popup.route(value))
        assert.is_truthy(html(value):find("saccan → saccaṃ · ṃ printed as n before ti",1,true))
    end)
    it("runs only after a fuzzy miss and leaves short words, other endings and unknown words alone", function()
        local lookup, db = niggahitaFixture()
        assert.is_false(lookup:get("saccam", Popup.selection_options).found)
        assert.is_false(lookup:get("xyzan", Popup.selection_options).found)
        db.rows["iṃ"] = { lookup_key="iṃ", headwords="[1]" }
        assert.is_false(lookup:get("in", Popup.selection_options).found)
        assert.is_false(lookup:get("xyzañ", Popup.selection_options).found)
        db.rows.saccanx = { lookup_key="saccanx", headwords="[1]" }
        db.groups[Normalize.fuzzy("saccan")] = { db.rows.saccanx }
        assert.equal("fuzzy", lookup:get("saccan").matched_via)
    end)
    it("leaves English words such as thin to the normal dictionary", function()
        local lookup, db = niggahitaFixture()
        db.rows["thiṃ"] = { lookup_key="thiṃ", headwords="[31513]" }
        db.rows.thin = { lookup_key="thin", headwords="", epd='[["kisa","adj","thin; lean"]]' }
        local value = lookup:get("thin", Popup.selection_options)
        assert.is_false(value.found)
        assert.equal("dictionary", Popup.route(value))
    end)
end)

describe("ṃ printed as ñ or ṅ before a split consonant", function()
    local Popup = require("dpd/popup")
    it("looks up ṃ for a final ñ or ṅ at any length", function()
        local lookup, db = fixture()
        db.rows["dhammaṃ"] = { lookup_key="dhammaṃ", headwords="[3]" }
        db.rows["yaṃ"] = { lookup_key="yaṃ", headwords="[4]" }
        local value = lookup:get("dhammañ", Popup.selection_options)
        assert.equal("dhammaṃ", value.suggestions[1].query)
        assert.equal("dpd", Popup.route(value))
        assert.is_truthy(html(value):find("dhammañ → dhammaṃ · ṃ printed as ñ before a consonant",1,true))
        value = lookup:get("Yaṅ", Popup.selection_options)
        assert.equal("yaṃ", value.suggestions[1].query)
        assert.equal("dhammaṃ", lookup:get("DHAMMAÑ", Popup.selection_options).suggestions[1].query)
        assert.equal("yaṃ", lookup:get("YAṄ", Popup.selection_options).suggestions[1].query)
        assert.is_truthy(html(value):find("ṃ printed as ṅ before a consonant",1,true))
    end)
end)

describe("long Pāḷi words with no entry", function()
    local Popup = require("dpd/popup")
    local word = "kiriyākiriyatosamuṭṭhāti"
    local function partsFixture()
        local lookup, db = fixture()
        db.rows["kiriyākiriyato"] = { lookup_key="kiriyākiriyato", headwords="[6]" }
        db.rows["kiriyā"] = { lookup_key="kiriyā", headwords="[7]" }
        db.rows["samuṭṭhāti"] = { lookup_key="samuṭṭhāti", headwords="[8]" }
        db.rows["ṭhāti"] = { lookup_key="ṭhāti", headwords="[9]" }
        return lookup, db
    end
    it("opens DPD on long-press with the longest beginning and ending DPD has", function()
        local lookup = partsFixture()
        local value = lookup:get(word, Popup.selection_options)
        assert.is_false(value.found)
        assert.is_true(value.long_miss)
        assert.equal("dpd", Popup.route(value))
        assert.equal("kiriyākiriyato", value.parts.begins.form)
        assert.equal("samuṭṭhāti", value.parts.ends.form)
        local frame = Navigation.new(value):current()
        local page = Render.render(value, frame, nil, true)
        assert.is_truthy(page:find("Begins with " , 1, true))
        assert.is_truthy(page:find('dpd:part/begins', 1, true))
        assert.is_truthy(page:find('dpd:part/ends', 1, true))
        -- When parts are offered, the title bar covers editing; no footer.
        assert.is_falsy(page:find("dpd:edit-search", 1, true))
        assert.is_falsy(page:find("Note as missing", 1, true))
    end)
    it("falls back when no part has five letters and restores manual miss advice", function()
        local lookup, db = fixture()
        db.rows["kiri"] = { lookup_key="kiri", headwords="[6]" }
        local value = lookup:get(word, Popup.selection_options)
        assert.is_nil(value.long_miss)
        assert.equal("dictionary", Popup.route(value))
        assert.is_nil(value.parts.begins)
        assert.is_nil(value.parts.ends)
        assert.is_falsy(Render.render(value, Navigation.new(value):current()):find("Parts DPD has", 1, true))
        local manual = lookup:get(word, { approximate = false })
        local page = Render.render(manual, Navigation.new(manual):current(), nil, true)
        assert.is_truthy(page:find("Check the spelling, or try English mode", 1, true))
        assert.is_truthy(page:find("dpd:edit-search", 1, true))
    end)
    it("opens DPD when only a beginning or an ending is available", function()
        for _, part in ipairs({ "kiriyākiriyato", "samuṭṭhāti" }) do
            local lookup, db = fixture()
            db.rows[part] = { lookup_key=part, headwords="[6]" }
            local value = lookup:get(word, Popup.selection_options)
            assert.is_true(value.long_miss)
            assert.equal("dpd", Popup.route(value))
            assert.equal(part, (value.parts.begins or value.parts.ends).form)
            assert.is_true(not value.parts.begins or not value.parts.ends)
        end
    end)
    it("bounds the parts it looks for in very long text", function()
        local lookup, db = partsFixture()
        local many, keys, longest = db.lookupMany, 0, 0
        function db:lookupMany(list)
            keys = keys + #list
            for _, key in ipairs(list) do longest = math.max(longest, #key) end
            return many(self, list)
        end
        local value = lookup:get("kiriyākiriyato" .. string.rep("a", 4000) .. "samuṭṭhāti", Popup.selection_options)
        assert.is_true(value.long_miss)
        assert.equal("kiriyākiriyato", value.parts.begins.form)
        assert.equal("samuṭṭhāti", value.parts.ends.form)
        -- About 2 × 300 keys of at most 300 letters, not 8,000 of up to 4,000.
        assert.is_true(keys <= 600)
        assert.is_true(longest <= 300 * 3)
    end)
    it("leaves short words, English and hits to the normal routes", function()
        local lookup = partsFixture()
        assert.is_nil(lookup:get("kiriyākiriya", Popup.selection_options).long_miss)
        local english = lookup:get("internationalisation", Popup.selection_options)
        assert.is_nil(english.long_miss)
        assert.equal("dictionary", Popup.route(english))
        assert.is_nil(lookup:get("kiriyākiriyatosamuṭṭhā-ti", Popup.selection_options).long_miss)
        assert.is_false(Lookup.isLongPali("kiriyākiriya"))
        assert.is_true(Lookup.isLongPali(word))
        local capital = lookup:get("Kiriyākiriyatosamuṭṭhāti", Popup.selection_options)
        assert.equal("kiriyākiriyato", capital.parts.begins.form)
        assert.is_true(Lookup.isLongPali("KIRIYĀKIRIYATOSAMUṬṬHĀTI"))
    end)
end)

describe("rescues for a word DPD has only as a variant reading", function()
    local Popup = require("dpd/popup")
    local reading = '{"SYA":{"DNa":[["purisassa x","saṃ.sa."]]}}'
    it("leaves a long variant-only word without parts to the normal dictionary", function()
        local lookup, db = fixture()
        local word = "rattimuṭṭhānadessinā"
        db.rows[word] = { lookup_key=word, variant=reading }
        local value = lookup:get(word, Popup.selection_options)
        assert.is_nil(value.long_miss)
        assert.equal("dictionary", Popup.route(value))
        assert.equal(1, #value.variants)
        local manual = lookup:get(word, { approximate = false })
        local page = Render.render(manual, Navigation.new(manual):current(), nil, true)
        assert.is_truthy(page:find("purisassa x", 1, true))
    end)
    it("splits ti and reads a final n as ṃ, keeping the readings", function()
        local lookup, db = fixture()
        db.rows["seṭṭhaṃ"] = { lookup_key="seṭṭhaṃ", headwords="[3]" }
        db.rows["seṭṭhan"] = { lookup_key="seṭṭhan", variant=reading }
        db.rows["evamādīsu"] = { lookup_key="evamādīsu", headwords="[4]" }
        db.rows["tievamādīsu"] = { lookup_key="tievamādīsu", variant=reading }
        local value = lookup:get("seṭṭhan", Popup.selection_options)
        assert.equal("niggahita", value.matched_via)
        assert.equal("seṭṭhaṃ", value.suggestions[1].query)
        assert.equal(1, #value.variants)
        assert.equal("dpd", Popup.route(value))
        value = lookup:get("tievamādīsu", Popup.selection_options)
        assert.equal("ti", value.matched_via)
        assert.equal("evamādīsu", value.suggestions[1].query)
        assert.equal("dpd", Popup.route(value))
        -- Manual lookup takes the same rescue, not a shortened prefix.
        assert.equal("niggahita", lookup:get("seṭṭhan").matched_via)
    end)
    it("shows the parts of a long word next to its readings", function()
        local lookup, db = fixture()
        local word = "rattimuṭṭhānadessinā"
        db.rows[word] = { lookup_key=word, variant=reading }
        db.rows.ratti = { lookup_key="ratti", headwords="[5]" }
        db.rows["uṭṭhānadessinā"] = { lookup_key="uṭṭhānadessinā", headwords="[6]" }
        local value = lookup:get(word, Popup.selection_options)
        assert.is_true(value.long_miss)
        assert.equal("ratti", value.parts.begins.form)
        assert.equal("uṭṭhānadessinā", value.parts.ends.form)
        assert.equal("dpd", Popup.route(value))
        local page = Render.render(value, Navigation.new(value):current())
        assert.is_truthy(page:find("No DPD definition for", 1, true))
        assert.is_truthy(page:find("dpd:part/begins", 1, true))
        assert.is_truthy(page:find("dpd:part/ends", 1, true))
        assert.is_truthy(page:find("purisassa x", 1, true))
    end)
end)

describe("did you mean after a manual miss", function()
    it("says the suggestions failed instead of showing a plain miss", function()
        local lookup = fixture()
        lookup.suggester = { spelling = function() error("no such column: fuzzy_key", 0) end }
        local value = lookup:get("kamna", { spelling = true })
        assert.is_false(value.found)
        assert.same({ "spelling suggestions" }, value.damaged)
        assert.is_truthy(html(value):find("Some DPD details could not be read", 1, true))
        -- A cached miss isn't changed by its copies.
        assert.same({ "spelling suggestions" }, lookup:get("kamna", { spelling = true }).damaged)
    end)
end)
