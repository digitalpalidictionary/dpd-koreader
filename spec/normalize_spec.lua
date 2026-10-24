local Normalize = require("dpd/normalize")

local function withUtf8Proc(provider, run)
    local name = "ffi/utf8proc"
    local loaded, preload = package.loaded[name], package.preload[name]
    package.loaded[name] = nil
    package.preload[name] = provider
    local ok, err = pcall(function()
        run(dofile("dpd/normalize.lua"))
    end)
    package.loaded[name], package.preload[name] = loaded, preload
    if not ok then error(err, 0) end
end

describe("canonical normalization and corpus aliases", function()
    it("removes discretionary soft hyphens and labels only spelling rewrites", function()
        assert.equal("dhamma", Normalize.query("dham­ma"))
        -- Zero-width spaces, joiners, word joiners and BOMs from EPUB markup too.
        for _, mark in ipairs({"\226\128\139","\226\128\140","\226\128\141","\226\129\160","\239\187\191"}) do
            assert.equal("dhamma", Normalize.query("dham" .. mark .. "ma"))
            assert.equal("dhamma", Normalize.query(mark .. "dhamma"))
            assert.is_false(Normalize.isRewrite("dham" .. mark .. "ma", "dhamma"))
        end
        for _, pair in ipairs({{"Evaṃ","evaṃ"},{"dhammā","dhammā"},
            {"saṁ","saṃ"},{"saŋ","saṃ"},{"“dham­ma,”","dhamma"}}) do
            assert.is_false(Normalize.isRewrite(pair[1], pair[2]))
        end
        assert.is_true(Normalize.isRewrite("tathā’haṃ","tathāhaṃ"))
        assert.is_true(Normalize.isRewrite("dham-ma","dhamma"))
        assert.is_true(Normalize.isRewrite("avaharissāmā","avaharissāma"))
    end)
    it("composes decomposed Pali without folding meaningful letters", function()
        local decomposed = "āīūṅñṭḍṇḷṃ"
        assert.equal("āīūṅñṭḍṇḷṃ", Normalize.query(decomposed))
        assert.equal("ĀĪŪṄÑṬḌṆḶṂ", Normalize.nfc("ĀĪŪṄÑṬḌṆḶṂ"))
        assert.equal("dhammā", Normalize.candidates("dhammā")[1].key)
        assert.equal("exact", Normalize.candidates("dhammā")[1].via)
        assert.equal("ānanda", Normalize.candidates("ānanda")[1].key)
        assert.equal("exact", Normalize.candidates("ānanda")[1].via)
        assert.not_equal(Normalize.query("dhamma"), Normalize.query("dhammā"))
        assert.not_equal(Normalize.query("saṃ"), Normalize.query("sam"))
    end)

    it("uses native full NFC when KOReader provides it", function()
        local input
        withUtf8Proc(function()
            return { normalize_NFC = function(text) input = text; return "é" end }
        end, function(normalize)
            assert.equal("é", normalize.nfc("é"))
            assert.equal("é", input)
        end)
    end)

    it("has a conservative Pali fallback when the FFI module is absent", function()
        withUtf8Proc(function() error("no standalone utf8proc") end, function(normalize)
            assert.equal("dhammā Ṅ ñ Ṭ ḍ Ṇ Ḷ ṃ Ṁ", normalize.nfc("dhammā Ṅ ñ Ṭ ḍ Ṇ Ḷ ṃ Ṁ"))
            assert.equal("é", normalize.nfc("é")) -- not a general Unicode NFC implementation
            assert.equal("x̄", normalize.nfc("x̄"))
            assert.equal("á̄", normalize.nfc("á̄")) -- preserve intervening unsupported marks
        end)
    end)

    it("falls back if a native normalizer fails", function()
        withUtf8Proc(function()
            return { normalize_NFC = function() error("native normalization unavailable") end }
        end, function(normalize)
            assert.equal("ā", normalize.nfc("ā"))
        end)
    end)

    it("recognizes niggahita conventions without conflating consonants", function()
        for _, form in ipairs({"saṁ", "saṃ", "saŋ", "saṀ", "saŊ", "saṁ", "saṃ"}) do
            assert.equal("saṃ", Normalize.query(form))
        end
        assert.equal("SAṃ", Normalize.query("SAŊ"))
        assert.equal("saṅgha", Normalize.query("saṅgha"))
        assert.equal("sammantayitvā", Normalize.query("sammantayitvā"))
    end)

    it("cleans corpus boundaries and curly sandhi apostrophes", function()
        assert.equal("tathāhaṃ", Normalize.query("*|॥“tathā’haŋ”।|*"))
        assert.equal("tathāhaṃ", Normalize.query("tathā‘haṃ"))
        assert.equal("bhikkhaveti", Normalize.query("bhikkhave’ti"))
        assert.equal("yodha", Normalize.query("yo’dha"))
        assert.equal("tasseva", Normalize.query("tass’eva"))
        assert.equal("a|b", Normalize.query("a|b"))
        assert.equal("a*b", Normalize.query("a*b"))
        assert.same({}, Normalize.candidates("॥|*‘’"))
    end)

    it("tries a literal hyphenated form before labelled letter-joining aliases", function()
        assert.equal("Dhamma-vinaya", Normalize.query("Dhamma-vinaya"))
        assert.same({
            {key="Dhamma-vinaya", via="exact"}, {key="dhamma-vinaya", via="ci"},
            {key="Dhamma-vinaya.", via="dot"}, {key="dhamma-vinaya.", via="dot"},
            {key="Dhammavinaya", via="alias"}, {key="dhammavinaya", via="alias"},
            {key="Dhammavinaya.", via="alias"}, {key="dhammavinaya.", via="alias"},
        }, Normalize.candidates("Dhamma-vinaya"))
        assert.same({ {key="SN", via="exact"}, {key="sn", via="ci"},
            {key="SN.", via="dot"}, {key="sn.", via="dot"} }, Normalize.candidates("SN."))
        for _, form in ipairs({"1-2", "SN-1", "-dhamma", "dhamma-", "a--b", "a - b", "a‐b"}) do
            for _, candidate in ipairs(Normalize.candidates(form)) do assert.not_equal("alias", candidate.via) end
        end
        assert.equal("saṃvidāvahāra", Normalize.candidates("saṃvidā-vahāra")[3].key)
    end)

    it("keeps approximate forms separate from canonical and alias candidates", function()
        assert.equal("avaharissāmā", Normalize.candidates("avaharissāmā")[1].key)
        assert.equal("avaharisama", Normalize.fuzzy("avaharissāmā"))
        assert.equal("saṃmantayitvā", Normalize.candidates("saṃmantayitvā")[1].key)
        assert.equal("samantayitva", Normalize.fuzzy("saṃmantayitvā"))
    end)

    it("strips modifier-letter apostrophes like curly ones", function()
        assert.equal("tathāhaṃ", Normalize.query("tathāʼhaṃ"))
        assert.equal("tathāhaṃ", Normalize.query("tathāʻhaṃ"))
        assert.equal("tathāhaṃ", Normalize.query("tathā’haṃ"))
        assert.equal("tataham", Normalize.fuzzy("tathāʼhaṃ"))
    end)

    it("folds non-Pali accented letters like the exporter's similar-form keys", function()
        assert.equal("fausbol", Normalize.fuzzy("Fausböll"))
        assert.equal("cafe", Normalize.fuzzy("CAFÉ"))
        -- Comma-below and dotless i sit beside ṭ, ṣ and i on KOReader's keyboard.
        assert.equal(Normalize.fuzzy("abbhuṭṭhita"), Normalize.fuzzy("abbhuțțhita"))
        assert.equal(Normalize.fuzzy("ṣaṭ"), Normalize.fuzzy("șaț"))
        assert.equal(Normalize.fuzzy("bhikkhu"), Normalize.fuzzy("bhıkkhu"))
        assert.equal("-grs", Normalize.fuzzy("-GṛS"))
        assert.equal("duhkam", Normalize.fuzzy("duḥkhaṃ"))
        assert.equal("avs", Normalize.fuzzy("AvŚ"))
        -- Exact lookup keeps every diacritic.
        assert.equal("duḥkhaṃ", Normalize.query("duḥkhaṃ"))
    end)
end)
