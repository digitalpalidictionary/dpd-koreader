local Normalize = require("dpd/normalize")
local Deconstruct = require("dpd/deconstruct")
local Lookup = require("dpd/lookup")
local SortKey = require("dpd/sortkey")
local Navigation = require("dpd/navigation")
local Direct = require("dpd/direct")
local Render = require("ui/dpd_render")

describe("selection normalization", function()
    it("cleans edge punctuation and preserves internal Pali", function()
        assert.equal("pacchimassa", Normalize.query(" “pacchimassa,” "))
        assert.equal("saṃ", Normalize.query("‘saṁ’"))
        assert.equal("saṅgha", Normalize.query("saṅgha"))
        assert.equal("tathāhaṃ", Normalize.query("tathā'haṃ"))
    end)
    it("aliases a closing double quote before ti, after the literal spelling", function()
        for _, input in ipairs({ "byādhayissasī”ti", 'byādhayissasī"ti', "“byādhayissasī”ti,”" }) do
            local candidates = Normalize.candidates(input)
            assert.equal("exact", candidates[1].via)
            assert.equal(Normalize.query(input), candidates[1].key)
            local aliased = false
            for _, candidate in ipairs(candidates) do
                if candidate.key == "byādhayissasīti" then aliased = candidate.via == "alias" end
            end
            assert.is_true(aliased, input)
        end
        -- Velthuis and other internal double quotes are not rewritten.
        for _, input in ipairs({ 'sa"ngha', 'a"bti', '1"ti' }) do
            for _, candidate in ipairs(Normalize.candidates(input)) do
                assert.not_equal("alias", candidate.via, input)
            end
        end
        assert.is_true(Normalize.isRewrite("tatthevantaradhāyathā”ti", "tatthevantaradhāyathāti"))
    end)
    it("lowercases Pali capitals and preserves abbreviation candidates", function()
        assert.equal("āīūṅñṭḍṇḷṃ", Normalize.lower("ĀĪŪṄÑṬḌṆḶṂ"))
        assert.same({ {key="SN",via="exact"}, {key="sn",via="ci"},
            {key="SN.",via="dot"}, {key="sn.",via="dot"} }, Normalize.candidates("SN."))
        assert.same({}, Normalize.candidates("“…”"))
    end)
    it("uses the mobile fuzzy rules only for suggestions", function()
        assert.equal("avaharisama", Normalize.fuzzy("avaharissāmā"))
        assert.equal("samantayitva", Normalize.fuzzy("saṃmantayitvā"))
        assert.equal("samantayitva", Normalize.fuzzy("sammantayitvā"))
        assert.equal("samantayitva", Normalize.fuzzy("samantayitvā"))
        assert.equal("kanti", Normalize.fuzzy("√ Khānti"))
        assert.equal("a", Normalize.fuzzy("ā"))
        assert.equal("kk", Normalize.fuzzy("kkk")) -- upstream substitutes pairs once
        assert.equal("saṃmantayitvā", Normalize.query("saṃmantayitvā"))
    end)
end)

describe("DPD ordering", function()
    it("reproduces upstream sort keys and its aspirate quirk", function()
        assert.equal("2901141439033301 2", SortKey("pacchima 2"))
        assert.equal("0939", SortKey("kh"))
        assert.equal("00024041", SortKey("√āḷṃ"))
        assert.is_true(SortKey("pacchima 1") < SortKey("pacchima 2"))
    end)
    it("matches Python DPD golden keys for 500 real lemmas", function()
        for _, row in ipairs(dofile("spec/fixtures/sortkeys.lua")) do
            assert.equal(row[2], SortKey(row[1]), row[1])
        end
    end)
end)

describe("analysis parsing", function()
    it("parses manual-correction spacing without splitting phrases", function()
        assert.same({"atha", "anena"}, Deconstruct.parse("atha+ anena"))
        assert.same({"ubho", "ettha"}, Deconstruct.parse("ubho  + ettha  "))
        assert.same({"nibbānaṃ uccati", "iti"}, Deconstruct.parse("nibbānaṃ uccati + iti"))
        for _, raw in ipairs({"", "a +", "+ a", "a ++ b"}) do assert.is_nil(Deconstruct.parse(raw)) end
    end)
    it("preserves malformed raw analyses without inventing components", function()
        local a = Deconstruct.analyses({"A ++ B", "A + C"})
        assert.equal("A ++ B", a[1].raw)
        assert.is_nil(a[1].parts)
        assert.same({"A", "C"}, a[2].parts)
    end)
end)

-- Analyses marked as Lookup marks them, with no DPD rows for their parts.
local function analyses(model, raws)
    model.deconstructions = Deconstruct.analyses(raws)
    Lookup.markAnalyses(model)
    return model
end

local function compound()
    return analyses({ query="compound", found=true, grammar={}, senses={}, components={} },
        {"vajja + kamma + appabhe + danti", "vajja + kammi + appabhe + danti", "vajja + kammā + appabhe + danti"})
