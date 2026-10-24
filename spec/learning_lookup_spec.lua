local Lookup = require("dpd/lookup")
local Normalize = require("dpd/normalize")
local DB = require("dpd/db")

local function fixture()
    local db = { rows = {}, records = {}, root_records = {}, detail_rows = {}, fuzzy_calls = 0 }
    function db:lookup(key) return self.rows[key] end
    function db:lookupMany(keys)
        local out = {}; for _, key in ipairs(keys) do if self.rows[key] then out[#out + 1] = self.rows[key] end end
        return out
    end
    function db:senses(ids)
        local out = {}; for _, id in ipairs(ids) do if self.records[id] then out[#out + 1] = self.records[id] end end
        return out
    end
    function db:sensesByLemma(lemmas)
        local out = {}; for _, lemma in ipairs(lemmas) do for _, row in pairs(self.records) do
            if row.lemma_1 == lemma then out[#out + 1] = row end
        end end; return out
    end
    function db:roots(keys)
        local out = {}; for _, key in ipairs(keys) do if self.root_records[key] then out[#out + 1] = self.root_records[key] end end
        return out
    end
    function db:detail(id) return self.detail_rows[id] end
    function db:fuzzy() self.fuzzy_calls = self.fuzzy_calls + 1; return {} end
    function db:fuzzyCount() return 0 end
    local function record(id, lemma, key)
        db.records[id] = { id = id, lemma_1 = lemma, pos = "noun", meaning_1 = "meaning " .. lemma }
        if key then db.rows[key] = { lookup_key = key, headwords = "[" .. id .. "]" } end
    end
    record(1, "dhamma 1.01", "dhamma")
    record(2, "dhamma 1.02")
    record(3, "hotīti", "hotīti")
    record(4, "cakka", "cakka")
    db.root_records["√dhar"] = { root = "√dhar", root_meaning = "hold" }
    db.root_records["√dhar 1"] = { root = "√dhar 1", root_meaning = "support" }
    return Lookup.new(db), db
end

describe("exact learning lookup identities", function()
    it("resolves uppercase numbered lemmas without widening their homonym", function()
        local lookup, db = fixture()
        for _, input in ipairs({ "dhamma 1.01", "Dhamma 1.01", "DHAMMA 1.01" }) do
            local result = lookup:get(input)
            assert.is_true(result.found)
            assert.equal(input, result.original)
            assert.equal("dhamma 1.01", result.query)
            assert.equal(1, #result.senses)
            assert.equal(1, result.senses[1].id)
        end
        assert.is_false(lookup:get("Dhamma 1.03", { approximate = false }).found)
        assert.equal(0, db.fuzzy_calls)
    end)

    it("recognizes mixed and uppercase quote-ti while keeping literal priority", function()
        local lookup, db = fixture()
        for _, input in ipairs({ 'HOTĪ”TI', 'hotī”Ti', 'HOTĪ"tI' }) do
            local result = lookup:get(input)
            assert.equal("hotīti", result.query)
            assert.equal("alias", result.matched_via)
            assert.equal(3, result.senses[1].id)
        end
        db.rows['HOTĪ”TI'] = { lookup_key = 'HOTĪ”TI', headwords = '[4]' }
        assert.equal(4, Lookup.new(db):get('HOTĪ”TI').senses[1].id)
        local candidates = Normalize.candidates('SA"NGHA')
        for _, candidate in ipairs(candidates) do assert.not_equal("sangha", candidate.key) end
        assert.equal(0, db.fuzzy_calls)
    end)

    it("batches normalized headword candidates while keeping literal identity first", function()
        local lookup, db = fixture()
        local batch, calls = db.sensesByLemma, 0
        function db:sensesByLemma(lemmas)
            calls = calls + 1
            assert.is_true(#lemmas > 1)
            return batch(self, lemmas)
        end
        db.records[5] = { id=5, lemma_1="Dhamma 1.01", pos="noun", meaning_1="literal entry" }
        assert.equal(5, lookup:headword("Dhamma 1.01").senses[1].id)
        assert.equal(1, calls)
        db.records[5] = nil
        assert.equal(1, lookup:headword("Dhamma 1.01").senses[1].id)
        assert.equal(2, calls)
    end)

    it("loads root families for full cards rather than compact compound components", function()
        local lookup, db = fixture()
        db.rows["√dhar 1"] = { lookup_key="√dhar 1", roots='["√dhar 1"]' }
        db.rows.compound = { lookup_key="compound", deconstructor='["√dhar 1 + cakka"]' }
        local calls = 0
        function lookup:rootFamilies(root) calls = calls + 1; root.families = {}; return root.families end
        local result = lookup:get("compound", { approximate=false })
        assert.equal(0, calls)
        assert.equal(1, #result.components["√dhar 1"].roots)
        assert.equal("support", result.components["√dhar 1"].roots[1].root_meaning)
        assert.equal(1, #lookup:get("√dhar 1", { approximate=false }).roots)
        assert.equal(1, calls)
    end)

    it("keeps detail navigation exact and roots independently numbered", function()
        local lookup, db = fixture()
        assert.equal(1, lookup:target("Dhamma 1.01", "headword").senses[1].id)
        assert.equal("√dhar 1", lookup:target("√dhar 1", "root").roots[1].root)
        assert.is_nil(lookup:target("√dhar 2", "root"))
        assert.is_nil(lookup:target("dhama", "form"))
        assert.is_nil(lookup:target("1", "headword"))
        assert.is_nil(lookup:target("dhamma", "unknown"))
        assert.equal(0, db.fuzzy_calls)
    end)

    it("preserves construction markup and separators, linking only resolved operands", function()
        local lookup, db = fixture()
        db.detail_rows[1] = { id = 1, construction = "<b>dhamma 1.01</b> + unknown\n√dhar 1 + cakka",
            compound_construction = "dhamm<b>assa</b> + cakka", root_key = "√dhar 1",
            derived_from = "dhamma 1.02", synonym = "cakka, unknown", antonym = "dhama",
            sanskrit = "dharma", cognate = "related term", non_ia = "origin note", root_sign = "a" }
        local detail = lookup:detail(1)
        assert.equal("dharma", detail.sanskrit)
        assert.equal("related term", detail.cognate)
        assert.equal("origin note", detail.non_ia)
        assert.equal("a", detail.root_sign)
        local rebuilt = {}; for _, part in ipairs(detail.field_parts.construction) do rebuilt[#rebuilt + 1] = part.text end
        assert.equal(db.detail_rows[1].construction, table.concat(rebuilt))
        local first = detail.field_parts.construction[1]
        assert.equal("<b>dhamma 1.01</b>", first.text)
        assert.equal(1, detail.targets[first.target_index].model.senses[1].id)
        assert.is_nil(detail.field_parts.construction[3].target_index)
        assert.equal(2, detail.targets[detail.field_parts.derived_from[1].target_index].model.senses[1].id)
        assert.equal("root", detail.targets[detail.field_parts.root_key[1].target_index].kind)
        assert.equal("support", detail.root_meaning)
        assert.is_nil(detail.field_parts.antonym[1].target_index)
        assert.is_nil(detail.field_parts.compound_construction[1].target_index)
        assert.same({}, detail.families)
        assert.equal(0, db.fuzzy_calls)
    end)

    it("projects missing optional etymology and family fields as empty values", function()
        local db = setmetatable({ columns = { dpd_headwords = { id = true, grammar = true } } }, DB)
        local sql
        function db:query(query) sql = query; return { { id = 1, grammar = "noun" } } end
        local row = db:detail(1)
        assert.equal("noun", row.grammar)
        for _, name in ipairs({ "sanskrit", "cognate", "non_ia", "root_sign", "family_root", "family_word", "family_compound", "family_idioms" }) do
            assert.is_truthy(sql:find("'' AS " .. name, 1, true), name)
        end
    end)

    it("keeps valid detail text when an optional navigation target is damaged", function()
        local lookup, db = fixture()
        db.rows.badtarget = { lookup_key = "badtarget", headwords = '["not an ID"]' }
        db.detail_rows[1] = { id = 1, construction = "cakka + badtarget", sanskrit = "dharma" }
        local detail = lookup:detail(1)
        assert.equal("dharma", detail.sanskrit)
        assert.is_truthy(detail.field_parts.construction[1].target_index)
        assert.is_nil(detail.field_parts.construction[3].target_index)
        assert.equal("badtarget", detail.field_parts.construction[3].text)
        assert.has_error(function() lookup:get("badtarget", { approximate = false }) end)
    end)
end)
