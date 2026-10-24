local Json = require("json")
local Inflection = require("dpd/inflection")
local Navigation = require("dpd/navigation")
local Render = require("ui/dpd_render")

-- Templates copied from the official DPD mobile database (abridged rows).
local templates = {
    ["a masc"] = {like="dhamma", rows={
        {{""},{"masc sg"},{""},{"masc pl"},{""}},
        {{"nom"},{"o"},{"masc nom sg"},{"ā","āse"},{"masc nom pl"}},
        {{"dat"},{"assa","āya"},{"masc dat sg"},{"ānaṃ"},{"masc dat pl"}},
        {{"gen"},{"assa"},{"masc gen sg"},{"āna","ānaṃ"},{"masc gen pl"}},
        {{"in comps"},{"a"},{"in comps"},{""},{""}}}},
    ["a pron"] = {like="sabba", rows={
        {{""},{"masc sg"},{""},{"masc pl"},{""},{"fem sg"},{""},{"fem pl"},{""},{"neut sg"},{""},{"neut pl"},{""}},
        {{"nom"},{"o"},{"masc nom sg"},{"e"},{"masc nom pl"},{"ā"},{"fem nom sg"},{"ā","āyo"},{"fem nom pl"},
            {"aṃ"},{"nt nom sg"},{"āni","e"},{"nt nom pl"}},
        {{"in comps"},{"a"},{"in comps"},{""},{""},{""},{""},{""},{""},{""},{""},{""},{""}}}},
    ["ati pr"] = {like="bhavati", rows={
        {{""},{"sg"},{""},{"pl"},{""},{"reflexive sg"},{""},{"reflexive pl"},{""}},
        {{"pr 3rd"},{"ati"},{"pr 3rd sg"},{"anti"},{"pr 3rd pl"},{"ate"},{"reflx pr 3rd sg"},{"ante","are"},{"reflx pr 3rd pl"}},
        {{"opt 3rd"},{"e","eyya"},{"opt 3rd sg"},{"eyyuṃ"},{"opt 3rd pl"},{"etha"},{"reflx opt 3rd sg"},{"eraṃ"},{"reflx opt 3rd pl"}}}},
    ["hoti pr"] = {like="hoti", rows={
        {{""},{"sg"},{""},{"pl"},{""}},
        {{"pr 3rd"},{"hoti"},{"pr 3rd sg"},{"honti"},{"pr 3rd pl"}}}},
    ["karoti pr"] = {like="irreg", rows={
        {{""},{"sg"},{""},{"pl"},{""}},
        {{"pr 3rd"},{"karoti"},{"pr 3rd sg"},{"karonti"},{"pr 3rd pl"}}}},
    ["a3 adj"] = {like="x", rows={
        {{""},{"masc sg"},{""},{"fem sg"},{""},{"neut sg"},{""}},
        {{"nom"},{"o"},{"masc nom sg"},{"ā"},{"fem nom sg"},{"aṃ"},{"nt nom sg"}}}},
}

local function fixture()
    local db = {queries=0}
    function db:query(sql, params)
        self.queries = self.queries + 1
        assert(sql:find("FROM inflection_templates WHERE pattern = ?", 1, true))
        local template = templates[params[1]]
        if self.raw and self.raw[params[1]] then return {{like="", data=self.raw[params[1]]}} end
        return template and {{like=template.like, data=Json.encode(template.rows)}} or {}
    end
    return Inflection.new(db), db
end

