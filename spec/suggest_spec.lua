local Suggest = require("dpd/suggest")
local English = require("dpd/english")

local headwords = {
    { "kamma 1", 5000 }, { "kāma 1", 900 },
    { "dhama", 5 }, { "dhamaka", 0 }, { "dhamana 1", 1 }, { "dhamma 1.01", 9000 }, { "dhamma 1.02", 50 },
    { "dhammavinaya", 300 }, { "dhammika", 20 }, { "dham", 0 }, { "ñāṇa 1", 700 }, { "nānā", 400 },
    { "tiṇasanthāraka", 19 }, { "kāla 1", 1025 }, { "kāḷa", 62 }, { "kala", 5 }, { "kālā", 900 },
    { "jaṇṇuka", 3 }, { "jaṇṇukā", 2 },
}
local lookup = {
    { "nana", "ñāṇa", "[1]" }, { "nana", "nānā", "[2]" }, { "nana", "naña", "" }, { "nana", "nāna", "[3]" },
    { "medit", "meditate", "" }, { "nana", "nanandā", "[4]" },
    { "anatika", "aññātikā", "[5]" }, { "anatika", "āṇattika", "[6]" },
    { "anatika", "āṇattikā", "[6]" }, { "anatika", "āṇattikaṃ", "[6]" }, { "anatika", "anatthika", "[13, 14]" },
    { "anatika", "anatthikā", "[13, 14]" }, { "januka", "jaṇṇuka", "[15, 16]" }, { "januka", "jaṇṇukā", "[15, 16]" },
    { "tinasantaraka", "tiṇasanthāraka", "[7]" }, { "tinasantara", "tiṇasanthara", "[8]" },
    { "kala", "kāla", "[9]" }, { "kala", "kāḷa", "[10]" }, { "kala", "kala", "[11]" }, { "kala", "kālā", "[12]" },
}
local epd = { { "meditate", '[["jhāyati","pr","meditates"]]' }, { "meditated upon", '[["x","pp","y"]]' },
    { "meditation", '[["jhāna","nt","meditation"],["adhicitta","nt","meditation"]]' }, { "medium", "" },
    { "Nibbāna", '[["nibbāna","nt","Nibbāna"]]' }, { "nibble", '[["x","pr","y"]]' },
    { "Awakened One", '[["buddha","masc","Awakened One"]]' },
    { "epithet of the Buddha", '[["buddha","masc","epithet"]]' },
    { "name of Kakusandha Buddha's father", '[["aggidatta","masc","name"]]' },
    { "Aṅguttara Nikāya", '[["aṅguttara","masc","name"]]' } }

local spelling_rows = { kama = { "kāma", "kama" }, kamma = { "kamma" } }

