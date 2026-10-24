local Navigation = require("dpd/navigation")
local Render = require("ui/dpd_render")

local function model(query, extra)
    local value = {query=query, found=true, senses={}, deconstructions={}, components={},
        suggestions={}, references={}, roots={}, variants={}}
    for key, field in pairs(extra or {}) do value[key] = field end
    return value
end

local function sense(id, lemma)
    return {id=id, lemma_1=lemma, pos="noun", meaning_combo="meaning of " .. lemma}
end

local function compound()
    return model("ab", {
        senses={sense(7, "whole")},
        deconstructions={{parts={"a", "b"}, unique={true, true}, has_new=true, starts_open=true},
            {parts={"a", "b"}, unique={false, false}, has_new=false}},
        components={a={senses={sense(7, "a 1"), sense(8, "a 2"), sense(9, "a 3")}, total=3},
            b={senses={sense(7, "a 1")}, total=1}},
    })
end

describe("learning details and exact navigation", function()
    it("shows lexical etymology safely without editorial or inflection tags", function()
        local value = model("kammī", {senses={sense(1, "kammī")}})
        local frame = Navigation.new(value):current()
        frame.expanded[1] = true
        frame.details[1] = {sanskrit="karmin [kṛ]", cognate="<b>related</b>",
            non_ia='<a href="dpd:normal">other</a>', root_sign="ṇī", origin="pass2", stem="kammī",
            pattern="masc", notes="-"}
        local html = Render.render(value, frame)
        assert.is_truthy(html:find("<i>Sanskrit:</i> karmin [kṛ]", 1, true))
        assert.is_truthy(html:find("<i>Cognates:</i> <b>related</b>", 1, true))
        assert.is_truthy(html:find("<i>Non-Indo-Aryan origin:</i> other", 1, true))
        assert.is_truthy(html:find("<i>Root sign:</i> ṇī", 1, true))
        assert.is_falsy(html:find("pass2", 1, true))
        assert.is_falsy(html:find("Pattern:", 1, true))
        assert.is_falsy(html:find('href="dpd:normal"', 1, true))
    end)

    it("links only exact matched construction segments and retains unmatched text", function()
        local value = model("ab", {senses={sense(1, "ab")}})
        local frame = Navigation.new(value):current()
        frame.expanded[1] = true
        frame.details[1] = {construction="a + unmatched",
            targets={{model=model("a")}},
            field_parts={construction={{text="a", target_index=1}, {text=" + unmatched"}}}}
        local html = Render.render(value, frame)
        assert.is_truthy(html:find('<a href="dpd:detail-target/1/1">a</a> + unmatched', 1, true))
        assert.is_falsy(html:find("detail-target/1/2", 1, true))
    end)

    it("trims a component sense's grammar like a headword's", function()
        local value = compound()
        local navigation = Navigation.new(value)
        navigation:toggleComponentSense(1, 1, 7, {grammar_line="noun, from x, irreg", derived_from="x"})
        local html = Render.render(value, navigation:current())
        assert.is_truthy(html:find("<i>Grammar:</i> irreg</p>", 1, true))
    end)

    it("keeps component expansions independent by analysis, part and actual sense ID", function()
        local value = compound()
        local navigation = Navigation.new(value)
        local frame = navigation:current()
        local detail_a = {sanskrit="alpha", construction="base", targets={{model=model("base")}},
            field_parts={construction={{text="base", target_index=1}}}}
        local detail_b = {sanskrit="beta"}
        assert.is_true(navigation:toggleComponentSense(1, 1, 7, detail_a))
        assert.is_true(navigation:toggleComponentSense(1, 2, 7, detail_b))
        navigation:toggleSense(7, {sanskrit="whole"})
        assert.same(detail_a, navigation:componentDetail(1, 1, 7))
        assert.same(detail_b, navigation:componentDetail(1, 2, 7))
        assert.same({sanskrit="whole"}, frame.details[7])
        assert.is_nil(navigation:toggleComponentSense(1, 1, 999, {}))
        assert.is_nil(navigation:toggleComponentSense(1, 1, 9, {}))
        assert.is_nil(navigation:toggleComponentSense(2, 1, 7, {}))
        local html = Render.render(value, frame)
        assert.is_truthy(html:find('href="dpd:component-sense/1/1/7"', 1, true))
        assert.is_truthy(html:find('href="dpd:component-sense/1/1/8"', 1, true))
        assert.is_truthy(html:find('href="dpd:component-detail/1/1/detail-target/7/1"', 1, true))
        -- The count joins the name link, and is absent for a component whose only sense is shown.
        assert.is_truthy(html:find('href="dpd:component/1/1"><b>a</b> <span class="count">·&nbsp;3&nbsp;senses&nbsp;›</span></a>', 1, true))
        assert.is_falsy(html:find("more senses", 1, true))
        assert.is_falsy(html:find("All 1 sense", 1, true))
        assert.is_falsy(html:find("View all", 1, true))
        assert.is_falsy(html:find('href="dpd:component/1/2"><b>b</b> <span', 1, true))
        local _, links = html:gsub('href="dpd:component/1/1"', "")
        assert.equal(2, links) -- analysis header part, component name with count
        navigation:toggleComponentSense(1, 1, 7, {})
        assert.is_nil(navigation:componentDetail(1, 1, 7))
        assert.same(detail_b, navigation:componentDetail(1, 2, 7))
        assert.is_true(frame.expanded[7])
    end)

    it("scopes nested component controls and rejects hidden or unrelated details", function()
        local leaf = compound()
        local middle = model("middle", {references={{kind="see", target="ab", model=leaf}}})
        local value = model("selected", {single_suggestion=true,
            suggestions={{query="middle", model=middle}}})
        local navigation = Navigation.new(value)
        local root = navigation:current()
        local frame = root.suggestions[1].references[1]
        local detail = {construction="a", targets={{model=model("a")}},
            field_parts={construction={{text="a", target_index=1}}},
            families={{kind="word", key="a", title="Word family: a", count=3}}}
        navigation:toggleComponentSense(1, 1, 7, detail, frame)
        local uri = "dpd:similar/1/reference/1/component-detail/1/1/detail-target/7/1"
        local owner, action, resolved = navigation:resolve(uri)
        assert.equal(frame, owner)
        assert.equal("dpd:detail-target/7/1", action)
        assert.equal(detail, resolved)
        local html = Render.render(value, root)
        assert.is_truthy(html:find('href="' .. uri .. '"', 1, true))
        assert.is_truthy(html:find('dpd:similar/1/reference/1/component-detail/1/1/detail-family/7/1', 1, true))
        assert.is_nil(navigation:resolve("dpd:similar/1/reference/1/component-detail/1/2/detail-target/7/1"))
        navigation:toggleAnalysis(1, frame)
        assert.is_nil(navigation:resolve(uri))
        navigation:toggleAnalysis(1, frame)
        assert.equal(frame, navigation:resolve(uri))
        navigation:toggleReference(1, root.suggestions[1])
        assert.is_nil(navigation:resolve(uri))
    end)

    it("underlines navigation links but not in-place chevron toggles", function()
        local value = compound()
        value.grammar = {{pos="noun", parse="nom sg", headword="whole"}}
        local frame = Navigation.new(value):current()
        local html = Render.render(value, frame)
        assert.is_truthy(Render.css:find("a[href] { color: #000; text-decoration: underline; }", 1, true))
        assert.is_truthy(Render.css:find("a.toggle, .footer a, a.plain { text-decoration: none; }", 1, true))
        assert.is_truthy(html:find('href="dpd:sense/7" class="toggle">', 1, true))
        assert.is_truthy(html:find('href="dpd:analysis/1" class="toggle">', 1, true))
        assert.is_truthy(html:find('href="dpd:component-sense/1/1/7" class="toggle">', 1, true))
        assert.is_truthy(html:find('href="dpd:grammar-sense/1">whole</a>', 1, true))
        assert.is_truthy(html:find('href="dpd:component/1/1"><b>a</b> <span class="count">·&nbsp;3&nbsp;senses&nbsp;›</span></a>', 1, true))
        for anchor in html:gmatch("<a [^>]*>[^<]*") do
            local toggle = anchor:find('class="toggle"', 1, true) ~= nil
            local chevron = anchor:find("▾", 1, true) or anchor:find("▸", 1, true)
            assert.equal(toggle, chevron ~= nil, anchor)
        end
    end)

    it("keeps all analysis components reachable without nested anchors or repeated summaries", function()
        local value = compound()
        local frame = Navigation.new(value):current()
        frame.analyses[2] = true
        local html = Render.render(value, frame)
        assert.is_truthy(html:find('href="dpd:component/2/1"', 1, true))
        assert.is_truthy(html:find('href="dpd:component/2/2"', 1, true))
        -- Nothing in analysis 2 is new, so it has no toggle to open.
        assert.is_falsy(html:find('href="dpd:analysis/2"', 1, true))
        assert.is_falsy(html:find('href="dpd:component-sense/2/', 1, true))
        for anchor in html:gmatch("<a.-</a>") do
            assert.is_nil(anchor:sub(3):find("<a", 1, true))
        end
    end)

    it("preserves selected-form damaged warnings for a single suggested definition", function()
        local value = model("bad", {single_suggestion=true, damaged={"variant readings"},
            suggestions={{query="good", model=model("good", {senses={sense(1, "good")}})}}})
        local html = Render.render(value, Navigation.new(value):current())
        assert.is_truthy(html:find("Some DPD details could not be read. Affected data: variant readings", 1, true))
        assert.is_truthy(html:find("<b>good</b>", 1, true))
        assert.is_falsy(html:find("KOReader dictionary", 1, true))
    end)
end)

