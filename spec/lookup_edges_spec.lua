local Lookup = require("dpd/lookup")
local Normalize = require("dpd/normalize")
local Render = require("ui/dpd_render")
local Navigation = require("dpd/navigation")
local Popup = require("dpd/popup")

local function fixture(rows, senses, neighbours)
    local db = { calls = {}, fuzzy_calls = 0 }
    function db:lookup(key)
        self.calls[#self.calls + 1] = key
        return rows[key]
    end
    function db:lookupMany(keys)
        local out = {}
        for _, key in ipairs(keys) do if rows[key] then out[#out + 1] = rows[key] end end
        return out
    end
    function db:senses(ids)
        local out = {}
        for _, id in ipairs(ids) do if senses and senses[id] then out[#out + 1] = senses[id] end end
        return out
    end
    function db:fuzzy()
        self.fuzzy_calls = self.fuzzy_calls + 1
        return neighbours or {}
    end
    return Lookup.new(db), db
end

local variant = '{"SYA":{"VV":[["tisahassāni sūdāni","yu. janā tisahassā sūdā."]]}}'

describe("lookup edge cases", function()
    it("keeps a recorded correction and its readings ahead of approximate neighbours", function()
        local neighbour = { lookup_key = "sudāni", headwords = "[1]" }
        local lookup, db = fixture({
            ["sūdāni"] = { lookup_key = "sūdāni", variant = variant, spelling = '["sūdā hi"]' },
            ["sudāni"] = neighbour,
        }, { [1] = { id = 1, lemma_1 = "sudāni", meaning_1 = "now" } }, { neighbour })
        local exact = lookup:get("sūdāni", { approximate = false })
        assert.is_false(Lookup.isVariantOnly(exact))
        assert.is_true(Lookup.directHit(exact))
        assert.equal("missing", exact.references[1].status)
        local result = lookup:get("sūdāni")
        assert.equal(0, #result.suggestions)
        assert.equal(0, db.fuzzy_calls)
        assert.equal("dpd", Popup.route(result))
        local frame = Navigation.new(result):current()
        frame.variants_open = true
        local html = Render.render(result, frame)
        assert.is_truthy(html:find("Incorrect spelling of sūdā hi", 1, true))
        assert.is_truthy(html:find("tisahassāni sūdāni", 1, true))
        assert.is_falsy(html:find("unavailable", 1, true))
    end)

    it("treats correction and referral text as content even when navigation is unavailable", function()
        local lookup = fixture({
            missing = { lookup_key = "missing", spelling = '["absent"]' },
            cycle = { lookup_key = "cycle", see = '["cycle"]' },
            empty = { lookup_key = "empty", see = '["placeholder"]' },
            placeholder = { lookup_key = "placeholder" },
        })
        for _, key in ipairs({ "missing", "cycle", "empty" }) do
            local value = lookup:get(key, { approximate = false })
            assert.is_true(value.found)
            assert.is_true(Lookup.directHit(value))
            assert.equal(1, #value.references)
            assert.is_truthy(value.references[1].status)
        end
    end)

    it("opens a phrase correction without inventing definitions or approximate replacements", function()
        local lookup, db = fixture({
            ["bhikkhunābhinandati"] = { lookup_key = "bhikkhunābhinandati", spelling = '["bhikkhu nābhinandati"]' },
        })
        local result = lookup:get("bhikkhunābhinandati", Popup.selection_options)
        assert.is_true(result.found)
        assert.equal("dpd", Popup.route(result))
        assert.equal(0, #result.senses)
        assert.equal(0, #result.deconstructions)
        assert.equal(0, db.fuzzy_calls)
        local html = Render.render(result, Navigation.new(result):current())
        assert.is_truthy(html:find("Incorrect spelling of bhikkhu nābhinandati", 1, true))
        assert.is_falsy(html:find("No DPD entry", 1, true))
        assert.is_falsy(html:find("unavailable", 1, true))
        assert.is_falsy(html:find("dpd:reference/1", 1, true))
    end)

    it("does not count blank correction or referral targets as content", function()
        local lookup = fixture({ blank = { lookup_key = "blank", spelling = '["", "  "]', see = '[" "]' } })
        local result = lookup:get("blank", { approximate = false })
        assert.is_false(result.found)
        assert.equal(0, #result.references)
    end)

    it("retains successful references as direct dictionary content", function()
        local lookup = fixture({
            source = { lookup_key = "source", variant = variant, see = '["target"]' },
            target = { lookup_key = "target", help = '"useful information"' },
        })
        local result = lookup:get("source")
        assert.is_true(result.found)
        assert.is_false(Lookup.isVariantOnly(result))
        assert.is_true(Lookup.directHit(result))
    end)

    it("keeps a referral to contextual readings useful without inventing a definition", function()
        local lookup = fixture({
            source = { lookup_key = "source", see = '["target"]' },
            target = { lookup_key = "target", variant = variant },
        })
        local exact = lookup:get("source", { approximate = false })
        assert.is_true(exact.found)
        assert.is_false(Lookup.isVariantOnly(exact))
        assert.is_true(Lookup.directHit(exact))
        assert.equal(0, #exact.senses)
    end)

    it("preserves literal punctuation abbreviations and separate cache identities", function()
        local rows = {}
        local literals = { "*", "**", "()", "[]", "BHS(G)", "BHS(V)", "SN (= S)",
            "ms(s)", "AN(= A)", "Vism (=Vm)", "-k, -koça, -kosa:" }
        for _, key in ipairs(literals) do
            rows[key] = { lookup_key = key, abbrev = '{"meaning":"literal ' .. key .. '"}' }
        end
        rows["ms(s"] = { lookup_key = "ms(s", help = '"different record"' }
        local lookup, db = fixture(rows)
        assert.equal("ms(s", lookup:get("ms(s", { approximate = false }).query)
        for _, key in ipairs(literals) do
            for _, form in ipairs({ key, "“" .. key .. "”", key }) do
                local result = lookup:get(form, { approximate = false })
                assert.is_true(result.found)
                assert.equal(key, result.query)
                assert.equal("literal " .. key, result.abbrev.meaning)
                assert.equal(form, result.original)
            end
        end
        assert.equal("ms(s", lookup:get("ms(s", { approximate = false }).query)
        assert.equal(0, db.fuzzy_calls)
    end)

    it("normalizes literal Unicode keys and keeps ordinary quoted lookups cheap", function()
        local lookup, db = fixture({
            ["saṃ(G)"] = { lookup_key = "saṃ(G)", help = '"literal"' },
            ["dhamma"] = { lookup_key = "dhamma", headwords = "[1]" },
        }, { [1] = { id = 1, lemma_1 = "dhamma", meaning_1 = "ordinary" } })
        assert.equal("saṃ(G)", lookup:get("saṁ(G)", { approximate = false }).query)
        assert.equal("dhamma", lookup:get("“dhamma,”", { approximate = false }).query)
        assert.equal("dhamma", db.calls[#db.calls])
        assert.equal(2, #db.calls)
        assert.equal("dhamma", lookup:get("dhamma", { approximate = false }).query)
        assert.equal(2, #db.calls)
        assert.equal("tathāhaṃ", Normalize.query("“tathā’haṃ”"))
    end)
end)