local function fake()
    local db = { queries = {}, columns = { dpd_headwords = { ebt_count = true }, lookup = { fuzzy_key = true, epd = true } } }
    function db:query(sql, p)
        self.queries[#self.queries + 1] = sql
        local out = {}
        if sql:find("FROM dpd_headwords WHERE lemma_1 >= ?", 1, true) then
            local sorted = {}
            for _, h in ipairs(headwords) do sorted[#sorted + 1] = h end
            table.sort(sorted, function(a, b) return a[1] < b[1] end)
            for _, h in ipairs(sorted) do
                if h[1] >= p[1] and h[1] < p[2] and #out < p[3] then out[#out + 1] = { lemma_1 = h[1], ebt_count = h[2] } end
            end
        elseif sql:find("count(*) AS n", 1, true) then
            local i = 0
            for k in sql:gmatch("SELECT (%d+) AS k") do
                local n, ebt = 0, 0
                for _, h in ipairs(headwords) do
                    if h[1] == p[i + 1] or (h[1] >= p[i + 2] and h[1] < p[i + 3]) then n, ebt = n + 1, math.max(ebt, h[2]) end
                end
                out[#out + 1] = { k = tonumber(k), n = n, ebt = ebt }
                i = i + 3
            end
        elseif sql:find("length(epd) AS epd_bytes", 1, true) and sql:find("WHERE fuzzy_key", 1, true) then
            for _, e in ipairs(epd) do
                local key = English.indexKey(e[1])
                if (p[2] and key >= p[1] and key < p[2] or not p[2] and key == p[1]) and e[2] ~= "" then
                    out[#out + 1] = { lookup_key = e[1], epd_bytes = #e[2] }
                end
            end
        elseif sql:find("fuzzy_key >= ?", 1, true) then
            assert(sql:find("LIMIT ?)", 1, true), "fuzzy range is capped")
            for _, l in ipairs(lookup) do
                if l[1] >= p[1] and l[1] < p[2] and l[3] ~= "" then out[#out + 1] = { lookup_key = l[2], headwords = l[3] } end
            end
        elseif sql:find("fuzzy_key = ?", 1, true) then
            for _, l in ipairs(lookup) do
                if l[1] == p[1] then out[#out + 1] = { lookup_key = l[2] } end
            end
        elseif sql:find("fuzzy_key IN (", 1, true) then
            for i = 1, #p - 1 do
                for _, key in ipairs(spelling_rows[p[i]] or {}) do out[#out + 1] = { lookup_key = key } end
            end
        elseif sql:find("WHERE lookup_key IN (", 1, true) then
            -- Candidates come only from capped slices of the key index.
            local _, slices = sql:gsub("ORDER BY lookup_key LIMIT %?%)", "")
            assert(slices * 3 + 3 == #p and sql:find("NOT GLOB", 1, true), "English candidates are capped key slices")
            local limit, hits = p[#p], {}
            local function exact(key) return key == p[#p - 2] or key == p[#p - 1] end
            for _, e in ipairs(epd) do
                local inside = false
                for i = 1, slices do inside = inside or (e[1] >= p[3 * i - 2] and e[1] < p[3 * i - 1]) end
                if inside and e[2] ~= "" then hits[#hits + 1] = e end
            end
            table.sort(hits, function(a, b)
                if exact(a[1]) ~= exact(b[1]) then return exact(a[1]) end
                local sa, sb = a[1]:find(" ", 1, true) ~= nil, b[1]:find(" ", 1, true) ~= nil
                if sa ~= sb then return sb end
                if #a[2] ~= #b[2] then return #a[2] > #b[2] end
                return a[1] < b[1]
            end)
            for i = 1, math.min(limit, #hits) do out[i] = { lookup_key = hits[i][1], epd_bytes = #hits[i][2] } end
        else error("unexpected query " .. sql) end
        return out
    end
    return db
end

local function texts(items)
    local out = {}
    for _, item in ipairs(items) do out[#out + 1] = (item.approximate and "≈" or "") .. item.text end
    return out
end

describe("autocomplete", function()
    it("collapses senses, puts an exact match first, then the most frequent", function()
        local s = Suggest.new(fake())
        assert.same({ "dham", "dhamma", "dhammavinaya", "dhammika" }, texts(s:complete("dham", "pali", 4)))
        assert.equal("dhamma", texts(s:complete("dhamm", "pali", 1))[1])
    end)

    it("adds approximate forms for input without diacritics, headwords first, by frequency", function()
        local got = texts(Suggest.new(fake()):complete("nana", "pali", 6))
        -- nanandā starts with the typed text, so it is not offered as approximate.
        assert.same({ "≈ñāṇa", "≈nānā", "≈nāna" }, got)
    end)

    it("keeps places for approximate forms but scans none after typed diacritics", function()
        local db = fake()
        local got = texts(Suggest.new(db):complete("ñāṇ", "pali", 6))
        assert.same({ "ñāṇa" }, got)
        for _, sql in ipairs(db.queries) do assert.is_nil(sql:find("fuzzy_key >=", 1, true)) end
    end)

    it("offers the headword the keyboard cannot type beside one it can", function()
        -- kāla is a headword, so kāḷa (ḷ has no key) gets a place; the typed ā
        -- is kept, so kala does not; and kāḷa comes before the more frequent
        -- kālā, whose ā the reader could have typed.
        assert.same({ "kāla", "≈kāḷa" }, texts(Suggest.new(fake()):complete("kāla", "pali", 6)))
        -- With one place the exact word keeps it.
        assert.same({ "kāla" }, texts(Suggest.new(fake()):complete("kāla", "pali", 1)))
    end)

    it("puts approximate forms whose opening letters are closest first", function()
        assert.same({ "≈āṇattika", "≈aññātikā", "≈anatthika" }, texts(Suggest.new(fake()):complete("anattika", "pali", 6)))
    end)

    it("gives an entry's inflections one place but keeps headwords that share entries", function()
        assert.same({ "≈jaṇṇuka", "≈jaṇṇukā" }, texts(Suggest.new(fake()):complete("januka", "pali", 6)))
    end)

    it("offers approximate forms when typed diacritics start no headword", function()
        -- The keyboard may have ā but not ṇ: ānattika still finds āṇattika.
        -- nanandā opens nana, one diacritic from ñana, so it comes first.
        -- With no headword, approximate forms may fill every place.
        assert.same({ "≈āṇattika", "≈anatthika", "≈aññātikā" }, texts(Suggest.new(fake()):complete("ānattika", "pali", 6)))
        assert.same({ "≈nanandā", "≈ñāṇa", "≈nāna", "≈nānā" }, texts(Suggest.new(fake()):complete("ñana", "pali", 6)))
    end)

    it("puts whole-word approximate matches before longer, more frequent forms", function()
        assert.same({ "≈tiṇasanthara", "≈tiṇasanthāraka" }, texts(Suggest.new(fake()):complete("tinasanthara", "pali", 6)))
    end)

    it("never loses a word when more of its diacritics are typed", function()
        -- The keyboard has ā and ñ but not ṇ: typing what it can must find
        -- at least what plain letters find.
        for _, case in ipairs{ { "anattika", "ānattika", "āṇattika" }, { "nana", "ñana", "ñāṇa" } } do
            local plain, typed, word = case[1], case[2], case[3]
            local function has(items)
                for _, item in ipairs(items) do if item.text == word then return true end end
            end
            assert.is_true(has(Suggest.new(fake()):complete(plain, "pali", 6)), plain)
            assert.is_true(has(Suggest.new(fake()):complete(typed, "pali", 6)), typed)
        end
    end)

    it("treats ṁ, ŋ and decomposed input as ṃ in Pāḷi mode", function()
        local headwords_before = #headwords
        headwords[#headwords + 1] = { "saṃgha", 100 }
        local s = Suggest.new(fake())
        assert.same({ "saṃgha" }, texts(s:complete("saṃ", "pali", 6)))
        assert.same({ "saṃgha" }, texts(s:complete("saṁ", "pali", 6)))
        assert.same({ "saṃgha" }, texts(s:complete("SAṀ", "pali", 6)))
        assert.same({ "saṃgha" }, texts(s:complete("saŋ", "pali", 6)))
        assert.same({ "saṃgha" }, texts(s:complete("sam\204\163", "pali", 6))) -- m + combining dot below
        headwords[headwords_before + 1] = nil
    end)

    it("ranks approximate forms with one probe statement", function()
        local db = fake()
        Suggest.new(db):complete("nana", "pali", 6)
        local probes = 0
        for _, sql in ipairs(db.queries) do if sql:find("count(*) AS n", 1, true) then probes = probes + 1 end end
        assert.equal(1, probes)
    end)

    it("cleans pasted Pāḷi punctuation, apostrophes and soft hyphens like lookups", function()
        local s = Suggest.new(fake())
        local expected = texts(s:complete("dhamma"))
        for _, input in ipairs({ "“dhamma,”", "dham\194\173ma", "dham’ma", "dhamʼma" }) do
            assert.same(expected, texts(s:complete(input)))
        end
    end)

    it("preserves English apostrophes and ṁ/ŋ instead of applying Pāḷi cleanup", function()
        local db = fake()
        local query = db.query
        local prefix
        function db:query(sql, params)
            if sql:find("WHERE lookup_key IN (", 1, true) then prefix = params[1] end
            return query(self, sql, params)
        end
        Suggest.new(db):complete("  SAṀŊ’S  ", "english")
        assert.equal("saṁŋ’s", prefix)
    end)

    it("suggests capitalised English keys and ignores trailing punctuation", function()
        assert.same({ "Nibbāna", "nibble" }, texts(Suggest.new(fake()):complete("nib", "english")))
        assert.same({ "Nibbāna" }, texts(Suggest.new(fake()):complete("nibbāna", "english")))
        assert.same({ "meditate" }, texts(Suggest.new(fake()):complete("meditate.", "english", 1)))
        assert.same({ "meditate" }, texts(Suggest.new(fake()):complete("meditate?", "english", 1)))
        assert.same({ "meditated upon" }, texts(Suggest.new(fake()):complete("meditated  up", "english")))
    end)

    it("suggests English keys that have English→Pāḷi entries in English mode", function()
        assert.same({ "meditation", "meditate", "meditated upon" }, texts(Suggest.new(fake()):complete("medi", "english")))
        assert.equal("meditate", texts(Suggest.new(fake()):complete("meditate", "english"))[1])
    end)

    it("keeps internally capitalized English suggestions as the typed prefix grows", function()
        local s = Suggest.new(fake())
        for _, text in ipairs({ "awakened o", "awakened one", "AWAKENED ONE", "Awakened One." }) do
            assert.same({ "Awakened One" }, texts(s:complete(text, "english")), text)
        end
        assert.same({ "epithet of the Buddha" }, texts(s:complete("epithet of the b", "english")))
        assert.same({ "epithet of the Buddha" }, texts(s:complete("epithet of the buddha", "english")))
        assert.same({ "name of Kakusandha Buddha's father" },
            texts(s:complete("name of kakusandha buddha's f", "english")))
        assert.same({ "Aṅguttara Nikāya" }, texts(s:complete("aṅguttara ni", "english")))
        assert.same({}, texts(s:complete("anguttara ni", "english")), "diacritics remain meaningful")
        assert.same({}, texts(s:complete("awakenedone", "english")), "spaces remain meaningful")
    end)

    it("reads English candidates from a few capped slices, per next letter from three characters", function()
        local db = fake()
        local query = db.query
        local params
        function db:query(sql, p)
            if sql:find("WHERE lookup_key IN (", 1, true) then params = p end
            return query(self, sql, p)
        end
        Suggest.new(db):complete("me", "english")
        assert.same({ "me", "me\244\143\191\191", 200, "Me", "Me\244\143\191\191", Suggest.english_capital_scan,
            "me", "Me", 6 }, params)
        Suggest.new(db):complete("med", "english")
        -- One general slice, one capitalised, then 28: before a, a to z, after z.
        assert.equal(30 * 3 + 3, #params)
        assert.same({ "med", "med\244\143\191\191", Suggest.english_scan }, { params[1], params[2], params[3] })
        assert.same({ "Med", "Med\244\143\191\191" }, { params[4], params[5] })
        assert.same({ "med", "meda", Suggest.english_letter_scan }, { params[7], params[8], params[9] })
        assert.same({ "med{", "med\244\143\191\191" }, { params[88], params[89] })
    end)

    it("does nothing for empty input or an ID, and caches by mode and text", function()
        local db = fake()
        local s = Suggest.new(db)
        assert.same({}, s:complete("  "))
        assert.same({}, s:complete("123"))
        assert.equal(0, #db.queries)
        s:complete("dham"); local n = #db.queries
        s:complete("dham")
        assert.equal(n, #db.queries)
        s:complete("dham", "english")
        assert.is_true(#db.queries > n)
    end)

    it("generates every one-edit key in folded form, without the key itself", function()
        local edits = Suggest.edits("kama")
        local set = {}
        for _, k in ipairs(edits) do set[k] = true end
        assert.is_true(set.ama and set.akma and set.kima and set.kamva)
        -- An inserted m doubles a consonant, which the fold collapses back to the key.
        assert.is_nil(set.kamma)
        assert.is_nil(set.kama)
    end)

    it("offers headwords one edit away, the most frequent first", function()
        local db = fake()
        -- kamna folds to kamna; kama is one edit away and holds kāma and kama.
        local got = texts(Suggest.new(db):spelling("kamna"))
        assert.same({ "≈kāma", "≈kama" }, got)
        assert.truthy(db.queries[1]:find("fuzzy_key IN (", 1, true))
    end)

    it("measures edits with diacritics and a dropped ṃ counting little", function()
        assert.equal(0.5, Suggest.distance("jāneyyu", "jāneyyuṃ"))
        assert.equal(1, Suggest.distance("jāneyyu", "jāneyya"))
        assert.equal(1, Suggest.distance("kamna", "kamma"))
        assert.equal(1, Suggest.distance("kmama", "kamma"))
        assert.equal(1, Suggest.distance("samadhy", "samādhi"))
        assert.equal(1.5, Suggest.distance("sāmadhy", "samādhi"))
    end)

    it("ranks every candidate by distance before cutting to twenty", function()
        local db = fake()
        local base = db.query
        -- 25 far forms come back first; the one-letter form comes last.
        function db:query(sql, p)
            if not sql:find("fuzzy_key IN (", 1, true) then return base(self, sql, p) end
            self.queries[#self.queries + 1] = sql
            local out = {}
            for i = 1, 25 do out[i] = { lookup_key = "jāneyya" .. string.rep("x", i) } end
            out[26] = { lookup_key = "jāneyyuṃ" }
            return out
        end
        assert.equal("≈jāneyyuṃ", texts(Suggest.new(db):spelling("jāneyyu"))[1])
    end)

    it("skips very short, very long and non-letter input", function()
        local s = Suggest.new(fake())
        assert.same({}, s:spelling("ka"))
        assert.same({}, s:spelling(string.rep("a", 25)))
        assert.same({}, s:spelling("k4ma"))
    end)

    it("renders a miss with one-edit suggestions as links", function()
        local Render = require("ui/dpd_render")
        local html = Render.render({ query = "kamna", found = true, senses = {}, suggestions = {}, deconstructions = {},
            roots = {}, grammar = {}, spelling_suggestions = { { text = "kamma", approximate = true } } }, { analyses = {} })
        assert.truthy(html:find("No DPD entry for “kamna”", 1, true))
        assert.truthy(html:find("dpd:spelling/1", 1, true))
        assert.truthy(html:find("≈ kamma", 1, true))
    end)
end)
