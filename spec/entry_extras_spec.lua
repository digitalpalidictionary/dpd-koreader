local Json = require("json")
local Traditional = require("dpd/traditional")
local Lookup = require("dpd/lookup")
local Families = require("dpd/families")
local Render = require("ui/dpd_render")

local function value(extra)
    local result = {query="x", found=true, grammar={}, senses={}, deconstructions={},
        components={}, suggestions={}, references={}, roots={}, variants={}}
    for key, field in pairs(extra or {}) do result[key] = field end
    return result
end

describe("traditional lemma", function()
    it("follows DPD's nine-pattern rule and drops the homonym number", function()
        assert.equal("satthu", Traditional.lemma{lemma_1="satthar 1.02", stem="satth*", pattern="ar masc"})
        assert.equal("sīlavantu", Traditional.lemma{lemma_1="sīlavant", stem="sīlav", pattern="ant adj"})
        assert.equal("mātu", Traditional.lemma{lemma_1="mātar", stem="*", pattern="mātar fem"})
        assert.equal("arahanta", Traditional.lemma{lemma_1="arahant 1", stem="*", pattern="arahant masc"})
    end)

    it("is absent for other patterns, inflected-form stems and identical results", function()
        assert.is_nil(Traditional.lemma{lemma_1="dhamma 1.01", stem="dhamm", pattern="a masc"})
        assert.is_nil(Traditional.lemma{lemma_1="katvā", stem="!", pattern="ar masc"})
        assert.is_nil(Traditional.lemma{lemma_1="satthu", stem="satth", pattern="ar masc"})
        assert.is_nil(Traditional.lemma{})
        assert.is_nil(Traditional.lemma(nil))
    end)
end)

describe("expanded-sense additions", function()
    local function detailFor(row)
        local queries = 0
        local db = {query=function() return {} end,
            detail=function(_, id) queries = queries + 1; row.id = id; return row end}
        local detail = Lookup.new(db):detail(7)
        return detail, queries
    end

    it("adds the traditional lemma, status and link from the one detail query", function()
        local detail, queries = detailFor{lemma_1="satthar 1.02", stem="satth*", pattern="ar masc",
            meaning_1="teacher", source_1="MN1"}
        assert.equal(1, queries)
        assert.equal("satthu", detail.traditional_line)
        assert.equal("✔ complete", detail.status_line)
        assert.equal("dpdict.net/7", detail.link_line)
        assert.is_nil(detail.web_line)
    end)

    it("shows DPD's web links as text", function()
        -- akka 2 (ID 295) and ID 9115 in the official mobile database.
        local detail = detailFor{meaning_1="crown flower", link="https://en.wikipedia.org/wiki/Calotropis_gigantea"}
        assert.equal("https://en.wikipedia.org/wiki/Calotropis_gigantea", detail.web_line)
        detail = detailFor{link="https://en.wikipedia.org/wiki/Checkered_keelback\nhttps://en.wikipedia.org/wiki/Indian_cobra"}
        assert.equal("https://en.wikipedia.org/wiki/Checkered_keelback, https://en.wikipedia.org/wiki/Indian_cobra",
            detail.web_line)
        local html = Render.render(value({senses={{id=7, lemma_1="akka 2", pos="masc"}}}),
            {expanded={[7]=true}, details={[7]={web_line="https://x.org/a_b", status_line="✔ complete"}}})
        assert.is_true(html:find("<i>Web link:</i> https://x.org/a_b (requires internet)", 1, true)
            < html:find("✔ complete", 1, true))
    end)

    it("marks DPD's degree of completion", function()
        local half = detailFor{meaning_1="teacher", source_1=""}
        assert.equal("◑ meaning, no source yet", half.status_line)
        -- As upstream: a stored "-" is a value, so the entry is complete.
        assert.equal("✔ complete", detailFor{meaning_1="teacher", source_1="-"}.status_line)
        assert.equal("✘ incomplete", detailFor{meaning_2="auto"}.status_line)
        assert.equal("◑ meaning, no source yet", detailFor{meaning_1="-"}.status_line)
        local none = detailFor{meaning_1="", meaning_2="auto"}
        assert.equal("✘ incomplete", none.status_line)
        assert.is_nil(none.traditional_line)
    end)

    it("renders the new fields in order: identity near the grammar, metadata last", function()
        local sense = {id=7, lemma_1="satthar 1.02", pos="masc", meaning_combo="teacher"}
        local frame = {expanded={[7]=true}, details={[7]={grammar_line="masc", ipa_line="/s̪ət̪t̪ʰər/",
            traditional_line="satthu", notes="a note", status_line="✔ complete",
            link_line="dpdict.net/7"}}}
        local html = Render.render(value({senses={sense}}), frame)
        local function at(text) return assert(html:find(text, 1, true), text) end
        assert.is_true(at("<i>IPA:</i>") < at("<i>Traditional lemma (grammar-book headword):</i> satthu"))
        assert.is_true(at("<i>Notes:</i>") < at("✔ complete"))
        assert.is_true(at("✔ complete") < at("dpdict.net/7"))
        assert.is_nil(html:find("Early Buddhist texts", 1, true))
    end)

    it("shows the root's meaning after the root, outside its link", function()
        local sense = {id=7, lemma_1="samaya 1.1", pos="masc", meaning_combo="time"}
        local frame = {expanded={[7]=true}, details={[7]={root_key="√i 1", root_meaning="come, go",
            field_parts={root_key={{text="√i 1", target_index=1}}}, targets={{text="√i 1", kind="root", model={}}}}}}
        local html = Render.render(value({senses={sense}}), frame)
        assert.is_truthy(html:find("√i 1</a> (come, go)</p>", 1, true))
        frame.details[7].root_meaning = nil
        assert.is_truthy(Render.render(value({senses={sense}}), frame):find("√i 1</a></p>", 1, true))
    end)
end)