describe("paged learning families", function()
    it("renders lazy sense and root launch controls without family member payloads", function()
        local group = {kind="root", key="√dhar", title="Root family: √dhar", count=578}
        local value = model("dhamma", {senses={sense(1, "dhamma")},
            roots={{root="√dhar", root_meaning="hold", families={group}}}})
        local frame = Navigation.new(value):current()
        frame.expanded[1] = true
        frame.details[1] = {families={group}}
        local html = Render.render(value, frame)
        assert.is_truthy(html:find('href="dpd:detail-family/1/1"', 1, true))
        assert.is_truthy(html:find('href="dpd:root-family/1/1"', 1, true))
        assert.is_truthy(html:find('href="dpd:root-family/1/1">Root family: √dhar</a> · 578', 1, true))
    end)

    it("places related-word links before long examples and notes", function()
        local group = {kind="word", key="dhamma", title="Word family: dhamma", count=12}
        local value = model("dhamma", {senses={sense(1, "dhamma")}})
        local frame = Navigation.new(value):current()
        frame.expanded[1] = true
        frame.details[1] = {construction="dhar + ma", example_1="a long example",
            notes="a note", families={group}}
        local html = Render.render(value, frame)
        local family = html:find('href="dpd:detail-family/1/1"', 1, true)
        assert.is_truthy(family)
        assert.is_true(html:find("dhar + ma", 1, true) < family)
        assert.is_true(family < html:find("a long example", 1, true))
        assert.is_true(family < html:find("Notes:", 1, true))
    end)

    it("renders numbered identity, unavailable members and bounded pagination safely", function()
        local value = model("family", {family={title="Compounds: dhamma", total=578,
            has_more=true, items={{lemma="dhamma 1.01", pos="noun", meaning="<b>meaning</b>", available=true},
                {lemma="missing", pos="adj", meaning='<a href="dpd:normal">prose</a>', available=false}}}})
        local html = Render.render(value, Navigation.new(value):current())
        assert.is_truthy(html:find('href="dpd:family-member/1"', 1, true))
        assert.is_truthy(html:find("<b>dhamma 1.01</b>", 1, true))
        assert.is_falsy(html:find('href="dpd:family-member/2"', 1, true))
        assert.is_falsy(html:find('href="dpd:normal"', 1, true))
        assert.is_truthy(html:find("2&nbsp;of&nbsp;578&nbsp;entries", 1, true))
        assert.is_truthy(html:find('href="dpd:family-more"', 1, true))
    end)

    it("shows malformed-family errors as text and does not promise more data", function()
        local value = model("family", {family={title="Broken family", total=0, items={},
            error='<script>unreadable family</script>'}})
        local html = Render.render(value, Navigation.new(value):current())
        assert.is_truthy(html:find("&lt;script&gt;unreadable family&lt;/script&gt;", 1, true))
        assert.is_falsy(html:find("dpd:family-more", 1, true))
        assert.is_falsy(html:find("No entries in this family", 1, true))
    end)
end)
