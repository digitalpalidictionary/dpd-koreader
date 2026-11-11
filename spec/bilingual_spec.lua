local Lookup = require("dpd/lookup")
local Popup = require("dpd/popup")
local Render = require("ui/dpd_render")
local Navigation = require("dpd/navigation")

-- A lookup table with Pāḷi rows, English rows and rows that are both.
local function fixture()
    local db = { rows = {}, columns = { lookup = { epd = true } } }
    function db:lookup(key) return self.rows[key] end
    function db:lookupMany(keys)
        local out = {}
        for _, key in ipairs(keys) do if self.rows[key] then out[#out + 1] = self.rows[key] end end
        return out
    end
    function db:senses(ids)
        local out = {}
        for _, id in ipairs(ids) do out[#out + 1] = { id = id, lemma_1 = "dama", pos = "masc", meaning_1 = "taming" } end
        return out
    end
    function db:fuzzy() return {} end
    function db:fuzzyCount() return 0 end
    local function has(key) return db.rows[key] and (db.rows[key].epd or "") ~= "" end
    function db:english(keys)
        for _, key in ipairs(keys) do if has(key) then return true end end
        return false
    end
    function db:prefix(key, limit)
        local keys, out = {}, {}
        for word, row in pairs(self.rows) do
            if row.headwords and word:sub(1, #key) == key then keys[#keys + 1] = word end
        end
        table.sort(keys)
        for i = 1, math.min(limit, #keys) do out[#out + 1] = self.rows[keys[i]] end
        return out
    end
    -- The English reader's probe: the first candidate key with entries.
    function db:query(sql, params)
        if sql:find("ORDER BY priority LIMIT 1", 1, true) then
            for i, key in ipairs(params) do
                if has(key) then return { { ["epd_" .. i] = self.rows[key].epd } } end
            end
        end
        return {}
    end
    db.rows.dama = { lookup_key = "dama", headwords = "[1]" }
    db.rows.damage = { lookup_key = "damage", epd = '[["hiṃsā","fem","damage"]]' }
    db.rows.time = { lookup_key = "time", headwords = "[2]", epd = '[["kāla","masc","time"]]' }
    db.rows.Buddha = { lookup_key = "Buddha", epd = '[["buddha","masc","Buddha"]]' }
    db.rows.buddha = { lookup_key = "buddha", headwords = "[3]" }
    db.rows.sacca = { lookup_key = "sacca", headwords = "[4]" }
    db.rows.happiness = { lookup_key = "happiness", epd = '[["sukha","nt","happiness"]]' }
    db.rows["etc."] = { lookup_key = "etc.", epd = '[["ādi","masc","etc."]]' }
    return Lookup.new(db), db
end
local button = { english = true }
local function html(value) return Render.render(value, Navigation.new(value):current()) end

describe("English on the DPD buttons", function()
    it("opens English→Pāḷi before the prefix rescue", function()
        local lookup = fixture()
        -- Without it, damage shortens to dama.
        local rescued = lookup:get("damage")
        assert.equal("prefix", rescued.matched_via)
        assert.equal("dama", rescued.suggestions[1].query)
        local value = lookup:get("damage", button)
        assert.equal("english", value.matched_via)
        assert.is_true(value.found)
        assert.equal("hiṃsā", value.english.items[1].lemma)
        assert.equal("dpd", Popup.route(value))
        -- Asked again, and after the other kind of lookup.
        assert.equal("english", lookup:get("Damage,", button).matched_via)
        assert.equal("prefix", lookup:get("damage").matched_via)
    end)

    it("keeps an exact Pāḷi form in Pāḷi", function()
        local lookup = fixture()
        for _, word in ipairs({ "dama", "time", "Buddha" }) do
            local value = lookup:get(word, button)
            assert.is_nil(value.english, word)
            assert.equal(1, #value.senses, word)
        end
    end)

    it("still rescues a word that is not English", function()
        local lookup = fixture()
        local value = lookup:get("saccax", button)
        assert.equal("prefix", value.matched_via)
        assert.equal("sacca", value.suggestions[1].query)
        assert.is_false(lookup:get("xyzzy", button).found)
    end)

    it("never answers long-press or a typed Pāḷi lookup in English", function()
        local lookup = fixture()
        assert.is_nil(lookup:get("damage", Popup.selection_options).english)
        assert.equal("dictionary", Popup.route(lookup:get("damage", Popup.selection_options)))
        assert.is_nil(lookup:get("damage", { spelling = true }).english)
    end)

    it("opens a word selected with quotes or dashes, whichever form came first", function()
        for _, words in ipairs({ { "“happiness”", "happiness" }, { "happiness", "“happiness”" },
            { "“damage”", "damage" }, { "damage—", "“damage”" } }) do
            local lookup = fixture()
            for _, word in ipairs(words) do
                local value = lookup:get(word, button)
                assert.equal("english", value.matched_via, word)
                assert.is_true(value.found, word)
            end
        end
        -- A key with its own punctuation is tried as selected first.
        assert.equal("ādi", fixture():get("etc.", button).english.items[1].lemma)
    end)

    it("works without an English index", function()
        local lookup, db = fixture()
        db.columns.lookup.epd, db.english = nil, nil
        assert.equal("prefix", lookup:get("damage", button).matched_via)
        assert.is_nil(lookup:get("time", button).english_word)
    end)
end)

describe("English link on a Pāḷi form", function()
    it("marks a form that is an English word too, however it was looked up", function()
        local lookup = fixture()
        assert.equal("time", lookup:get("time").english_word)
        assert.equal("time", lookup:get("time", Popup.selection_options).english_word)
        -- The English key has the capital; the Pāḷi row is lowercase.
        assert.equal("Buddha", lookup:get("Buddha", button).english_word)
        assert.is_nil(lookup:get("dama").english_word)
        assert.is_nil(lookup:get("saccax").english_word)
    end)

    it("links the word without quotes or dashes, and in either case", function()
        for _, case in ipairs({ { "“time”", "time" }, { "time—", "time" }, { "buddha", "buddha" },
            { "“Buddha”", "Buddha" } }) do
            local lookup = fixture()
            local word = lookup:get(case[1]).english_word
            assert.equal(case[2], word, case[1])
            assert.is_true(lookup:english(word).found, case[1])
        end
        -- Quoted first or second, the same Pāḷi entry keeps its link.
        local lookup = fixture()
        assert.equal("Buddha", lookup:get("“Buddha”").english_word)
        assert.equal("Buddha", lookup:get("Buddha").english_word)
    end)

    it("renders one link under the entry, and none on other words", function()
        local lookup = fixture()
        local page = html(lookup:get("time"))
        local _, count = page:gsub('href="dpd:english%-word"', "")
        assert.equal(1, count)
        assert.truthy(page:find("English → Pāḷi: time", 1, true))
        assert.is_nil(html(lookup:get("dama")):find("dpd:english-word", 1, true))
        -- The English view itself links to headwords, not back to itself.
        assert.is_nil(html(lookup:get("damage", button)):find("dpd:english-word", 1, true))
    end)

    it("escapes the word", function()
        local value = Lookup.new(select(2, fixture())):get("time")
        value.english_word = "<time>"
        assert.truthy(html(value):find("English → Pāḷi: &lt;time&gt;", 1, true))
    end)
end)