end

describe("compound rendering and navigation", function()
    it("opens only the first analysis; another shows only its new words when opened", function()
        local model = compound()
        local navigation = Navigation.new(model)
        assert.same({true, false, false}, navigation:current().analyses)
        local html = Render.render(model, navigation:current())
        local _, count = html:gsub('class="component"', '')
        assert.equal(4, count)
        -- Closed headers stay navigable, and bold marks what each would add.
        assert.is_truthy(html:find('href="dpd:component/2/1">vajja</a>',1,true))
        assert.is_truthy(html:find('href="dpd:component/2/2"><b>kammi</b></a>',1,true))
        assert.is_truthy(html:find('href="dpd:component/1/2">kamma</a>',1,true)) -- no bold in the open one
        navigation:toggleAnalysis(3)
        html = Render.render(model, navigation:current())
        assert.is_truthy(html:find('<div class="component"><p><a href="dpd:component/3/2"',1,true))
        assert.is_falsy(html:find('<div class="component"><p><a href="dpd:component/3/1"',1,true))
        navigation:toggleAnalysis(1)
        html = Render.render(model, navigation:current())
        assert.is_truthy(html:find('dpd:component/1/',1,true)) -- collapsed header remains navigable
        local _, remaining = html:gsub('class="component"', '')
        assert.equal(1, remaining)
    end)
    it("restores parent expansion and scroll after component navigation", function()
        local navigation = Navigation.new(compound())
        navigation:toggleAnalysis(3)
        navigation:push({query="kammi"}, .4)
        navigation:toggleSense(42, {construction="kamma + ī"})
        assert.is_true(navigation:back())
        assert.same({true, false, true}, navigation:current().analyses)
        assert.equal(.4, navigation:current().ratio)
        assert.is_false(navigation:back())
    end)
    it("bounds Back history, keeping the popup's own result", function()
        local navigation = Navigation.new({query="root"})
        for i = 1, 50 do navigation:push({query="tap" .. i}) end
        assert.equal(Navigation.max_depth, #navigation.stack)
        assert.equal("tap50", navigation:current().model.query)
        local backs = 0
        while navigation:back() do backs = backs + 1 end
        assert.equal(Navigation.max_depth - 1, backs)
        assert.equal("root", navigation:current().model.query)
    end)
    it("compares each later analysis with the first open one only, and within itself", function()
        local model = analyses({query="compound", found=true, grammar={}, senses={}, components={}},
            {"A + B + A + C", "A + D + C", "A + D + E", "A + B + E"})
        assert.same({true,false,false,false}, Navigation.new(model):current().analyses)
        assert.same({true,true,false,true}, model.deconstructions[1].unique)
        assert.same({false,true,false}, model.deconstructions[2].unique)
        -- D is new again: analysis 2, which explained it, may stay closed.
        assert.same({false,true,true}, model.deconstructions[3].unique)
        assert.same({false,false,true}, model.deconstructions[4].unique)
        local forms = analyses({query="forms", found=true, grammar={}, senses={}, components={}},
            {"saṁ + kamma", "saṃ + kammā", "SAṂ + kamma"})
        assert.same({false,true}, forms.deconstructions[2].unique)
        assert.is_false(forms.deconstructions[3].has_new)
        -- Nothing new: a plain row with nothing to expand, even if marked open.
        local frame = Navigation.new(forms):current()
        frame.analyses[3] = true
        local html = Render.render(forms, frame)
        assert.is_falsy(html:find('dpd:analysis/3',1,true))
        assert.is_truthy(html:find('<p class="row still"><a href="dpd:component/3/',1,true))
        assert.is_falsy(html:find('dpd:component-sense/3/',1,true))
        assert.is_falsy(html:find('<div class="component"><p><a href="dpd:component/3/',1,true))
    end)
    it("opens the first analysis that adds to the headwords", function()
        local function part(id) return {senses={{id=id, lemma_1="w" .. id}}, reference_targets={}} end
        local model = analyses({query="xy", found=true, grammar={}, senses={{id=1, lemma_1="w1"}},
            components={x=part(1), y=part(2)}}, {"x", "x + y", "y + x"})
        assert.is_false(model.deconstructions[1].has_new)
        assert.same({false, true}, model.deconstructions[2].unique)
        assert.same({false, false}, model.deconstructions[3].unique)
        local frame = Navigation.new(model):current()
        assert.same({false, true, false}, frame.analyses)
        -- x is the headword: analysis 1 still opens to say so. Analysis 3
        -- spells both parts as analysis 2 does, so it has nothing to show.
        assert.same({[1]={headword=true}}, model.deconstructions[1].same)
        assert.is_nil(model.deconstructions[3].same)
        frame.analyses[1] = true
        local html = Render.render(model, frame)
        assert.is_truthy(html:find('<span class="count">· same as the headword above</span>', 1, true))
        assert.is_truthy(html:find('href="dpd:analysis/1"', 1, true))
        assert.is_falsy(html:find('href="dpd:analysis/3"', 1, true))
        -- A part spelled as its headword (itīti: iti + iti) needs no line.
        local same = analyses({query="xx", found=true, grammar={}, senses={{id=1, lemma_1="x 1"}},
            components={x=part(1)}}, {"x + x"})
        assert.is_nil(same.deconstructions[1].same)
        assert.is_false(same.deconstructions[1].has_new)
    end)
    it("renders inline DPD formatting without introducing source controls or leaking styles", function()
        assert.equal('<b>bold <i>italic</i></b><br>x &amp; y',
            Render.inline('<B>bold <i>italic</i></B><BR/>x & y'))
        assert.equal('a &amp; b &lt;literal&gt; &nbsp;', Render.inline('a &amp; b &lt;literal&gt; &nbsp;'))
        assert.equal('<b>unclosed</b>', Render.inline('<b>unclosed'))
        assert.equal('see <i>rūpa.</i> <sup>1</sup>.', Render.inline('see <i>rūpa</i>. <sup>1</sup>.'))
        assert.is_falsy(Render.inline('<a href="dpd:normal">x</a>'):find('<a ',1,true))
        assert.is_falsy(Render.inline('<b onclick="x">x</b>'):find('<b onclick',1,true))
        -- Prose angle brackets stay text; DPD's own link/span markup keeps only its words.
        assert.equal('a &lt; b &gt; c', Render.inline('a < b > c'))
        assert.equal('see inside TPP', Render.inline('see <a class="link" href="https://x">inside TPP</a>'))
        assert.equal('<br>gray', Render.inline("<br/><span class='gray'>gray</span>"))
        assert.equal('&lt;script&gt;x&lt;/script&gt;', Render.inline('<script>x</script>'))
        -- A stray "<" before a real tag keeps the tag; unclosed runs stay linear.
        assert.equal('a &lt; b <i>x</i>', Render.inline('a < b <i>x</i>'))
        local clock = os.clock()
        assert.equal(string.rep('&lt;', 100000), Render.inline(string.rep('<', 100000)))
        assert.is_true(os.clock() - clock < 2)
        local model = {query="a",found=true,grammar={},deconstructions={},components={},
            senses={{id=1,lemma_1='a',pos='adj',meaning_combo='<b>meaning</b>'}}}
        local html = Render.render(model, {expanded={[1]=true}, details={[1]={
            construction='acc<b>āyi</b>ka',example_1='a <b>word</b>',notes='<i>note</i>'}}})
        assert.is_truthy(html:find('acc<b>āyi</b>ka',1,true))
        assert.is_truthy(html:find('a <b>word</b>',1,true))
        assert.is_truthy(html:find('<i>note</i>',1,true))
        assert.is_truthy(html:find('<b>meaning</b>',1,true))
    end)
    it("escapes dictionary data and omits empty detail fields", function()
        local model = {query='<unsafe>', found=true, grammar={}, deconstructions={}, components={},
            senses={{id=1,lemma_1='<script>',pos='adj',meaning_combo='a & b'}}}
        local html = Render.render(model, {expanded={[1]=true}, details={[1]={construction='x<br>y'}}})
        assert.is_falsy(html:find('<script>',1,true))
        assert.is_truthy(html:find('&lt;script&gt;',1,true))
        assert.is_truthy(html:find('a &amp; b',1,true))
        assert.is_truthy(html:find('x<br>y',1,true))
        assert.is_falsy(html:find('Derived from:',1,true))
    end)
end)

describe("direct lookup wrapper", function()
    it("intercepts hits and preserves all fallback arguments on misses or errors", function()
        local calls, args = 0
        local original = function(_, ...) calls=calls+1; args={...}; return "normal" end
        local dict = setmetatable({}, {__index={onLookupWord=original}})
        local hook = Direct.install(dict, function(word)
            if word == "error" then error("bad database") end
            return word == "pacchima"
        end)
        assert.is_true(dict:onLookupWord("pacchima"))
        assert.equal(0, calls)
        local highlight, callback = {}, function() end
        assert.equal("normal", dict:onLookupWord("miss", false, {}, highlight, nil, callback))
        assert.equal(highlight, args[4])
        assert.equal(callback, args[6])
        assert.equal("normal", dict:onLookupWord("error"))
        hook:remove()
        assert.is_nil(rawget(dict,"onLookupWord"))
        assert.equal(original, dict.onLookupWord)
    end)
    it("does not clobber another plugin's later wrapper", function()
        local dict = {onLookupWord=function() end}
        local hook = Direct.install(dict, function() return false end)
        local later = function() end
        dict.onLookupWord = later
        hook:remove()
        assert.equal(later, dict.onLookupWord)
    end)
end)