describe("compact expanded sense", function()
    local function expanded(detail, pos)
        local sense = {id=7, lemma_1="dhamma 1.01", pos=pos or "masc", meaning_combo="nature"}
        return Render.render(value({senses={sense}}), {expanded={[7]=true}, details={[7]=detail}})
    end

    it("keeps only the grammar the sense row and origin do not already say", function()
        -- dhamma 1.01, 1.04 and 1.12, and akaṭa 3, in the official mobile database.
        local html = expanded({grammar_line="masc, from dharati", derived_from="dharati"})
        assert.is_falsy(html:find("Grammar:", 1, true))
        assert.is_truthy(html:find("<i>from</i> dharati", 1, true))
        html = expanded({grammar_line="masc, normally pl dhammā, from dharati", derived_from="dharati"})
        assert.is_truthy(html:find("<i>Grammar:</i> normally pl dhammā</p>", 1, true))
        html = expanded({grammar_line="nt, from dharati, irreg", derived_from="dharati"}, "nt")
        assert.is_truthy(html:find("<i>Grammar:</i> irreg</p>", 1, true))
        html = expanded({grammar_line="pp of na karoti", derived_from="karoti"}, "pp")
        assert.is_truthy(html:find("<i>Grammar:</i> pp of na karoti</p>", 1, true))
    end)

    it("leaves out a suffix or compound construction the construction already shows", function()
        local html = expanded({construction="√dhar + ma", suffix="ma"})
        assert.is_falsy(html:find("Suffix:", 1, true))
        html = expanded({construction="√kar + a", suffix="ta"})
        assert.is_truthy(html:find("<i>Suffix:</i> ta", 1, true))
        html = expanded({construction="dhamma + cakka", compound_construction="dhamma + cakka"})
        assert.is_falsy(html:find("Compound construction:", 1, true))
        html = expanded({construction="buddha + anussati", compound_construction="buddha + anussati + ti"})
        assert.is_truthy(html:find("<i>Compound construction:</i> buddha + anussati + ti", 1, true))
    end)

    it("names a family button only when the entry does not already", function()
        local html = expanded({lemma_1="dhamma 1.01", root_key="√dhar 1", families={
            {kind="root", title="Root family: √dhar", count=84},
            {kind="compound", title="Compounds: dhamma", count=578},
            {kind="set", title="Thematic set: qualities", count=9}}})
        assert.is_truthy(html:find('href="dpd:detail-family/7/1">Root family · 84</a>', 1, true))
        assert.is_truthy(html:find('href="dpd:detail-family/7/2">Compounds · 578</a>', 1, true))
        assert.is_truthy(html:find('href="dpd:detail-family/7/3">Thematic set: qualities · 9</a>', 1, true))
        -- akkanta 1's family is prefixed; dhammacakka has two compound families.
        html = expanded({lemma_1="akkanta 1", root_key="√kam 1",
            families={{kind="root", title="Root family: ā √kam", count=5}}})
        assert.is_truthy(html:find(">Root family: ā √kam · 5</a>", 1, true))
        html = expanded({lemma_1="dhammacakka", families={{kind="compound", title="Compounds: dhamma", count=578},
            {kind="compound", title="Compounds: cakka", count=41}}})
        assert.is_truthy(html:find(">Compounds: dhamma · 578</a>", 1, true))
        assert.is_truthy(html:find(">Compounds: cakka · 41</a>", 1, true))
    end)

    it("cites each example inside its paragraph and keeps verse lines", function()
        local html = expanded({example_1="line one,\nline two.", source_1="SNP4",
            sutta_1="kasibhāradvājasuttaṃ\nuragavaggo 4", example_2="prose", source_2="-", sutta_2="nakhasikhā"})
        assert.is_truthy(html:find('<p class="example">line one,<br>line two.<br><span class="cite">&#8195;— '
            .. 'SNP4 · kasibhāradvājasuttaṃ · uragavaggo 4</span></p>', 1, true))
        assert.is_truthy(html:find('<p class="example">prose<br><span class="cite">&#8195;— nakhasikhā</span></p>', 1, true))
        assert.is_falsy(html:find("Example 1:", 1, true))
    end)

    it("keeps short small-type items whole but lets long ones wrap", function()
        local long = string.rep("dharma ", 12)
        local html = expanded({ipa_line="/d̪ʰəmmə/", sanskrit=long})
        assert.is_truthy(html:find('<span class="item"><i>IPA:</i> /d̪ʰəmmə/</span>', 1, true))
        assert.is_truthy(html:find('<p class="meta"><i>Sanskrit:</i> ' .. long, 1, true))
    end)
end)

