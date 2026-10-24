local Navigation = require("dpd/navigation")
local Render = require("ui/dpd_render")

local function model(query, extra)
    local value = {query=query, found=true, grammar={}, senses={}, deconstructions={},
        components={}, suggestions={}, references={}, roots={}, variants={}}
    for key, field in pairs(extra or {}) do value[key] = field end
    return value
end

-- Exercise viewer actions without a device or screen. Restore module bindings
-- immediately so these stubs do not affect the other pure logic specs.
local function viewerClass()
    local names = {"ffi/blitbuffer", "ui/widget/container/centercontainer", "device",
        "ui/widget/container/framecontainer", "ui/geometry", "ui/gesturerange", "ui/widget/infomessage",
        "ui/widget/container/inputcontainer", "ui/widget/scrollhtmlwidget", "ui/widget/titlebar",
        "ui/uimanager", "ui/widget/verticalgroup", "logger", "ui/time", "ui/widget/buttontable",
            "ui/widget/horizontalgroup", "ui/widget/horizontalspan", "ui/widget/iconbutton",
            "ui/widget/linewidget", "ui/size", "ui/font", "ui/widget/textwidget"}
    local saved = {}
    for _, name in ipairs(names) do saved[name] = package.loaded[name]; package.loaded[name] = {} end
    package.loaded.device = {screen={}}
    package.loaded["ui/widget/container/inputcontainer"] = {extend=function(_, value) return value end}
    local loaded = package.loaded["ui/dpd_viewer"]
    package.loaded["ui/dpd_viewer"] = nil
    local class = require("ui/dpd_viewer")
    package.loaded["ui/dpd_viewer"] = loaded
    for _, name in ipairs(names) do package.loaded[name] = saved[name] end
    return class
end
local Viewer = viewerClass()
local function viewer(value, lookup)
    return setmetatable({navigation=Navigation.new(value), lookup=lookup or {},
        ratio=function() return .37 end, update=function(self) self.updated=true end,
        showError=function(_, err) error(err) end}, {__index=Viewer})
end