local function forms(section, label, column)
    for _, row in ipairs(section.rows) do
        if row.label == label then
            local out = {}
            for _, form in ipairs(row.cells[column].forms) do out[#out+1] = form.text end
            return out
        end
    end
end

describe("DPD declension and conjugation tables", function()
    it("builds a noun paradigm, highlighting every cell with the selected form", function()
        local inflection = fixture()
        local result = inflection:paradigm({stem="dhamm", pattern="a masc"}, "dhamma 1.01", "dhammassa")
        assert.equal("Declension", result.kind)
        assert.equal("dhamma", result.like)
        assert.equal(1, #result.sections)
        local section = result.sections[1]
        assert.is_nil(section.title)
        assert.same({"masc sg","masc pl"}, section.columns)
        assert.same({"dhammā","dhammāse"}, forms(section, "nom", 2))
        assert.same({"dhammassa","dhammāya"}, forms(section, "dat", 1))
        assert.equal(2, result.selected_count)
        assert.equal("dhammassa", result.selected)
        -- Repeated forms share one lookup index.
        local dat, gen = section.rows[2].cells[1].forms[1], section.rows[3].cells[1].forms[1]
        assert.equal(dat.index, gen.index)
        assert.equal("dhammassa", result.forms[dat.index])
        assert.same({"dhamma"}, forms(section, "in comps", 1))
        assert.same({}, forms(section, "in comps", 2))
    end)

    it("splits wide grids by gender and drops rows without forms in a section", function()
        local result = fixture():paradigm({stem="sabb", pattern="a pron"}, "sabba 1", "sabbe")
        assert.equal(3, #result.sections)
        assert.same({"Masculine","Feminine","Neuter"},
            {result.sections[1].title, result.sections[2].title, result.sections[3].title})
        assert.same({"sg","pl"}, result.sections[2].columns)
        assert.equal(2, #result.sections[1].rows)
        assert.equal(1, #result.sections[2].rows, "in comps has no feminine forms")
        assert.same({"sabbāni","sabbe"}, forms(result.sections[3], "nom", 2))
        assert.equal(2, result.selected_count)
    end)

    it("splits conjugations into active and reflexive voices", function()
        local result = fixture():paradigm({stem="gacch", pattern="ati pr"}, "gacchati 1", "gacche")
        assert.equal("Conjugation", result.kind)
        assert.same({"Active","Reflexive"}, {result.sections[1].title, result.sections[2].title})
        assert.same({"gacche","gaccheyya"}, forms(result.sections[1], "opt 3rd", 1))
        assert.same({"gacchante","gacchare"}, forms(result.sections[2], "pr 3rd", 2))
        assert.equal(1, result.selected_count)
    end)

    it("keeps single-column groups together with their full labels", function()
        local result = fixture():paradigm({stem="x", pattern="a3 adj"}, "x", nil)
        assert.equal(1, #result.sections)
        assert.same({"masc sg","fem sg","neut sg"}, result.sections[1].columns)
        assert.is_nil(result.selected)
    end)

    it("removes irregular and inflected-headword stem markers", function()
        local inflection = fixture()
        local irregular = inflection:paradigm({stem="*", pattern="hoti pr"}, "hoti 1", "honti")
        assert.same({"hoti","honti"}, irregular.forms)
        assert.equal(1, irregular.selected_count)
        local both = inflection:paradigm({stem="!*", pattern="hoti pr"}, "hoti 2", nil)
        assert.same({"hoti","honti"}, both.forms)
        local inflected = inflection:paradigm({stem="!dhamm", pattern="a masc"}, "dhammassa 1", "dhammassa")
        assert.equal("dhammo", inflected.forms[1])
        assert.equal(2, inflected.selected_count)
    end)

    it("offers no table for indeclinables and explains missing or damaged templates", function()
        assert.is_false(Inflection.available({stem="-", pattern=""}))
        assert.is_false(Inflection.available({stem="ca", pattern=""}))
        assert.is_false(Inflection.available({}))
        assert.is_true(Inflection.available({stem="dhamm", pattern="a masc"}))
        local inflection = fixture()
        assert.is_truthy(inflection:paradigm({stem="-", pattern=""}, "ca", "ca").error)
        local missing = inflection:paradigm({stem="x", pattern="nonexistent"}, "x", nil)
        assert.is_truthy(missing.error:find("nonexistent", 1, true))
        local damaged = fixture()
        damaged.db.raw = {["a masc"]='[[[""],["sg"],[""]],[["nom"],["o"]]]'}
        assert.is_truthy(damaged:paradigm({stem="x", pattern="a masc"}, "x", nil).error:find("fresh DPD", 1, true))
        for _, raw in ipairs({'{broken', '[]', '[[[""],[1],[""]],[["nom"],["o"],["g"]]]', string.rep(" ", 65537)}) do
            local fresh = fixture()
            fresh.db.raw = {["a masc"]=raw}
            assert.is_truthy(fresh:paradigm({stem="x", pattern="a masc"}, "x", nil).error)
        end
    end)

    it("names conjugations from the pattern's part of speech", function()
        assert.equal("Conjugation", Inflection.kind("ati pr"))
        assert.equal("Conjugation", Inflection.kind("aor irreg"))
        assert.equal("Conjugation", Inflection.kind("imperf"))
        assert.equal("Declension", Inflection.kind("a masc"))
        assert.equal("Declension", Inflection.kind("ant prp"))
        assert.equal("Declension", Inflection.kind(nil))
    end)

    it("reads each template once and bounds the decoded cache", function()
        local inflection, db = fixture()
        inflection:paradigm({stem="dhamm", pattern="a masc"}, "dhamma", nil)
        inflection:paradigm({stem="buddh", pattern="a masc"}, "buddha", nil)
        assert.equal(1, db.queries)
        for i = 1, 10 do inflection:paradigm({stem="x", pattern="p" .. i}, "x", nil) end
        local retained = 0
        for _ in pairs(inflection.templates) do retained = retained + 1 end
        assert.equal(8, retained)
    end)
end)

describe("DPD paradigm rendering", function()
    local function value(extra)
        local result = {query="sabba 1", found=true, grammar={}, senses={}, deconstructions={},
            components={}, suggestions={}, references={}, roots={}, variants={}}
        for key, field in pairs(extra or {}) do result[key] = field end
        return result
    end

    it("says irregular instead of naming DPD's irreg model word", function()
        local paradigm = fixture():paradigm({stem="*", pattern="karoti pr"}, "karoti 1", "karoti")
        local html = Render.render(value({query="karoti 1", paradigm=paradigm}), {paradigm_columns=1})
        assert.is_truthy(html:find("pattern <i>karoti pr</i> · irregular</p>", 1, true))
        assert.is_falsy(html:find("like irreg", 1, true))
    end)

    it("links each form, marks the selection and states that occurrence is not shown", function()
        local paradigm = fixture():paradigm({stem="sabb", pattern="a pron"}, "sabba 1", "sabbe")
        local html = Render.render(value({paradigm=paradigm}), {paradigm_columns=1})
        assert.is_truthy(html:find("Declension · pattern <i>a pron</i>", 1, true))
        assert.is_falsy(html:find("like sabba", 1, true), "the model word is the entry itself")
        assert.is_truthy(html:find('<p class="section">Masculine</p>', 1, true))
        assert.is_truthy(html:find('<p class="section">Neuter</p>', 1, true))
        local index
        for i, form in ipairs(paradigm.forms) do if form == "sabbe" then index = i end end
        assert.is_truthy(html:find('href="dpd:paradigm-form/' .. index .. '"><span class="selected">▸ sabbe</span>', 1, true))
        assert.is_truthy(html:find("This database does not show which individual forms occur in the texts.", 1, true))
        local _, tables = html:gsub("<table", "")
        assert.equal(3, tables)
    end)

    it("lets only a form wider than its column break, and never inside its ending", function()
        local long = string.rep("abhivādana", 8)
        local paradigm = {lemma="x", kind="Declension", pattern="a nt", sections={{columns={"sg"},
            rows={{label="nom", cells={{forms={{text=long .. "aṃ", ending="aṃ", index=1},
                {text="xaṃ", ending="aṃ", index=2}}}}}}}}}
        local html = Render.render(value({paradigm=paradigm}), {paradigm_columns=1, content_em=30})
        local zwsp = "\226\128\139"
        assert.is_truthy(html:find(">a" .. zwsp .. "b" .. zwsp .. "h" .. zwsp .. "i" .. zwsp .. "v" .. zwsp .. "ā", 1, true))
        assert.is_truthy(html:find("a" .. zwsp .. "aṃ</a>", 1, true))
        assert.is_truthy(html:find('href="dpd:paradigm-form/2">xaṃ</a>', 1, true))
    end)

    it("wraps a whole-word irregular form wider than its column", function()
        local paradigm = {lemma="catu", kind="Declension", pattern="catu card", sections={{columns={"pl"},
            rows={{label="dat", cells={{forms={{text="catunnaṃ", ending="catunnaṃ", index=1}}}}}}}}}
        local html = Render.render(value({paradigm=paradigm}), {paradigm_columns=1, content_em=6})
        local zwsp = "\226\128\139"
        assert.is_truthy(html:find('href="dpd:paradigm-form/1">c' .. zwsp .. "a" .. zwsp, 1, true))
        assert.equal("catunnaṃ", (html:match('href="dpd:paradigm%-form/1">(.-)</a>'):gsub(zwsp, "")))
    end)

    it("stacks a three-column section as two columns when its forms would not fit", function()
        local function form(text, index) return {forms={{text=text, ending="", index=index}}} end
        local paradigm = {lemma="eka 1", kind="Declension", pattern="eka card", sections={{columns={"masc sg", "fem sg", "neut sg"},
            rows={{label="abl", cells={form("ekamhā", 1), form("ekissāya", 2), form("ekamhā", 1)}}}}}}
        local narrow = Render.render(value({paradigm=paradigm}), {paradigm_columns=1, content_em=15})
        local _, tables = narrow:gsub("<table", "")
        assert.equal(2, tables)
        assert.is_truthy(narrow:find(">masc sg</th><th[^>]*>fem sg</th></tr>"))
        assert.is_truthy(narrow:find('href="dpd:paradigm-form/2">ekissāya</a>', 1, true))
        local wide = Render.render(value({paradigm=paradigm}), {paradigm_columns=1, content_em=30})
        _, tables = wide:gsub("<table", "")
        assert.equal(1, tables)
    end)

    it("places as many sections side by side as the popup width allows", function()
        local paradigm = fixture():paradigm({stem="sabb", pattern="a pron"}, "sabba 1", nil)
        local html = Render.render(value({paradigm=paradigm}), {paradigm_columns=2})
        local _, tables = html:gsub("<table", "")
        assert.equal(2, tables)
        assert.is_truthy(html:find('<th style="width: 21%%">Masculine sg</th><th style="width: 21%%">Masculine pl</th>'))
        assert.is_truthy(html:find('<p class="section">Neuter</p>', 1, true))
        assert.is_falsy(html:find('<p class="section">Masculine</p>', 1, true))
        -- "in comps" exists only in the masculine column; its feminine cells stay empty.
        assert.is_truthy(html:find('<td class="case">in comps</td><td><p class="form"><a href="dpd:paradigm%-form/%d+">sabba</a></p></td><td></td><td></td><td></td></tr>'))
        assert.is_falsy(html:find("is highlighted", 1, true))
    end)

    it("shows an explanation instead of a table when no paradigm exists", function()
        local html = Render.render(value({paradigm={lemma="x", error="DPD has no inflection template “q”."}}), {})
        assert.is_truthy(html:find("DPD has no inflection template", 1, true))
        assert.is_falsy(html:find("<table", 1, true))
    end)

    it("adds the IPA and a declension link to an expanded sense, but none for indeclinables", function()
        local sense = {id=7, lemma_1="dhamma 1.01", pos="masc", meaning_combo="nature"}
        local frame = {expanded={[7]=true}, details={[7]={grammar_line="masc", ipa_line="/d̪ʰəmmə/",
            paradigm_kind="Declension", construction="dhar + ma"}}}
        local html = Render.render(value({senses={sense}}), frame)
        assert.is_truthy(html:find('<td class="label">IPA</td><td>/d̪ʰəmmə/', 1, true))
        local link = html:find('href="dpd:detail-paradigm/7">Declension</a>', 1, true)
        assert.is_truthy(link)
        -- The origin comes first; the table button leads the row of buttons below it.
        assert.is_true(html:find("dhar + ma", 1, true) < link)
        frame.details[7].paradigm_kind = nil
        html = Render.render(value({senses={sense}}), frame)
        assert.is_falsy(html:find("detail-paradigm", 1, true))
    end)
end)

describe("DPD paradigm navigation", function()
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
        package.loaded["ui/widget/container/inputcontainer"] = {extend=function(_, v) return v end}
        local shown = {}
        package.loaded["ui/uimanager"] = {show=function(_, widget) shown[#shown+1] = widget end}
        package.loaded["ui/widget/infomessage"] = {new=function(_, v) return v end}
        local loaded = package.loaded["ui/dpd_viewer"]
        package.loaded["ui/dpd_viewer"] = nil
        local class = require("ui/dpd_viewer")
        package.loaded["ui/dpd_viewer"] = loaded
        for _, name in ipairs(names) do package.loaded[name] = saved[name] end
        return class, shown
    end
    local Viewer, shown = viewerClass()
    local function base(query)
        return {query=query, found=true, grammar={}, senses={{id=7, lemma_1="dhamma 1.01", pos="masc"}},
            deconstructions={}, components={}, suggestions={}, references={}, roots={}, variants={}}
    end

    it("opens the expanded sense's paradigm with the looked-up form, then looks up a tapped form", function()
        local calls = {}
        local lookup = {
            paradigm=function(_, id, selected)
                calls[#calls+1] = {id, selected}
                local result = base("dhamma 1.01")
                result.senses = {}
                result.paradigm = {lemma="dhamma 1.01", forms={"dhammo","dhammassa"}, sections={}}
                return result
            end,
            get=function(_, word, options)
                assert.is_false(options.approximate)
                local result = base(word)
                result.found = word == "dhammo"
                return result
            end,
        }
        local viewer = setmetatable({navigation=Navigation.new(base("dhammassa")), lookup=lookup,
            ratio=function() return .2 end, update=function(self) self.updated = true end,
            showError=function(_, err) error(err) end}, {__index=Viewer})
        viewer:followLink("dpd:detail-paradigm/7")
        assert.equal(0, #calls, "a collapsed sense offers no paradigm")
        local frame = viewer.navigation:current()
        frame.expanded[7], frame.details[7] = true, {paradigm_kind="Declension"}
        viewer:followLink("dpd:detail-paradigm/7")
        assert.same({{7, "dhammassa"}}, calls)
        assert.equal(2, #viewer.navigation.stack)
        viewer:followLink("dpd:paradigm-form/1")
        assert.equal(3, #viewer.navigation.stack)
        assert.equal("dhammo", viewer.navigation:current().model.query)
        viewer.navigation:back()
        viewer:followLink("dpd:paradigm-form/2")
        assert.equal(2, #viewer.navigation.stack, "an unknown form stays on the table")
        assert.is_truthy(shown[#shown].text:find("dhammassa", 1, true))
        viewer:followLink("dpd:paradigm-form/9")
        assert.equal(2, #viewer.navigation.stack)
    end)

    it("opens an English result's root with the root reader, other items as headwords", function()
        local calls = {}
        local lookup = {
            target=function(_, value, kind)
                calls[#calls+1] = {"target", value, kind}
                local result = base(value)
                result.senses, result.roots = {}, {{root="√kal 3"}}
                return result
            end,
            headword=function(_, lemma)
                calls[#calls+1] = {"headword", lemma}
                return base(lemma)
            end,
        }
        local value = base("add")
        value.english = {items={{lemma="√kal 3", pos="root", meaning="calculate, add"},
            {lemma="ādāna", pos="nt", meaning="taking"}}}
        local viewer = setmetatable({navigation=Navigation.new(value), lookup=lookup,
            ratio=function() return .2 end, update=function() end,
            showError=function(_, err) error(err) end}, {__index=Viewer})
        viewer:followLink("dpd:english-item/1")
        assert.same({"target", "√kal 3", "root"}, calls[1])
        assert.equal(2, #viewer.navigation.stack)
        viewer.navigation:back()
        viewer:followLink("dpd:english-item/2")
        assert.same({"headword", "ādāna"}, calls[2])
    end)

    it("resolves paradigm links inside inline component details", function()
        local value = base("x")
        value.deconstructions = {{parts={"dhamma","cakka"}, unique={true,true}, has_new=true, starts_open=true}}
        value.components = {dhamma={senses={{id=7}}}}
        local navigation = Navigation.new(value)
        local detail = {paradigm_kind="Declension"}
        navigation:toggleComponentSense(1, 1, 7, detail)
        local frame, uri, scoped = navigation:resolve("dpd:component-detail/1/1/detail-paradigm/7")
        assert.is_truthy(frame)
        assert.equal("dpd:detail-paradigm/7", uri)
        assert.equal(detail, scoped)
    end)
end)
