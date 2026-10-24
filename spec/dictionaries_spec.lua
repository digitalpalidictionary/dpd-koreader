local Dictionaries = require("dpd/dictionaries")
local Render = require("ui/dpd_render")

local entries = {
    { id = 1, dict_id = "dppn", word = "Sāriputta", word_fuzzy = "sariputa", html = "<p><span class=\"Head\">01.</span> Chief <b>disciple</b>.</p>" },
    { id = 2, dict_id = "cpd", word = "kamma", word_fuzzy = "kama", html = "<?xml version='1.0'?><article><h2><b>kamma</b></h2>, <i>n.</i> work-<br/>ing<br/>deed</article>" },
    { id = 3, dict_id = "nyanatiloka", word = "kamma", word_fuzzy = "kama", html = "<p>action</p>" },
    { id = 4, dict_id = "mw", word = "karman", word_fuzzy = "karman", html = "<html><head><title>x</title></head><body><p><span class=\"sdata\">karman</span> <span class=\"record-id\">[ID=1]</span><a href=\"https://x\">scan</a></p></body></html>" },
    { id = 5, dict_id = "zz", word = "kamma", word_fuzzy = "kama", html = "<p>deed</p>" },
}

local function fake()
    local db = { queries = {}, params = {} }
    function db:query(sql, p)
        self.queries[#self.queries + 1] = sql
        self.params[#self.params + 1] = p
        if sql:find("SELECT 1 FROM dict_meta", 1, true) then return self.empty and {} or { { 1 } } end
        if sql:find("FROM dict_meta", 1, true) then
            local rows = { { dict_id = "mw", name = "MW", author = "Monier-Williams", entry_count = 1 },
                { dict_id = "cpd", name = "CPD", author = "Trenckner", entry_count = 1 },
                { dict_id = "dppn", name = "DPPN", author = "Malalasekera", entry_count = 1 },
                { dict_id = "nyanatiloka", name = "Nyanatiloka", entry_count = 1 } }
            for _, row in ipairs(self.extra or {}) do rows[#rows + 1] = row end
            return rows
        end
        local out = {}
        if sql:find("WHERE id = ?", 1, true) then
            for _, e in ipairs(entries) do
                if e.id == p[3] then
                    out[1] = { dict_id = e.dict_id, total = #e.html, chunk = e.html:sub(p[1], p[1] + p[2] - 1) }
                end
            end
            return out
        end
        assert(sql:find("WHERE dict_id = ? AND ", 1, true), "every entry query binds dict_id: " .. sql)
        local column = sql:find("word_fuzzy = ?", 1, true) and "word_fuzzy" or "word"
        local matches = {}
        for _, e in ipairs(entries) do
            if e.dict_id == p[1] and e[column] == p[2] then matches[#matches + 1] = { id = e.id, word = e.word, head = e.html } end
        end
        if sql:find("count(*)", 1, true) then return { { n = #matches } } end
        for i = (p[4] or 0) + 1, math.min(#matches, (p[4] or 0) + p[3]) do out[#out + 1] = matches[i] end
        return out
    end
    return db
end

describe("other dictionaries", function()
    it("distinguishes failed metadata reads from an absent feature and allows retry", function()
        local db = fake()
        local query = db.query
        function db:query() error("database disk image is malformed") end
        local reader = Dictionaries.new(db)
        local lookup = setmetatable({dictionaries=reader}, {__index=require("dpd/lookup")})
        local ready, err = lookup:hasOtherDictionaries()
        assert.is_nil(ready)
        assert.matches("could not read the other dictionaries", err, 1, true)
        assert.has_error(function() reader:lookup({"kamma"}) end)
        db.query = query
        assert.is_true(lookup:hasOtherDictionaries())
        function db:query() error("no such table: dict_meta") end
        assert.is_false(Dictionaries.new(db):available())
    end)
    it("lists the database's dictionaries, known ones in a fixed order and others after them by name", function()
        local ids = {}
        for _, d in ipairs(Dictionaries.new(fake()):list()) do ids[#ids + 1] = d.id end
        assert.same({ "dppn", "cpd", "nyanatiloka", "mw" }, ids)
        local db = fake()
        db.extra = { { dict_id = "zz", name = "Zed", entry_count = 1 }, { dict_id = "aa", name = "Alpha", entry_count = 1 } }
        local reader = Dictionaries.new(db)
        ids = {}
        for _, d in ipairs(reader:list()) do ids[#ids + 1] = d.id end
        assert.same({ "dppn", "cpd", "nyanatiloka", "mw", "aa", "zz" }, ids)
        -- Read once per database.
        local reads = #db.queries
        reader:list()
        assert.equal(reads, #db.queries)
    end)

    it("turns on every dictionary but PEU, the Sanskrit ones and WordNet, including new ones", function()
        assert.same({ "dppn", "cpd", "pts", "nyanatiloka" }, Dictionaries.enabled(Dictionaries.order))
        assert.same({ "new" }, Dictionaries.enabled({ "new", "mw" }))
        assert.same({ "mw" }, Dictionaries.enabled({ "new", "mw" }, { "new" }))
        local db = fake()
        db.extra = { { dict_id = "zz", name = "Zed", entry_count = 1 } }
        local ids = {}
        for _, group in ipairs(Dictionaries.new(db):lookup({ "kamma" })) do ids[#ids + 1] = group.id end
        assert.same({ "cpd", "nyanatiloka", "zz" }, ids)
    end)

    it("migrates every public snapshot dictionary choice, including PTS and an empty selection", function()
        local settings = { dictionaries = { "mw" } }
        Dictionaries.convertSettings(settings)
        assert.is_nil(settings.dictionaries)
        assert.same({ "dppn", "cpd", "pts", "nyanatiloka", "peu", "bhs", "apte", "wordnet" },
            settings.dictionaries_off)
        assert.same({ "mw" }, Dictionaries.enabled(Dictionaries.order, settings.dictionaries_off))
        settings = { dictionaries = {} }
        Dictionaries.convertSettings(settings)
        assert.same(Dictionaries.order, settings.dictionaries_off)
        assert.same({}, Dictionaries.enabled(Dictionaries.order, settings.dictionaries_off))
    end)

    it("keeps existing disabled settings and leaves new installations unchanged", function()
        for _, off in ipairs({ {}, { "pts" } }) do
            local settings = { dictionaries = { "mw" }, dictionaries_off = off }
            Dictionaries.convertSettings(settings)
            assert.is_nil(settings.dictionaries)
            assert.equal(off, settings.dictionaries_off)
            Dictionaries.convertSettings(settings)
            assert.equal(off, settings.dictionaries_off)
        end
        local settings = {}
        Dictionaries.convertSettings(settings)
        assert.same({}, settings)
    end)

    it("finds keys as is, then capitalized, binding dict_id in every query", function()
        local db = fake()
        local groups = Dictionaries.new(db):lookup({ "sāriputta", "kamma", "kamma" })
        assert.equal("dppn", groups[1].id)
        assert.equal("Sāriputta", groups[1].entries[1].word)
        assert.equal("01. Chief disciple.", groups[1].entries[1].preview)
        assert.equal("cpd", groups[2].id)
        assert.equal("nyanatiloka", groups[3].id)
        assert.equal("action", groups[3].entries[1].preview)
        for i, sql in ipairs(db.queries) do
            if sql:find("dict_entries", 1, true) and not sql:find("PRAGMA", 1, true) then
                assert.truthy(sql:find("dict_id = ?", 1, true) or sql:find("WHERE id = ?", 1, true))
            end
        end
    end)

    it("reads entries 20 at a time, in key order, until all are listed", function()
        local before = #entries
        for i = 1, 47 do entries[#entries + 1] = { id = 100 + i, dict_id = "dppn", word = "Tissa", word_fuzzy = "tisa", html = "<p>" .. i .. "</p>" } end
        entries[#entries + 1] = { id = 99, dict_id = "dppn", word = "Tissā", word_fuzzy = "tisa", html = "<p>f</p>" }
        local d = Dictionaries.new(fake())
        local group = d:lookup({ "tissa", "tissā" }, { "dppn" })[1]
        assert.equal(48, group.total)
        assert.equal(20, #group.entries)
        assert.equal(20, d:more(group))
        assert.equal(8, d:more(group))
        assert.equal(48, #group.entries)
        assert.equal(147, group.entries[47].id)
        assert.equal("Tissā", group.entries[48].word)
        assert.equal(0, d:more(group))
        for i = #entries, before + 1, -1 do entries[i] = nil end
    end)

    it("starts previews after the headword, keeping its homonym number, without Burmese script", function()
        local rows = {
            { dict_id = "cpd", word = "kamma", head = "<article><sup>3</sup><h2><b>kamma</b></h2>, <i>n., act</i></article>" },
            { dict_id = "mw", word = "kāya", head = "<p><strong>(H1)</strong> <span>[Printed book page <a>274.1</a>]</span>"
                .. " 1. kāya mf(ī)n. body</p>" },
            { dict_id = "bhs", word = "kāya", head = "<b>kāya</b>, normally m." },
            { dict_id = "dppn", word = "Tissa", head = "<p><span class=\"Head\"> 01. </span>A monk.</p>" },
            { dict_id = "peu", word = "dhamma", head = "(pu,na) CL=0 \225\128\128\225\128\133 \225\128\138. 531. Doctrine." },
            { dict_id = "nyanatiloka", word = "kamma", head = "<p>kammaṭṭhāna is another word</p>" },
            { dict_id = "pts", word = "sattha", head = "<p><sup>2</sup> (neuter) [<i>cf.</i> Vedic <i>śāstra</i>] a science</p>" },
        }
        local db = {}
        function db:query(sql, p)
            if sql:find("SELECT 1 FROM dict_meta", 1, true) then return { { 1 } } end
            if sql:find("FROM dict_meta", 1, true) then
                local out = {}
                for _, r in ipairs(rows) do out[#out + 1] = { dict_id = r.dict_id, name = r.dict_id, entry_count = 1 } end
                return out
            end
            for i, r in ipairs(rows) do
                if r.dict_id == p[1] and r.word == p[2] then
                    if sql:find("count(*)", 1, true) then return { { n = 1 } } end
                    return { { id = i, word = r.word, head = r.head } }
                end
            end
            return sql:find("count(*)", 1, true) and { { n = 0 } } or {}
        end
        local found = {}
        for _, group in ipairs(Dictionaries.new(db):lookup({ "kamma", "kāya", "tissa", "dhamma", "sattha" },
            { "cpd", "mw", "bhs", "dppn", "peu", "nyanatiloka", "pts" })) do
            found[group.id] = group.entries[1]
            assert.equal(Dictionaries.headings[group.id], group.heading)
        end
        assert.equal("n., act", found.cpd.preview)
        assert.equal("3", found.cpd.homonym)
        assert.equal("mf(ī)n. body", found.mw.preview)
        assert.equal("1", found.mw.homonym)
        assert.equal("normally m.", found.bhs.preview)
        assert.is_nil(found.bhs.homonym)
        -- A number that is not followed by the headword stays in the preview.
        assert.equal("01. A monk.", found.dppn.preview)
        assert.equal("(pu,na) CL=0 531. Doctrine.", found.peu.preview)
        -- Only the whole word is the headword.
        assert.equal("kammaṭṭhāna is another word", found.nyanatiloka.preview)
        -- PTS numbers a homonym without repeating the headword.
        assert.equal("(neuter) [cf. Vedic śāstra] a science", found.pts.preview)
        assert.equal("2", found.pts.homonym)
    end)

    it("heads each dictionary with a compact name and its count on one line", function()
        local groups = { { id = "bhs", heading = Dictionaries.headings.bhs, name = "Edgerton's Buddhist Hybrid Sanskrit Dictionary 1953",
            author = "Franklin Edgerton", total = 1, entries = { { id = 1, word = "kāya", homonym = "2", preview = "normally m." } } } }
        local view = Render.render({ query = "kāya", dictionaries = { keys = { "kāya" }, groups = groups } }, { analyses = {} })
        assert.truthy(view:find('<p class="section">Edgerton · Buddhist Hybrid Sanskrit <span class="count">·&nbsp;1&nbsp;entry</span></p>', 1, true))
        assert.is_nil(view:find("1953", 1, true))
        assert.is_nil(view:find("Franklin", 1, true))
        assert.truthy(view:find("<b>kāya</b><sup>2</sup> · normally m.", 1, true))
        -- The searched forms are named only when they differ from the title.
        assert.truthy(view:find('<p class="header">Other dictionaries</p>', 1, true))
        view = Render.render({ query = "kāye", dictionaries = { keys = { "kāya", "kāyati" }, groups = groups } }, { analyses = {} })
        assert.truthy(view:find('<p class="header">Other dictionaries · kāya, kāyati</p>', 1, true))
    end)

    it("is unavailable when the release leaves the tables empty", function()
        local db = fake(); db.empty = true
        local d = Dictionaries.new(db)
        assert.is_false(d:available())
        assert.same({}, d:lookup({ "kamma" }))
        assert.same({}, d:list())
    end)

    it("falls back to a few folded matches, marked approximate, only without exact hits", function()
        local groups = Dictionaries.new(fake()):lookup({ "kammā" }, { "cpd" })
        assert.is_true(groups[1].entries[1].approximate)
        assert.is_false(Dictionaries.new(fake()):lookup({ "kamma" }, { "cpd" })[1].entries[1].approximate)
    end)

    it("lists dictionaries with exact entries before approximate-only ones", function()
        -- kammā is only approximate in CPD and Nyanatiloka; karman is exact in MW.
        local groups = Dictionaries.new(fake()):lookup({ "kammā", "karman" }, { "cpd", "nyanatiloka", "mw" })
        local ids = {}
        for _, group in ipairs(groups) do ids[#ids + 1] = group.id end
        assert.same({ "mw", "cpd", "nyanatiloka" }, ids)
        assert.is_false(groups[1].entries[1].approximate)
        assert.is_true(groups[2].entries[1].approximate)
    end)

    it("keeps printed-page citations muted and drops MW/Apte headword levels", function()
        -- Official mobile v0.4.20260926 openings.
        local mw = '<body><p><strong>(H1)</strong> <span class="pcol-ref">[Printed book page <a href="https://www.sanskrit-lexicon.uni-koeln.de/scans/csl-apidev/servepdf.php?dict=MW&page=1">1</a>.1]</span><br/>\n'
            .. '<span class="hom" title="Homonym">1.</span> <span class="sdata">a</span></p></body>'
        assert.equal('<p><span class="src">[Printed book page 1.1]</span><br>\n1. <i>a</i></p>', Dictionaries.sanitize(mw, "mw"))
        local apte = '<p><strong>(H2A)</strong> <span class="pcol-ref">[Printed book page <a href="x">0220-1</a>.]</span><br/>x <strong>(C1)</strong> y</p>'
        assert.equal('<p><span class="src">[Printed book page 0220-1.]</span><br>x y</p>', Dictionaries.sanitize(apte, "apte"))
        -- Only MW and Apte use the markers; elsewhere such text is content.
        assert.equal("<p><b>(H1)</b> x</p>", Dictionaries.sanitize("<p><strong>(H1)</strong> x</p>", "cpd"))
        assert.equal('<b><span class="src">[vol 2, p. XVI]</span> Ludwig Alsdorf</b>',
            Dictionaries.sanitize('<h2><span class="page">[vol 2, p. XVI]</span> Ludwig Alsdorf</h2>', "cpd"))
        assert.equal("<p>x</p>", Dictionaries.sanitize('<section class="intro-page"><p>x</p></section>', "cpd"))
    end)

    it("sanitizes to the popup's markup", function()
        assert.equal("<p>Chief <b>disciple</b>.</p>", Dictionaries.sanitize('<p style="color:red"><span class="Head">Chief</span> <b>disciple</b>.</p>'))
        assert.equal("<i>karman</i> scan", Dictionaries.sanitize(entries[4].html:gsub("<p>", ""):gsub("</p>", ""), "mw"):gsub("^%s*", ""))
        assert.equal("x", Dictionaries.sanitize('<script>alert(1)</script><style>p{}</style>x'))
        assert.equal("<b>kamma</b>, <i>n.</i> working deed", Dictionaries.sanitize(entries[2].html, "cpd"))
        -- Unbalanced input comes out balanced; stray closing tags go.
        assert.equal("<p><b>a</b></p>", Dictionaries.sanitize("<p><b>a</p></i>"))
        assert.equal("<table><tr><td>x</td></tr></table>", Dictionaries.sanitize("<td>x</td>"))
        assert.equal('<table><tr><td rowspan="2"><b>PRESENT</b></td><td colspan="3">x</td><th>y</th></tr></table>',
            Dictionaries.sanitize('<table border="1"><tr><td ROWSPAN=2 valign="middle" width="83"><strong>PRESENT</strong></td>'
                .. "<td colspan='3' style='x'>x</td><th rowspan=\"1\" colspan=\"999\">y</th></tr></table>"))
    end)

    -- A list preview of one article, through the dictionary reader.
    local function previewOf(dict_id, word, head, longer)
        local db, reads = {}, 0
        function db:query(sql, p)
            if sql:find("WHERE id = ?", 1, true) then
                reads = reads + 1
                return longer and { { head = longer } } or {}
            end
            if sql:find("SELECT 1 FROM dict_meta", 1, true) then return { { 1 } } end
            if sql:find("FROM dict_meta", 1, true) then return { { dict_id = dict_id, name = dict_id, entry_count = 1 } } end
            if p[2] ~= word then return sql:find("count(*)", 1, true) and { { n = 0 } } or {} end
            if sql:find("count(*)", 1, true) then return { { n = 1 } } end
            return { { id = 1, word = word, head = head } }
        end
        return Dictionaries.new(db):lookup({ word }, { dict_id })[1].entries[1].preview, reads
    end

    -- Apte eḍukaḥ (580816): a ">" inside a quoted note is not the tag's end.
    local eduka = '<chg type="chg" note="change \'or\' to comma; also equ->equkaH"><old>x</old>'
        .. '<new><span class="sdata">eḍu</span>kaḥ</new></chg> A building'

    it("keeps a quoted '>' inside its tag in articles and previews", function()
        assert.equal("<i>eḍu</i>kaḥ A building", Dictionaries.sanitize(eduka, "apte"))
        assert.is_nil(previewOf("apte", "eḍukaḥ", eduka):find("equkaH", 1, true))
        -- A chunk that ends inside a quoted value shows none of it.
        assert.equal("a", previewOf("apte", "w", 'a <chg note="equ->eq'))
        -- Real articles open with a declaration (and CPD's with <?xml?>), not tags.
        assert.equal("x", previewOf("mw", "w", '<!DOCTYPE html><html><head><meta charset="utf-8"></head>'
            .. "<body><!-- c --><p><strong>(H3)</strong> x</p>"))
        assert.equal("x", previewOf("cpd", "w", "<?xml version='1.0'?><article>x</article>"))
        -- An unquoted ">" and a stray apostrophe still end tags as before.
        assert.equal("<b>it's</b> x", Dictionaries.sanitize("<b class=it's>it's</b> x"))
    end)

    it("previews an amendment's current reading, as the article shows it", function()
        -- MW abdhitanaya (354398).
        local mw = '<chg type="chg" n="1" src="mw"><old>the <span class="dotunder" title="">Aśvin</span>s</old>'
            .. '<new>the two <span class="dotunder" title="">Aśvin</span>s</new></chg>, Kathās.'
        assert.equal("the two Aśvins, Kathās.", previewOf("mw", "x", mw))
        assert.equal("the two Aśvins, Kathās.", (Dictionaries.sanitize(mw, "mw"):gsub("<[^>]+>", "")))
        -- A chunk cut inside the old reading shows neither half of it.
        assert.equal("m. du.", previewOf("mw", "x", "m. du. <chg><old>the Aś"))
        -- Nor a record ID or entity the chunk ends inside (Apte 571347, 597754).
        assert.equal("a grown-up girl.", previewOf("apte", "x", 'a grown-up girl. <span class="record-id">[ID=609'))
        assert.equal("Excellence", previewOf("apte", "x", "Excellence &a"))
        assert.equal("A building", previewOf("apte", "eḍukaḥ", eduka), "after the headword, as usual")
    end)

    it("keeps escaped punctuation in previews, decoded once", function()
        -- WordNet angle bracket (4032), 13 (54); CPD adveḷhaka (315745).
        assert.equal("either of two punctuation marks (‘<’ or ‘>’)",
            previewOf("wordnet", "x", "<li>either of two punctuation marks (‘&lt;’ or ‘&gt;’)</li>"))
        assert.equal("thirteen, baker's dozen", previewOf("wordnet", "x", "thirteen, baker&#x27;s dozen"))
        assert.equal("dveḷhaka < *dvahihaka", previewOf("cpd", "x", "dveḷhaka &lt;<br/>\n*dvahihaka"))
        assert.equal('a "b" c d', previewOf("peu", "x", "a &quot;b&quot;&#10;c&nbsp;d"))
        -- An escaped entity stays the text of an entity; an escaped tag is not a tag.
        assert.equal("&lt; and &amp;", previewOf("apte", "x", "&amp;lt; and &amp;amp;"))
        assert.equal("<b>", previewOf("apte", "x", "&lt;b&gt;"))
        -- Unknown entities are dropped, as before.
        assert.equal("a b", previewOf("apte", "x", "a &bogus; b"))
    end)

    it("reads further when the chunk holds no current text", function()
        -- Apte eḍukaḥ (580816): the 600-byte chunk ends inside the old reading.
        local opening = '<p><chg><old>' .. string.rep("old reading ", 60)
        assert.equal(600, #opening:sub(1, 600))
        local article = opening .. '</old><new>eḍu(ḍū,ḍo)kaḥ</new></chg>, A building constructed of rubbish</p>'
        local text, reads = previewOf("apte", "x", opening:sub(1, 600), article)
        assert.equal("eḍu(ḍū,ḍo)kaḥ, A building constructed of rubbish", text)
        assert.equal(1, reads)
        -- Only an empty preview of a full chunk reads further.
        assert.equal(0, select(2, previewOf("apte", "x", "a", article)))
        assert.equal(0, select(2, previewOf("apte", "x", string.rep("word ", 120), article)))
        assert.equal(0, select(2, previewOf("dppn", "x", "<p> </p>", article)))
        assert.equal("", (previewOf("apte", "x", opening:sub(1, 600))))
    end)

    it("drops a character the preview's byte limit split", function()
        -- Apte ākūtiḥ (576877): the chunk ends on the first byte of ā.
        assert.equal("ca cittīn…", previewOf("apte", "x", "ca cittīn\196"))
        assert.equal("ā", previewOf("apte", "x", "ā"))
        assert.equal("ab…", previewOf("apte", "x", "ab\225\184"), "two of three bytes")
    end)

    it("pages a long article at structural boundaries, never whole", function()
        local parts = {}
        for i = 1, 1000 do parts[i] = "<p>paragraph number " .. i .. " with some text</p>" end
        entries[5] = { id = 5, dict_id = "cpd", word = "a", word_fuzzy = "a", html = table.concat(parts) }
        local d = Dictionaries.new(fake())
        local offset, pages = 0, 0
        repeat
            local page = d:page(5, offset)
            pages = pages + 1
            assert.is_true(#page.html <= Dictionaries.article_page * 1.5)
            assert.truthy(page.html:match("^<p>") and page.html:match("</p>$"), "cut after a paragraph")
            offset = page.next_offset
        until not page.has_more
        assert.equal(#entries[5].html, offset)
        assert.is_true(pages > 1)
        entries[5] = nil
    end)

    it("pages unbroken text between characters", function()
        -- No tag or space to cut at: the byte limit falls inside ā (C4 81).
        local size = math.floor(Dictionaries.article_page * 1.5)
        entries[5] = { id = 5, dict_id = "cpd", word = "a", word_fuzzy = "a",
            html = string.rep("x", size - 1) .. "ā" .. string.rep("x", 10) }
        local d = Dictionaries.new(fake())
        local first = d:page(5, 0)
        assert.equal(size - 1, first.next_offset)
        assert.is_true(first.has_more)
        local second = d:page(5, first.next_offset)
        assert.equal("ā" .. string.rep("x", 10), second.html)
        assert.is_false(second.has_more)
        entries[5] = nil
    end)

    it("cuts tag-free windows without repeated suffix searches", function()
        local started = os.clock()
        assert.is_nil(Dictionaries.cut(string.rep("x", 24000), 24000))
        assert.equal(24000, Dictionaries.cut(string.rep("x ", 12000), 24000))
        assert.is_true(os.clock() - started < 0.1, "24 KB tag-free cuts must take less than 100 ms")
    end)

    it("never cuts inside a comment or a tag", function()
        local chunk = string.rep("x ", 20) .. "<p>a</p><!-- <p>b</p> --> <span class=\"y z\">"
        local cut = Dictionaries.cut(chunk, #chunk)
        assert.equal(#(string.rep("x ", 20) .. "<p>a</p>"), cut)
    end)

    it("leaves the button to the viewer's row, offered for results only, and lists entries collapsed", function()
        local value = { query = "kamma", senses = {}, found = true, deconstructions = {}, roots = {} }
        local result = Render.render(value, { analyses = {}, other_dictionaries = true })
        assert.is_nil(result:find("dpd:dictionaries", 1, true))
        assert.is_true(Render.isResult(value))
        local groups = Dictionaries.new(fake()):lookup({ "kamma" })
        local view = Render.render({ query = "kamma", dictionaries = { keys = { "kamma" }, groups = groups } },
            { analyses = {}, other_dictionaries = true })
        assert.truthy(view:find("dpd:dict-entry/1/1", 1, true))
        assert.is_nil(view:find("dpd:dictionaries", 1, true))
        assert.is_false(Render.isResult({ dictionaries = {} }))
        assert.is_nil(view:find('class="article"', 1, true))
    end)

    it("renders one article part with its controls, more entries, and unsearched forms", function()
        local groups = { { id = "dppn", name = "DPPN", total = 47,
            entries = { { id = 1, word = "Tissa" }, { id = 2, word = "Tissa" } } } }
        local value = { query = "tissa", dictionaries = { keys = { "tissa" }, omitted = 2, groups = groups } }
        local state = { analyses = {}, dictionary_pages = { ["1/2"] = { open = true, html = "<p>part two</p>",
            part = 2, offset = 16000, next_offset = 32000, total = 64000, has_more = true } } }
        local view = Render.render(value, state)
        assert.truthy(view:find("<p>part two</p>", 1, true))
        assert.truthy(view:find("dpd:dict-prev/1/2", 1, true))
        assert.truthy(view:find("dpd:dict-next/1/2", 1, true))
        assert.truthy(view:find('<p class="header">Part 2</p>', 1, true))
        assert.is_nil(view:find("50%", 1, true))
        local _, previous = view:gsub('href="dpd:dict%-prev/1/2"', "")
        local _, next_part = view:gsub('href="dpd:dict%-next/1/2"', "")
        -- Previous part above and below the article; Next part only below it.
        assert.equal(2, previous)
        assert.equal(1, next_part)
        assert.truthy(view:find("dpd:dict-next/1/2", 1, true) > view:find("<p>part two</p>", 1, true))
        assert.truthy(view:find('<table class="actions"', 1, true))
        assert.truthy(view:find("dpd:dict-entries/1", 1, true))
        assert.truthy(view:find("47&nbsp;entries · 2&nbsp;shown", 1, true))
        assert.truthy(view:find("2 more Pāḷi forms of this result not searched by spelling.", 1, true))
        groups[1].total = 2
        state.dictionary_pages["1/2"] = { open = true, html = "<p>x</p>", part = 1, offset = 0, next_offset = 9, total = 9 }
        view = Render.render(value, state)
        assert.truthy(view:find("2&nbsp;entries", 1, true))
        -- An article in one part has no part label.
        assert.is_nil(view:find("Part 1", 1, true))
        assert.is_nil(view:find("100%", 1, true))
        assert.is_nil(view:find("dpd:dict-entries/", 1, true))
        assert.is_nil(view:find("dpd:dict-prev/", 1, true))
        assert.is_nil(view:find("dpd:dict-next/", 1, true))
        groups[1].entries[1].approximate = true
        view = Render.render(value, state)
        assert.truthy(view:find("2&nbsp;approximate · limited&nbsp;search", 1, true))
        assert.is_nil(view:find("2&nbsp;entries", 1, true))
    end)

    it("labels multipart articles without estimating progress or a total", function()
        local value = { query = "kamma", dictionaries = { groups = {
            { id = "cpd", entries = { { id = 1, word = "kamma" } } },
        } } }
        for _, case in ipairs({
            { part = 1, has_more = true, label = "Part 1" },
            { part = 2, has_more = true, label = "Part 2" },
            { part = 3, has_more = false, label = "Part 3 · last part" },
            { part = 1, has_more = false },
        }) do
            local page = { open = true, html = "<p>article</p>", part = case.part,
                has_more = case.has_more, next_offset = 32000, total = 64000 }
            local view = Render.render(value, { analyses = {}, dictionary_pages = { ["1/1"] = page } })
            if case.label then
                assert.truthy(view:find('<p class="header">' .. case.label .. '</p>', 1, true))
            else
                assert.is_nil(view:find('<p class="header">Part ', 1, true))
            end
            assert.is_nil(view:find("50%", 1, true))
        end
    end)

    -- Fields as DPD v0.4.20260926 writes them.
    it("takes plain Sanskrit words from DPD's field, never parts of an analysis", function()
        assert.same({"viṣṇu"}, Dictionaries.sanskritWords("Viṣṇu"))
        assert.same({"viṣṇu"}, Dictionaries.sanskritWords("VIṢṆU"))
        assert.same({}, Dictionaries.sanskritWords("viṣ ṇu"))
        assert.same({ "dharma" }, Dictionaries.sanskritWords("dharma [dhṛ]"))
        assert.same({ "akathya", "akathanīya", "akathanārha" },
            Dictionaries.sanskritWords("akathya, akathanīya , akathanārha [kath]"))
        assert.same({ "akṛtajña" }, Dictionaries.sanskritWords("akṛtajña (na + kṛtajña)"))
        assert.same({ "aṭavī" }, Dictionaries.sanskritWords("aṭavī (bsk)"))
        assert.same({}, Dictionaries.sanskritWords("atyaya + sūkta, sūtra (bsk)"))
        assert.same({}, Dictionaries.sanskritWords("agnihotra + miśra?"))
        assert.same({}, Dictionaries.sanskritWords("a [praṇidhā]"))
        assert.same({}, Dictionaries.sanskritWords("[arh]"))
        assert.same({}, Dictionaries.sanskritWords(nil))
    end)

    describe("Sanskrit equivalents", function()
        -- dhamma has no entry of that spelling in the Sanskrit dictionaries.
        local rows = {
            { id = 10, dict_id = "mw", word = "ḍama", word_fuzzy = "dama" },
            { id = 11, dict_id = "mw", word = "dharma", word_fuzzy = "dharma" },
            { id = 20, dict_id = "apte", word = "dharmaḥ", word_fuzzy = "dharmah" },
            { id = 30, dict_id = "bhs", word = "dāma", word_fuzzy = "dama" },
            { id = 31, dict_id = "bhs", word = "dharma", word_fuzzy = "dharma" },
            { id = 40, dict_id = "mw", word = "kamma", word_fuzzy = "kama" },
            { id = 50, dict_id = "mw", word = "viṣṇu", word_fuzzy = "visnu" },
            { id = 51, dict_id = "apte", word = "viṣṇuḥ", word_fuzzy = "visnuh" },
            { id = 52, dict_id = "bhs", word = "viṣṇu", word_fuzzy = "visnu" },
        }
        local function sanskritDb(without)
            local db = {}
            function db:query(sql, p)
                if sql:find("SELECT 1 FROM dict_meta", 1, true) then return { { 1 } } end
                if sql:find("FROM dict_meta", 1, true) then
                    return { { dict_id = "bhs", name = "BHS" }, { dict_id = "mw", name = "MW" },
                        { dict_id = "apte", name = "Apte" }, { dict_id = "cpd", name = "CPD" } }
                end
                local column = sql:find("word_fuzzy = ?", 1, true) and "word_fuzzy" or "word"
                local matches = {}
                for _, r in ipairs(rows) do
                    if r.dict_id == p[1] and r[column] == p[2] and not (without and without[r.id]) then
                        matches[#matches + 1] = { id = r.id, word = r.word, head = "<p>" .. r.word .. "</p>" }
                    end
                end
                if sql:find("count(*)", 1, true) then return { { n = #matches } } end
                return matches
            end
            return Dictionaries.new(db)
        end
        local function byId(groups)
            local out = {}
            for _, g in ipairs(groups) do out[g.id] = g end
            return out
        end
        local all = { "bhs", "mw", "apte", "cpd" }
        it("offers bissanu's capitalized Sanskrit equivalent through the full lookup path", function()
            local reader = sanskritDb()
            function reader.db:sanskrit() return {{id=7,sanskrit="Viṣṇu"}} end
            local lookup = setmetatable({db=reader.db,dictionaries=reader}, {__index=require("dpd/lookup")})
            local result = lookup:otherDictionaries({query="bissanu",senses={{id=7,lemma_1="bissanu"}}}, all)
            local groups = byId(result.dictionaries.groups)
            assert.equal("viṣṇu",groups.mw.entries[1].word)
            assert.equal("viṣṇuḥ",groups.apte.entries[1].word)
            assert.equal("viṣṇu",groups.bhs.entries[1].word)
            assert.same({"viṣṇu"},groups.mw.via)
        end)

        it("are looked up in MW and Apte before near spellings, and named", function()
            local groups = byId(sanskritDb():lookup({ "dhamma" }, all, { "dharma" }))
            assert.equal("dharma", groups.mw.entries[1].word)
            assert.is_false(groups.mw.entries[1].approximate)
            assert.equal(1, #groups.mw.entries)
            assert.same({ "dharma" }, groups.mw.via)
            -- Apte lists nouns in the nominative.
            assert.equal("dharmaḥ", groups.apte.entries[1].word)
            assert.same({ "dharma" }, groups.apte.via)
            assert.is_nil(groups.cpd)
        end)

        it("only fill an empty Edgerton section, whose near spellings may be hybrid forms", function()
            local groups = byId(sanskritDb():lookup({ "dhamma" }, all, { "dharma" }))
            assert.equal("dāma", groups.bhs.entries[1].word)
            assert.is_true(groups.bhs.entries[1].approximate)
            assert.is_nil(groups.bhs.via)
            groups = byId(sanskritDb({ [30] = true }):lookup({ "dhamma" }, all, { "dharma" }))
            assert.equal("dharma", groups.bhs.entries[1].word)
            assert.same({ "dharma" }, groups.bhs.via)
        end)

        it("never replace an exact match of the Pāḷi spelling, and change nothing when absent", function()
            local groups = byId(sanskritDb():lookup({ "kamma" }, all, { "karman" }))
            assert.equal("kamma", groups.mw.entries[1].word)
            assert.is_nil(groups.mw.via)
            groups = byId(sanskritDb():lookup({ "dhamma" }, all))
            assert.equal("ḍama", groups.mw.entries[1].word)
            assert.is_true(groups.mw.entries[1].approximate)
            groups = byId(sanskritDb():lookup({ "dhamma" }, all, { "nothing" }))
            assert.is_true(groups.mw.entries[1].approximate)
        end)

        it("head their group with the Sanskrit word", function()
            local groups = sanskritDb():lookup({ "dhamma" }, { "mw" }, { "dharma" })
            local view = Render.render({ query = "dhamma", dictionaries = { keys = { "dhamma" }, groups = groups } },
                { analyses = {} })
            assert.truthy(view:find("1&nbsp;entry · via Sanskrit&nbsp;dharma", 1, true))
            assert.is_nil(view:find("≈", 1, true))
        end)
    end)
end)

describe("searching the other dictionaries", function()
    local Lookup = require("dpd/lookup")
    local rows = {
        { dict_id = "dppn", word = "Mahā Bodhi", fuzzy = "mahabodi" },
        { dict_id = "dppn", word = "Mahā Bodhi", fuzzy = "mahabodi" },
        { dict_id = "dppn", word = "Mahā Bodhi", fuzzy = "mahabodi" },
        { dict_id = "dppn", word = "Mahā bodhi tree", fuzzy = "mahabodi" },
        { dict_id = "cpd", word = "saṃsāra", fuzzy = "samsara" },
        { dict_id = "bhs", word = "śāriputra", fuzzy = "sariputra" },
        { dict_id = "mw", word = "śāriputra", fuzzy = "sariputra" },
        { dict_id = "mw", word = "dharma", fuzzy = "darma" },
        { dict_id = "mw", word = "ātman", fuzzy = "atman" },
        { dict_id = "apte", word = "dharmaḥ", fuzzy = "darmah" },
        { dict_id = "apte", word = "ātman", fuzzy = "atman" },
        { dict_id = "dppn", word = "Accayasutta (Akodhanasutta)", fuzzy = "acayasuta(akodanasuta)" },
        { dict_id = "wordnet", word = "e.g.", fuzzy = "e.g." },
        { dict_id = "wordnet", word = "no.", fuzzy = "no." },
        { dict_id = "wordnet", word = "no", fuzzy = "no" },
        { dict_id = "cpd", word = "dhamma", fuzzy = "dama" },
        { dict_id = "mw", word = "phala", fuzzy = "pala" },
        { dict_id = "apte", word = "phalaṃ", fuzzy = "palam" },
        { dict_id = "apte", word = "palaḥ", fuzzy = "pala" },
        { dict_id = "mw", word = "ḹ", fuzzy = "l" },
        { dict_id = "wordnet", word = "vacuum", fuzzy = "vacuum" },
        { dict_id = "mw", word = "rāma", fuzzy = "rama" },
        { dict_id = "mw", word = "raama", fuzzy = "rama" },
    }
    local all = { "dppn", "cpd", "bhs", "mw", "apte", "wordnet" }
    local db
    local function search(text, enabled, draft)
        db = { queries = {} }
        function db:query(sql, p)
            self.queries[#self.queries + 1] = { sql = sql, p = p }
            if sql:find("SELECT 1 FROM dict_meta", 1, true) then return { { 1 } } end
            if sql:find("FROM dict_meta", 1, true) then
                local out = {}
                for _, id in ipairs(all) do out[#out + 1] = { dict_id = id, name = id, entry_count = 1 } end
                return out
            end
            local column = sql:find("word_fuzzy = ?", 1, true) and "fuzzy" or "word"
            local matches = {}
            for i, r in ipairs(rows) do
                if r.dict_id == p[1] and r[column] == p[2] then
                    matches[#matches + 1] = { id = i, word = r.word, head = "<p>" .. r.word .. "</p>" }
                end
            end
            if sql:find("count(*)", 1, true) then return { { n = #matches } } end
            return matches
        end
        local lookup = setmetatable({ dictionaries = Dictionaries.new(db) }, { __index = Lookup })
        return lookup:searchDictionaries(text, enabled or all, draft)
    end
    local function searched()
        local keys = {}
        for _, q in ipairs(db.queries) do
            if q.sql:find("count(*)", 1, true) and q.p[1] == "mw" then keys[#keys + 1] = q.p[2] end
        end
        return keys
    end
    local function group(model, id)
        for _, g in ipairs(model.dictionaries.groups) do if g.id == id then return g end end
    end

    it("finds a name exactly as typed, capitals and all", function()
        local model = search("Mahā Bodhi")
        local dppn = group(model, "dppn")
        assert.equal(3, dppn.total)
        assert.is_falsy(dppn.entries[1].approximate)
        assert.is_true(model.found and model.dictionary_search)
        assert.same({ "Mahā Bodhi" }, model.dictionaries.keys)
    end)

    it("tries the text as typed where Velthuis input found nothing", function()
        -- vacuum converts to vacūm, which WordNet lacks.
        local model = search("vacūm", nil, "vacuum")
        assert.equal("vacuum", group(model, "wordnet").entries[1].word)
        assert.same({ "vacūm" }, model.dictionaries.keys)
        -- Where the converted text is found, the typed text is not added.
        local words = {}
        for _, entry in ipairs(group(search("rāma", nil, "raama"), "mw").entries) do words[#words + 1] = entry.word end
        assert.same({ "rāma" }, words)
    end)

    it("keeps typed punctuation that is part of a headword", function()
        local sutta = search("Accayasutta (Akodhanasutta)")
        assert.equal("Accayasutta (Akodhanasutta)", group(sutta, "dppn").entries[1].word)
        assert.is_falsy(group(sutta, "dppn").entries[1].approximate)
        local eg = search("e.g.")
        assert.equal("e.g.", eg.query)
        assert.equal("e.g.", group(eg, "wordnet").entries[1].word)
        -- The literal word comes first; the cleaned one is a separate, labelled headword.
        local words = {}
        for _, entry in ipairs(group(search("no."), "wordnet").entries) do words[#words + 1] = entry.word end
        assert.same({ "no.", "no" }, words)
    end)

    it("still finds pasted text by its cleaned form", function()
        local model = search("“dhamma,”")
        assert.equal("dhamma", group(model, "cpd").entries[1].word)
        assert.is_falsy(group(model, "cpd").entries[1].approximate)
    end)

    it("finds lower-case Sanskrit headwords from capitalised input", function()
        local model = search("Śāriputra")
        assert.equal("śāriputra", group(model, "mw").entries[1].word)
        assert.is_falsy(group(model, "mw").entries[1].approximate)
        assert.equal("śāriputra", group(model, "bhs").entries[1].word)
    end)

    it("also tries Apte's nominative after a final vowel, naming only the typed form", function()
        local model = search("dharma")
        assert.equal("dharmaḥ", group(model, "apte").entries[1].word)
        assert.is_falsy(group(model, "apte").entries[1].approximate)
        assert.equal("dharma", group(model, "mw").entries[1].word)
        -- The typed form first, then the nominative.
        assert.equal("dharma", searched()[1])
        assert.truthy(table.concat(searched(), " "):find("dharmaḥ", 1, true))
        local view = Render.render(model, { analyses = {} })
        assert.truthy(view:find(">Other dictionaries</p>", 1, true))
        assert.falsy(view:find("dharmaḥ</p>", 1, true))
    end)

    it("also tries Apte's neuter nominative after a, within the key limit", function()
        for _, text in ipairs({ "phala", '"Phala"' }) do
            local model = search(text)
            local apte = group(model, "apte")
            assert.equal(1, #apte.entries)
            assert.equal("phalaṃ", apte.entries[1].word)
            assert.is_falsy(apte.entries[1].approximate)
            assert.equal("phala", group(model, "mw").entries[1].word)
        end
    end)

    it("finds a lower-case headword from any capital Sanskrit letter", function()
        local entry = group(search("Ḹ"), "mw").entries[1]
        assert.equal("ḹ", entry.word)
        assert.is_falsy(entry.approximate)
    end)

    it("adds no nominative after a consonant", function()
        local model = search("ātman")
        assert.equal("ātman", group(model, "apte").entries[1].word)
        assert.falsy(table.concat(searched(), " "):find("ḥ", 1, true))
    end)

    it("searches ṁ and ŋ as ṃ, as the dictionaries spell it", function()
        assert.equal("saṃsāra", group(search("saṁsāra"), "cpd").entries[1].word)
        assert.equal("saṃsāra", group(search("saŋsāra"), "cpd").entries[1].word)
    end)

    it("falls back to approximate matches without diacritics", function()
        local entry = group(search("sariputra"), "bhs").entries[1]
        assert.equal("śāriputra", entry.word)
        assert.is_true(entry.approximate)
    end)

    it("returns a showable miss, including with no dictionaries selected", function()
        for _, enabled in ipairs({ all, {} }) do
            local model = search("zzzz", enabled)
            assert.is_false(model.found)
            assert.is_true(model.dictionary_search)
            assert.same({}, model.dictionaries.groups)
            local view = Render.render(model, { analyses = {} }, nil, true)
            local none = #enabled == 0
            assert.equal(none, model.dictionaries.none_selected)
            assert.equal(not none, view:find("No entries in the selected dictionaries.", 1, true) ~= nil)
            -- Another spelling cannot help when no dictionary is selected.
            assert.equal(not none, view:find("Try another spelling", 1, true) ~= nil)
            assert.equal(none, view:find("No other dictionaries are selected.", 1, true) ~= nil)
            assert.truthy(view:find("dpd:edit-search", 1, true))
            -- Not DPD's own miss card, which would say no DPD entry and suggest English.
            assert.falsy(view:find("No DPD entry", 1, true))
            assert.falsy(view:find("English", 1, true))
        end
    end)

    it("keeps a long paste to whole characters", function()
        local model = search(string.rep("ā", 80))
        assert.is_true(#model.query <= Lookup.max_dictionary_query)
        assert.equal(model.query, model.query:match("^[ā]+$"))
    end)
end)