describe("complete DPD result rendering", function()
    it("decodes abbreviation fields, roots and help with safe inline markup", function()
        local value = model("loc", {abbrev={meaning="locative case", ["pāli"]="sattamī",
            example="<b>loc</b> sg", explanation="in, on"},
            abbrev_other={{source="PTS",meaning="locative",notes="a note"}},
            roots={{root="√loc",root_meaning="see",root_group="1",note="<i>note</i>"}},
            help="<b>Explanation</b>"})
        local html = Render.render(value, Navigation.new(value):current())
        assert.is_truthy(html:find("<i>Example:</i> <b>loc</b> sg",1,true))
        assert.is_truthy(html:find("<b>PTS:</b> locative",1,true))
        assert.is_truthy(html:find("√loc · see",1,true))
        assert.is_truthy(html:find("<b>Explanation</b>",1,true))
        assert.is_falsy(html:find('"meaning"',1,true))
    end)

    it("separates independent root matches from headwords but not on root-only results", function()
        local root = {root="√hu",root_meaning="offer as oblation"}
        local sense = {id=1,lemma_1="āhu",pos="perf",meaning_combo="they said"}
        local value = model("āhu", {senses={sense}, roots={root}})
        local html = Render.render(value, Navigation.new(value):current())
        local label = html:find("Other root matches",1,true)
        assert.is_truthy(label and label > html:find("they said",1,true) and label < html:find("√hu",1,true))
        value = model("āhu", {deconstructions={{parts={"āhu"},unique={true}}}, roots={root}})
        assert.is_truthy(Render.render(value, Navigation.new(value):current()):find("Other root matches",1,true))
        value = model("√hu", {roots={root}})
        assert.is_falsy(Render.render(value, Navigation.new(value):current()):find("Other root matches",1,true))
    end)

    it("opens a long miss's parts", function()
        local part = model("samuṭṭhāti", {senses={{id=8,lemma_1="samuṭṭhāti",pos="pr",meaning_combo="arises"}}})
        local value = model("kiriyākiriyatosamuṭṭhāti", {found=false, long_miss=true, parts={ends={form="samuṭṭhāti", model=part}}})
        local instance = viewer(value)
        instance:onLink("dpd:part/begins")
        assert.equal(value, instance.navigation:current().model)
        instance:onLink("dpd:part/ends")
        assert.equal(part, instance.navigation:current().model)
    end)

    it("makes every grammar alternative reachable and links exact lemmas", function()
        local value = model("buddhā", {grammar={{pos="noun",parse="nom pl",headword="buddha"},
            {pos="noun",parse="instr sg",headword="buddha"},
            {pos="pp",parse="fem nom sg",headword="buddha"}}})
        local instance = viewer(value, {headword=function(_, lemma) return model(lemma) end})
        local html = Render.render(value, instance.navigation:current())
        assert.is_truthy(html:find('dpd:grammar-toggle',1,true))
        assert.is_falsy(html:find("fem nom sg",1,true))
        instance:onLink("dpd:grammar-toggle")
        html = Render.render(value, instance.navigation:current())
        assert.is_truthy(html:find("fem nom sg",1,true))
        instance:onLink("dpd:grammar-sense/3")
        assert.equal("buddha", instance.navigation:current().model.query)
        instance.navigation:back()
        assert.is_true(instance.navigation:current().grammar_open)
        assert.equal(.37, instance.navigation:current().ratio)
    end)
    it("opens parses one line per part of speech and headword, keeping every parse", function()
        local function p(pos, parse, headword) return {pos=pos,parse=parse,headword=headword} end
        local parses={p("noun","masc dat sg","dhamma"),p("noun","masc gen sg","dhamma"),
            p("adj","masc dat sg","dhamma"),p("adj","nt dat sg","dhamma"),p("adj","masc gen sg","dhamma"),
            p("adj","nt gen sg","dhamma"),p("noun","nt dat sg","dhamma"),p("noun","nt gen sg","dhamma"),
            p("noun","fem acc sg","dhammā"),p("pron","2nd acc sg","tumha"),p("verb","present","hoti"),
            p("pron","masc acc sg","ta"),p("pron","nt nom sg","ta")}
        local merged=Render.mergeParses(parses)
        assert.same({
            {pos="noun",headword="dhamma",index=1,count=4,parse="masc, nt dat/gen sg"},
            {pos="adj",headword="dhamma",index=3,count=4,parse="masc, nt dat/gen sg"},
            {pos="noun",headword="dhammā",index=9,count=1,parse="fem acc sg"},
            {pos="pron",headword="tumha",index=10,count=1,parse="2nd acc sg"},
            {pos="verb",headword="hoti",index=11,count=1,parse="present"},
            {pos="pron",headword="ta",index=12,count=2,parse="masc acc sg; nt nom sg"}}, merged)
        -- Every original parse can be read back from its line.
        local expanded={}
        for _, line in ipairs(merged) do
            for segment in (line.parse .. "; "):gmatch("(.-); ") do
                local firsts, middles, last = segment:match("^(.-) (%S+) (%S+)$")
                if middles and middles:find("/",1,true) or (firsts and firsts:find(", ",1,true)) then
                    for first in (firsts .. ", "):gmatch("(.-), ") do
                        for middle in (middles .. "/"):gmatch("(.-)/") do
                            expanded[line.pos .. "|" .. first .. " " .. middle .. " " .. last .. "|" .. line.headword]=true
                        end
                    end
                else expanded[line.pos .. "|" .. segment .. "|" .. line.headword]=true end
            end
        end
        local count=0
        for _ in pairs(expanded) do count=count+1 end
        assert.equal(#parses,count)
        for _, parse in ipairs(parses) do
            assert.is_true(expanded[parse.pos .. "|" .. parse.parse .. "|" .. parse.headword], parse.parse)
        end
        -- Rendered open, each line links through its first parse.
        local value=model("dhammassa",{grammar=parses})
        local frame=Navigation.new(value):current()
        frame.grammar_open=true
        local html=Render.render(value, frame)
        assert.is_truthy(html:find("masc, nt dat/gen sg of ",1,true))
        assert.is_truthy(html:find('dpd:grammar-sense/3"',1,true))
        assert.is_falsy(html:find('dpd:grammar-sense/2"',1,true))
        local _, lines = html:gsub('<p class="grammar">', "")
        assert.equal(6,lines)
    end)
    it("measures bundled labels before hiding parses, preserving counts and original links", function()
        local value = model("pacchimassa", {grammar={
            {pos="adj",parse="masc dat sg",headword="pacchima"},
            {pos="adj",parse="masc gen sg",headword="pacchima"},
            {pos="noun",parse="masc dat sg",headword="pacchima"},
            {pos="noun",parse="masc gen sg",headword="pacchima"},
            {pos="adj",parse="nt dat sg",headword="pacchima"},
            {pos="noun",parse="nt dat sg",headword="pacchima"},
            {pos="adj",parse="nt gen sg",headword="pacchima"},
            {pos="noun",parse="nt gen sg",headword="pacchima"}}})
        local frame, measured = Navigation.new(value):current(), {}
        local layout = {content_em=30*.85, measure_text=function(text, factor)
            if text:find(" of ",1,true) then
                measured[#measured+1] = text
                return 12 * factor
            end
            return 3 * factor
        end}
        local html = Render.render(value, frame, nil, nil, layout)
        assert.same({"adj · masc, nt dat/gen sg of pacchima", "noun · masc, nt dat/gen sg of pacchima"}, measured)
        assert.is_falsy(html:find("dpd:grammar-toggle",1,true))
        assert.is_truthy(html:find('dpd:grammar-sense/3"',1,true))
        assert.is_falsy(html:find('dpd:grammar-sense/2"',1,true))
        layout.content_em = 20 * .85
        html = Render.render(value, frame, nil, nil, layout)
        assert.is_truthy(html:find("masc, nt dat/gen sg of ",1,true))
        assert.is_truthy(html:find("+4 parses",1,true))
        assert.is_falsy(html:find('dpd:grammar-sense/3"',1,true))
        local measurements = #measured
        frame.grammar_open = true
        html = Render.render(value, frame, nil, nil, layout)
        assert.equal(measurements, #measured)
        assert.is_truthy(html:find('dpd:grammar-sense/3"',1,true))
        assert.is_truthy(html:find("Show fewer parses",1,true))
        assert.equal(8, #value.grammar)
        assert.equal("masc dat sg", value.grammar[1].parse)
        -- A single bundle can wrap, but none of its original parses are hidden.
        value.grammar = {value.grammar[1], value.grammar[2]}
        frame = Navigation.new(value):current()
        layout.content_em = 10 * .85
        html = Render.render(value, frame, nil, nil, layout)
        assert.is_truthy(html:find("masc dat/gen sg of ",1,true))
        assert.is_falsy(html:find("dpd:grammar-toggle",1,true))
    end)
    it("fits complete parses and reserves space for the overflow control", function()
        local value = model("form", {grammar={
            {pos="noun",parse="first",headword="lemma"},
            {pos="adj",parse="second",headword="lemma"},
            {pos="pron",parse="third",headword="lemma"},
            {pos="verb",parse="fourth",headword="lemma"}}})
        local frame = Navigation.new(value):current()
        local layout = {content_em=60, measure_text=function(text, factor)
            return (text:find(" of ",1,true) and 12 or 3) * factor
        end}
        local html = Render.render(value, frame, nil, nil, layout)
        assert.is_truthy(html:find("fourth",1,true))
        assert.is_falsy(html:find("dpd:grammar-toggle",1,true))
        layout.content_em = 36 * .85
        html = Render.render(value, frame, nil, nil, layout)
        assert.is_truthy(html:find("second",1,true))
        assert.is_falsy(html:find("third",1,true))
        assert.is_truthy(html:find("+2 parses",1,true))
        assert.is_truthy(html:find('grammar-sense/2',1,true))
        -- Nested cards must use the space left after their indentation.
        html = Render.render(value, frame, "similar/1", nil, layout, 12 * .85)
        assert.is_falsy(html:find("second",1,true))
        assert.is_truthy(html:find("+3 parses",1,true))
        assert.is_truthy(html:find('dpd:similar/1/grammar-toggle',1,true))
        layout.content_em = 10 * .85
        html = Render.render(value, frame, nil, nil, layout)
        assert.is_truthy(html:find('<p class="grammar"><i>noun',1,true))
        assert.is_truthy(html:find('</p>\n<p class="grammar grammar-more">',1,true))
        assert.is_falsy(html:find('grammar-parse',1,true))
        frame.grammar_open = true
        html = Render.render(value, frame, nil, nil, layout)
        assert.is_truthy(html:find("fourth",1,true))
        assert.is_truthy(html:find("Show fewer parses",1,true))
        assert.is_falsy(html:find('grammar-parse',1,true))
        frame.grammar_open, layout.content_em = false, 60
        html = Render.render(value, frame, nil, nil, layout)
        assert.is_falsy(html:find("dpd:grammar-toggle",1,true))
        -- One left over is singular.
        value = model("form", {grammar={{pos="noun",parse="first",headword="lemma"},
            {pos="adj",parse="second",headword="lemma"}}})
        layout.content_em = 10 * .85
        html = Render.render(value, Navigation.new(value):current(), nil, nil, layout)
        assert.is_truthy(html:find("+1 parse<",1,true))
    end)
    it("passes the displayed model to grammar navigation, including nested candidate controls", function()
        local leaf = model("inflected", {senses={{id=1,lemma_1="lemma",pos="noun",meaning_combo="meaning"}},
            grammar={{headword="lemma",pos="noun",parse="nom sg",id=1}}})
        local value = model("selected", {single_suggestion=true,
            suggestions={{query="inflected",model=leaf,
                attestations={{source="CST",book="VIN1",note="selected (ka.)"}}}}})
        local passed
        local instance=viewer(value,{headword=function(_,lemma,existing)
            assert.equal("lemma",lemma);passed=existing;return model(lemma,{senses=existing.senses})
        end})
        instance:onLink("dpd:similar/1/attestations-toggle")
        assert.is_true(instance.navigation:current().suggestions[1].attestations_open)
        assert.is_truthy(Render.render(value,instance.navigation:current()):find("selected (ka.)",1,true))
        instance:onLink("dpd:similar/1/grammar-sense/1")
        assert.equal(leaf,passed)
        assert.equal(1,instance.navigation:current().model.senses[1].id)
        instance.navigation:back()
        assert.equal(.37,instance.navigation:current().ratio)
        assert.is_true(instance.navigation:current().suggestions[1].attestations_open)
        instance:onLink("dpd:similar/1/attestations-toggle")
        assert.is_falsy(Render.render(value,instance.navigation:current()):find("selected (ka.)",1,true))
    end)
    it("keeps source notes tappable on collapsed candidates without enabling hidden sense controls", function()
        local value=model("selected",{suggestions={
            {query="first",model=model("first"),
                attestations={{source="CST",book="VIN1",note="selected (ka.)"}}},
            {query="second",model=model("second")}}})
        local instance=viewer(value)
        instance:onLink("dpd:similar/1")
        assert.is_false(instance.navigation:current().suggestions[1].open)
        instance:onLink("dpd:similar/1/attestations-toggle")
        assert.is_true(instance.navigation:current().suggestions[1].attestations_open)
        assert.is_truthy(Render.render(value,instance.navigation:current()):find("selected (ka.)",1,true))
        assert.is_nil(instance.navigation:resolve("dpd:similar/1/sense/1"))
        instance:onLink("dpd:similar/1/attestations-toggle")
        assert.is_falsy(Render.render(value,instance.navigation:current()):find("selected (ka.)",1,true))
    end)

    it("keeps contextual variants collapsed and preserves their provenance", function()
        local value = model("kā", {grammar={{headword="ka",pos="pron",parse="fem nom sg"}},
            variants={{source="CST",book="PV",context="tattha kā",note="kā tattha (sī.)"}}})
        local instance = viewer(value)
        local html = Render.render(value, instance.navigation:current())
        assert.is_falsy(html:find("tattha kā",1,true))
        instance:onLink("dpd:variants-toggle")
        html = Render.render(value, instance.navigation:current())
        assert.is_truthy(html:find("CST · PV",1,true))
        assert.is_truthy(html:find("kā tattha (sī.)",1,true))
        assert.is_falsy(html:find("spelling correction",1,true))
    end)

    it("shows original selection and lexical details without allowing source controls", function()
        local value = model("buddha", {original="BUDDHA",senses={{id=1,lemma_1="buddha",pos="noun",meaning_combo="Buddha"}}})
        local frame = Navigation.new(value):current()
        frame.expanded[1] = true
        frame.details[1] = {phonetic="dht > ddh",commentary="<b>buddhassa</b>",root_base="budh",
            synonym='<a href="dpd:normal">sambuddha</a>'}
        local html = Render.render(value, frame)
        assert.is_falsy(html:find("Selected:",1,true))
        assert.is_truthy(html:find("<i>Commentary:</i> <b>buddhassa</b>",1,true))
        assert.is_truthy(html:find('<td class="label">Root base</td><td>budh',1,true))
        assert.is_falsy(html:find('<a href="dpd:normal">sambuddha',1,true))
    end)

    it("pages long variant-reading lists and omits empty reading notes", function()
        local variants = {}
        for i = 1, 120 do variants[i] = {source="CST", book="B" .. i, context="ctx" .. i, note=i == 1 and "" or "n" .. i} end
        local value = model("ca", {variants=variants})
        local frame = Navigation.new(value):current()
        frame.variants_open = true
        local html = Render.render(value, frame)
        assert.is_truthy(html:find("ctx1</p>",1,true))
        assert.is_falsy(html:find("<br></p>",1,true))
        assert.is_truthy(html:find("ctx50<br>",1,true))
        assert.is_falsy(html:find("ctx51<br>",1,true))
        assert.is_truthy(html:find("Readings 1–50&nbsp;of&nbsp;120",1,true))
        assert.is_truthy(html:find("dpd:variants-next",1,true))
        assert.is_falsy(html:find("dpd:variants-prev",1,true))
        local instance = viewer(value)
        frame = instance.navigation:current()
        frame.variants_open = true
        instance:onLink("dpd:variants-next")
        html = Render.render(value, frame)
        assert.is_truthy(html:find("Readings 51–100&nbsp;of&nbsp;120",1,true))
        assert.is_falsy(html:find("ctx50<br>",1,true))
        assert.is_falsy(html:find("ctx101<br>",1,true))
        instance:onLink("dpd:variants-next")
        instance:onLink("dpd:variants-next") -- the last window is bounded
        assert.equal(3, frame.variants_page)
        html = Render.render(value, frame)
        assert.is_truthy(html:find("ctx120<br>",1,true))
        assert.is_falsy(html:find("ctx100<br>",1,true))
        assert.is_falsy(html:find("dpd:variants-next",1,true))
        instance.navigation:push(model("another"), .37)
        instance.navigation:back()
        assert.equal(frame, instance.navigation:current())
        assert.equal(3, frame.variants_page)
        assert.equal(.37, frame.ratio)
        instance:onLink("dpd:variants-prev")
        assert.equal(2, frame.variants_page)
        instance:onLink("dpd:variants-prev")
        instance:onLink("dpd:variants-prev") -- the first window is bounded
        assert.equal(1, frame.variants_page)
    end)

    it("pages nested readings against their own frame", function()
        local variants = {}
        for i = 1, 51 do variants[i] = {source="CST",book="B",context="nested" .. i} end
        local child = model("ca", {variants=variants})
        local value = model("parent", {single_suggestion=true,suggestions={{query="ca",model=child}}})
        local instance = viewer(value)
        local root, frame = instance.navigation:current(), instance.navigation:current().suggestions[1]
        frame.variants_open = true
        instance:onLink("dpd:similar/1/variants-next")
        assert.equal(2, frame.variants_page)
        assert.equal(1, root.variants_page)
        local html = Render.render(value, root)
        assert.truthy(html:find("Readings 51–51&nbsp;of&nbsp;51",1,true))
        assert.truthy(html:find("dpd:similar/1/variants-prev",1,true))
        assert.is_falsy(html:find("nested50</p>",1,true))
        instance:onLink("dpd:similar/1/variants-prev")
        assert.equal(1, frame.variants_page)
    end)

    it("shows no meaning for DPD's dash placeholder meanings", function()
        local value = model("ajjha", {senses={{id=1254,lemma_1="ajjha",pos="prefix",meaning_combo=""}}})
        local html = Render.render(value, Navigation.new(value):current())
        assert.is_truthy(html:find("<b>ajjha</b> · <i>prefix</i></a>",1,true))
    end)

    it("omits DPD's lone dash placeholders from sense details", function()
        local value = model("pacchima", {senses={{id=1,lemma_1="pacchima 2",pos="adj",meaning_combo="west"}}})
        local frame = Navigation.new(value):current()
        frame.expanded[1] = true
        frame.details[1] = {commentary="-",source_1=" - ",suffix="ima",notes="a - b"}
        local html = Render.render(value, frame)
        assert.is_falsy(html:find("Commentary:",1,true))
        assert.is_falsy(html:find("Source:",1,true))
        assert.is_truthy(html:find('<td class="label">Suffix</td><td>ima',1,true))
        assert.is_truthy(html:find("<i>Notes:</i> a - b",1,true))
    end)

    it("drops the heading rule only when the heading opens the view", function()
        local analyses = {{raw="a + b",parts={"a","b"},unique={true,true},has_new=true, starts_open=true}}
        local compound = model("ab", {deconstructions=analyses})
        local html = Render.render(compound, Navigation.new(compound):current())
        assert.is_truthy(html:find('^<h3 class="lead">1 possible split <span class="quiet">· not yet checked by DPD</span>'))
        local mixed = model("ab", {deconstructions=analyses,
            senses={{id=1,lemma_1="ab",pos="adj",meaning_combo="x"}}})
        html = Render.render(mixed, Navigation.new(mixed):current())
        assert.is_truthy(html:find('^<h3 class="lead">Headwords'))
        assert.is_truthy(html:find("<h3>1 possible split",1,true))
    end)

    it("leaves out view headings that only repeat the title", function()
        local state = {analyses={}}
        local paradigm = Render.render({query="sabba 1", found=true, paradigm={lemma="sabba 1", kind="Declension",
            pattern="a pron", sections={}}}, state)
        assert.is_falsy(paradigm:find("<h3",1,true))
        assert.is_truthy(paradigm:find("^<p class=\"header\">Declension"))
        local details = Render.render({query="√gam", found=true, root_details={root="√gam", rows={}}}, state)
        assert.is_falsy(details:find("<h3",1,true))
        local matrix = Render.render({query="√gam", found=true, root_matrix={root="√gam", total=640, groups={}}}, state)
        assert.is_truthy(matrix:find('^<p class="header">640&nbsp;words</p>'))
        local row = Render.render({query="√gam", found=true, matrix_row={root="√gam", group="verbs", label="pr", items={{lemma="x"}}}}, state)
        assert.is_truthy(row:find('^<h3 class="lead">verbs · <b>pr</b> · 1</h3>'))
        -- A heading naming something else stays.
        details = Render.render({query="gacchati", found=true, root_details={root="√gam", rows={}}}, state)
        assert.is_truthy(details:find('<h3 class="lead">√gam</h3>',1,true))
        local english = Render.render({query="good", found=true, english={query="good", total=38, items={}}}, state)
        assert.is_truthy(english:find('^<p class="header">English → Pāḷi · 38&nbsp;entries</p>'))
        -- A miss says so once.
        local miss = Render.render(model("zz", {found=false, english={query="zz", total=0, items={}}}), state)
        assert.is_falsy(miss:find("English · ",1,true))
        assert.is_falsy(miss:find("English → Pāḷi ·",1,true))
    end)

    it("does not present a family view's title as a selected form", function()
        local family = Render.render({query="dhamma", found=true, original="Idioms: dhamma", family={title="Idioms: dhamma",
            items={{lemma="diṭṭhe dhamme", pos="idiom", meaning="in this life", available=true}}, total=1}},
            {analyses={}})
        assert.is_falsy(family:find("Selected:",1,true))
        -- The whole row opens the member; only the word is underlined.
        assert.is_truthy(family:find('class="plain"><u><b>diṭṭhe dhamme</b></u> · <i>idiom</i>',1,true))
        local result = Render.render(model("dhamma", {original="dhammo"}), Navigation.new(model("dhamma")):current())
        assert.is_truthy(result:find("Selected:",1,true))
    end)

    it("keeps component sense fields aligned and the first card free of a rule", function()
        assert.is_truthy(Render.css:find(".component .detail p { margin-left: 0; }",1,true))
        local value = model("hotī", {references={{kind="spelling", target="hotīti"}}})
        local html = Render.render(value, Navigation.new(value):current())
        assert.is_truthy(html:find('^<div class="similar first">'))
    end)

    it("reads a component sense's detail only from a visible control", function()
        local reads = 0
        local value = model("ab", {deconstructions={{parts={"a","b"}, unique={true,false}, has_new=true, starts_open=true}},
            components={a={senses={{id=7},{id=8},{id=9}}, total=3}, b={senses={{id=7}}, total=1}}})
        local instance = viewer(value, {detail=function(_, id) reads = reads + 1; return {id=id} end})
        -- A third sense, an unknown one, a repeated component and a missing analysis.
        for _, uri in ipairs({"dpd:component-sense/1/1/9", "dpd:component-sense/1/1/99",
            "dpd:component-sense/1/2/7", "dpd:component-sense/2/1/7"}) do
            instance:onLink(uri)
        end
        local frame = instance.navigation:current()
        frame.analyses[1] = false
        instance:onLink("dpd:component-sense/1/1/7")
        assert.equal(0, reads)
        assert.is_nil(instance.updated)
        frame.analyses[1] = true
        instance:onLink("dpd:component-sense/1/1/7")
        assert.equal(1, reads)
        assert.same({id=7}, instance.navigation:componentDetail(1, 1, 7))
    end)
end)

describe("resolved references and pagination", function()
    it("opens exact reference content and scopes nested controls through references and similar forms", function()
        local leaf = model("hotīti", {grammar={{pos="verb",parse="present",headword="hoti"},
            {pos="pp",parse="another",headword="hoti"},{pos="ind",parse="third",headword="hoti"}}})
        local middle = model("hotī", {references={{kind="spelling",target="hotīti",model=leaf}}})
        local value = model("approximate", {suggestions={{query="hotī",model=middle}}})
        local instance = viewer(value)
        assert.is_true(instance.navigation:current().suggestions[1].open)
        local html = Render.render(value, instance.navigation:current())
        assert.is_truthy(html:find("Incorrect spelling of",1,true))
        assert.is_truthy(html:find("dpd:similar/1/reference/1/grammar-toggle",1,true))
        instance:onLink("dpd:similar/1/reference/1/grammar-toggle")
        assert.is_true(instance.navigation:current().suggestions[1].references[1].grammar_open)
        instance:onLink("dpd:similar/1/reference/1")
        assert.equal(leaf, instance.navigation:current().model)
        instance.navigation:back()
        instance:onLink("dpd:similar/1/reference-toggle/1")
        assert.is_nil(instance.navigation:resolve("dpd:similar/1/reference/1/grammar-toggle"))
        assert.equal(middle, instance.navigation:current().suggestions[1].model)
    end)

    it("renders unavailable references without creating navigation or recursive lookups", function()
        local value = model("mixed", {references={{kind="see",target="missing",status="missing"},
            {kind="see",target="cycle",status="cycle"}}})
        local instance = viewer(value)
        local html = Render.render(value, instance.navigation:current())
        assert.is_truthy(html:find("See missing",1,true))
        assert.is_falsy(html:find("Referenced DPD entry is unavailable",1,true))
        assert.is_truthy(html:find("Circular DPD reference",1,true))
        instance:onLink("dpd:reference/1")
        assert.equal(1, #instance.navigation.stack)
    end)

    it("preserves source corrections and referrals before a single similar form", function()
        local value = model("jālante", {single_suggestion=true,
            references={{kind="spelling",target="jālente",status="missing"},
                {kind="see",target="some headword",status="missing"}},
            suggestions={{query="jalante",model=model("jalante")}}})
        local html = Render.render(value, Navigation.new(value):current())
        local correction = html:find("Incorrect spelling of jālente",1,true)
        assert.is_truthy(correction and correction < html:find("similar form",1,true))
        assert.is_truthy(html:find("See some headword",1,true))
        assert.is_falsy(html:find("unavailable",1,true))
    end)

    it("preserves previous child state and scroll when loading more similar forms", function()
        local first = model("first")
        local value = model("approximate", {suggestion_total=2,suggestions={{query="first",model=first}}})
        local next_value = model("approximate", {suggestion_total=2,suggestions={value.suggestions[1],
            {query="second",model=model("second")}}})
        local instance = viewer(value, {more=function(_, old) assert.equal(value,old); return next_value end})
        local frame = instance.navigation:current()
        frame.suggestions[1].open = false
        frame.suggestions[1].expanded[42] = true
        assert.is_truthy(Render.render(value,frame):find("Show more",1,true))
        instance:onLink("dpd:more")
        assert.equal(next_value, frame.model)
        assert.is_false(frame.suggestions[1].open)
        assert.is_true(frame.suggestions[1].expanded[42])
        -- A newly loaded form within the first two starts open like the rest.
        assert.is_true(frame.suggestions[2].open)
        assert.equal(.37, frame.ratio)
        assert.is_falsy(Render.render(next_value,frame):find("Show more",1,true))
    end)

    it("opens compound components with approximate matching disabled and displays correction provenance", function()
        local value = model("compound", {deconstructions={{parts={"hotī"},unique={true},has_new=true, starts_open=true}},
            components={hotī={senses={{pos="verb",meaning_combo="is"}},total=1,
                reference_targets={{kind="spelling",target="hotīti"}}}}})
        local seen
        local instance = viewer(value, {get=function(_,word,options) seen={word,options}; return model(word) end})
        local html = Render.render(value,instance.navigation:current())
        assert.is_truthy(html:find("Incorrect spelling of hotīti",1,true))
        instance:onLink("dpd:component/1/1")
        assert.same({"hotī",{approximate=false}},seen)
    end)
end)

describe("manual miss and imported table presentation", function()
    it("names a missing headword ID instead of a word miss", function()
        local html = Render.render(model("999999999", {found=false, id_query=true}), {}, nil, true)
        assert.is_truthy(html:find("No DPD headword with ID 999999999.", 1, true))
        assert.is_truthy(html:find("Check the number", 1, true))
        assert.is_falsy(html:find("No DPD entry", 1, true))
        html = Render.render(model("dhammax", {found=false}), {}, nil, true)
        assert.is_truthy(html:find("No DPD entry for “dhammax”", 1, true))
    end)

    it("caps imported table text at large popup fonts only", function()
        assert.equal(Render.css, Render.cssFor(16))
        assert.equal(Render.css, Render.cssFor(Render.table_font_max))
        assert.is_truthy(Render.cssFor(26):find(".article table { font-size: 0.846em; }", 1, true))
        assert.is_truthy(Render.cssFor(32):find(".article table { font-size: 0.688em; }", 1, true))
    end)
end)