describe("ID search", function()
    it("opens exactly one headword by ID and rejects invalid IDs", function()
        local db = {senses=function(_, ids)
            return ids[1] == 34626 and {{id=34626, lemma_1="dhamma 1.01", pos="masc", meaning_1="nature"}} or {}
        end}
        local lookup = Lookup.new(db)
        local result = lookup:byId(34626)
        assert.is_true(result.found)
        assert.equal("dhamma 1.01", result.query)
        assert.equal(1, #result.senses)
        assert.equal(34626, result.senses[1].id)
        assert.is_nil(lookup:byId(1))
        for _, bad in ipairs({0, -3, 1.5, "x"}) do assert.is_nil(lookup:byId(bad)) end
    end)
end)

describe("family completion marks", function()
    it("keep each member's fourth item through the adapter and into the page", function()
        local data = Json.encode({{"dhamma 1.01","masc","nature","✔"},{"dhamma 1.02","masc","thing"}})
        local db = {query=function(_, sql)
            if sql:find("PRAGMA", 1, true) then return {{name="word_family"},{name="data"},{name="count"}} end
            if sql:find("SELECT data", 1, true) then return {{data=data}} end
            return {{family_key="dhamma", count=2}}
        end}
        local page = Families.new(db):page("word", "dhamma")
        assert.equal("✔", page.items[1].completion)
        assert.is_nil(page.items[2].completion)
        local html = Render.render(value({family={title="Word family: dhamma", total=2, items=page.items}}), {})
        assert.is_truthy(html:find("nature ✔", 1, true))
    end)
end)
