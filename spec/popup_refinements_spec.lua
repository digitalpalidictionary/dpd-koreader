local Navigation = require("dpd/navigation")
local Render = require("ui/dpd_render")

local function model(query, extra)
    local value = {query=query, found=true, senses={}, deconstructions={}, components={},
        suggestions={}, references={}, roots={}, variants={}, grammar={}}
    for key, field in pairs(extra or {}) do value[key] = field end
    return value
end

local function sense(id, lemma)
    return {id=id, lemma_1=lemma, pos="noun", meaning_combo="meaning of " .. lemma}
end

describe("popup refinements", function()
    it("sets the parses toggle off with space, keeping the bar between parses", function()
        local p = function(pos, parse, headword) return {pos=pos, parse=parse, headword=headword} end
        local value = model("vāda", {grammar={p("adj","masc voc sg","vāda"), p("noun","masc voc sg","vāda"),
            p("noun","masc nom sg","vādin"), p("pr","3rd sg","vadati"), p("pp","nt nom sg","vutta")}})
        local html = Render.render(value, Navigation.new(value):current(), nil, nil, {content_em=40, target_em=2.5, buttons={}})
        local header = html:match('<p class="grammar grammar%-more">(.-)</p>')
        assert.is_truthy(header)
        assert.is_truthy(header:find("|", 1, true)) -- between the two parses shown
        assert.is_falsy(header:find('|\226\128\130 <a href="dpd:grammar-toggle"', 1, true))
        assert.is_truthy(header:find('\226\128\130 \226\128\130\226\128\130<a href="dpd:grammar-toggle"', 1, true))
    end)

    it("names a family list and its size in the title, not in the body", function()
        local value = model("dhamma", {family={title="Idioms: dhamma", total=19,
            items={{lemma="diṭṭhe dhamme", pos="idiom", meaning="in this life", available=true}}}})
        assert.equal("Idioms: dhamma · 19", Render.title(value))
        assert.equal("dhamma", Render.title(model("dhamma")))
        local html = Render.render(value, Navigation.new(value):current())
        assert.is_falsy(html:find("Idioms: dhamma", 1, true))
        assert.is_truthy(html:find("diṭṭhe dhamme", 1, true))
    end)

    it("labels compound splits plainly and drops part headings that repeat their rows", function()
        local value = model("vissajjiyavebhaṅgiyaṃ", {
            deconstructions={{parts={"vissajjiya", "vebhaṅgiyaṃ"}, unique={true, true}, has_new=true, starts_open=true}},
            components={vissajjiya={senses={sense(1, "vissajjiya 1"), sense(2, "vissajjiya 2")}, total=2},
                ["vebhaṅgiyaṃ"]={senses={sense(3, "vebhaṅgiya")}, total=1}}})
        local layout = {content_em=30, target_em=2.5, buttons={}}
        local html = Render.render(value, Navigation.new(value):current(), nil, nil, layout)
        assert.is_truthy(html:find('<h3 class="lead">1 possible split <span class="quiet">· not yet checked by DPD</span></h3>', 1, true))
        -- The chevron alone toggles the analysis, with a button's tap area.
        assert.is_truthy(html:find('<p class="row"><a href="dpd:analysis/1" class="toggle">▾[^<]*</a><a href="dpd:component/1/1">vissajjiya</a>'))
        assert.same({width_em=2.4, height_em=2.5}, layout.buttons["dpd:analysis/1"])
        assert.is_truthy(html:find('<div class="component bare">%s*<p class="row">'))
        assert.is_falsy(html:find('<div class="component"><p><a href="dpd:component/1/1">', 1, true))
        assert.is_truthy(html:find('<div class="component"><p><a href="dpd:component/1/2"><b>vebhaṅgiyaṃ</b></a>', 1, true))
    end)

end)
