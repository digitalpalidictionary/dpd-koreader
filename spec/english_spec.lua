local English = require("dpd/english")
local Render = require("ui/dpd_render")

local function fake(rows)
    local db = { reads = {}, columns = { lookup = { epd = true, fuzzy_key = true } } }
    function db:query(sql, p)
        if sql:find("WHERE fuzzy_key = ?", 1, true) then
            local out = {}
            for key, value in pairs(rows) do
                if English.indexKey(key) == p[1] and value ~= "" and value ~= "[]" then
                    out[#out + 1] = { lookup_key = key, epd_bytes = #value }
                end
            end
            table.sort(out, function(a, b) return a.lookup_key < b.lookup_key end)
            return out
        end
        if sql:find("ORDER BY priority LIMIT 1", 1, true) then
            for i, key in ipairs(p) do
                self.reads[#self.reads + 1] = key
                local value = rows[key]
                if value and value ~= "" and value ~= "[]" then return { { ["epd_" .. i] = value } } end
            end
            return {}
        end
        assert(sql:find("SELECT epd FROM lookup WHERE lookup_key = ?", 1, true), sql)
        self.reads[#self.reads + 1] = p[1]
        return rows[p[1]] and { { epd = rows[p[1]] } } or {}
    end
    return db
end

local function items(n)
    local out = {}
    for i = 1, n do out[i] = string.format('["lemma%d","nt","meaning %d"]', i, i) end
    return "[" .. table.concat(out, ",") .. "]"
end

describe("English→Pāḷi", function()
    it("finds the word as typed, then lowercase, then capitalized", function()
        local db = fake({ meditation = '[["jhāna","nt","meditation"]]', Sanskrit = '[["sakkata","adj","Sanskrit"]]',
            ["Ānanda the elder"] = '[["ānanda","masc","Ānanda the elder"]]' })
        local e = English.new(db)
        local page = e:page("Meditation")
        assert.equal("meditation", page.query)
        assert.same({ lemma = "jhāna", pos = "nt", meaning = "meditation" }, page.items[1])
        assert.equal("Sanskrit", English.new(db):page("sanskrit").query)
        assert.equal("Ānanda the elder", English.new(db):page("ānanda the elder").query)
        assert.equal(0, English.new(db):page("nothing").total)
    end)

    it("folds Unicode case, drops trailing punctuation and knows nibbana", function()
        local db = fake({ monk = '[["bhikkhu","masc","monk"]]', ["Nibbāna"] = '[["nibbāna","nt","Nibbāna"]]',
            ["etc."] = '[["ādi","adj","etc."]]' })
        assert.equal("Nibbāna", English.new(db):page("NIBBĀNA").query)
        assert.equal("Nibbāna", English.new(db):page("nibba\204\132na").query) -- a + combining macron
        assert.equal("Nibbāna", English.new(db):page("nibbana").query)
        assert.equal("Nibbāna", English.new(db):page("Nirvana").query)
        assert.equal("monk", English.new(db):page("monk.").query)
        assert.equal("monk", English.new(db):page("Monk,").query)
        -- A key's own punctuation is found first.
        assert.equal("etc.", English.new(db):page("etc.").query)
    end)

    it("treats repeated spaces as one", function()
        local db = fake({ ["good deed"] = '[["kusala","adj","good deed"]]' })
        local page = English.new(db):page("  good \t deed ")
        assert.equal("good deed", page.query)
        assert.equal(1, page.total)
    end)

    it("finds capitals inside a phrase and preserves them when removing punctuation", function()
        local db = fake({ ["Awakened One"] = items(2), ["epithet of the Buddha"] = items(41),
            ["name of Kakusandha Buddha's father"] = items(1), ["Chapter etc."] = items(3) })
        for _, word in ipairs({ "awakened one", "AWAKENED ONE", "Awakened One", "Awakened One." }) do
            local page = English.new(db):page(word)
            assert.equal("Awakened One", page.query)
            assert.equal(2, page.total)
        end
        local page = English.new(db):page("epithet of the buddha")
        assert.equal("epithet of the Buddha", page.query)
        assert.equal(41, page.total)
        assert.equal(1, English.new(db):page("name of kakusandha buddha's father").total)
        assert.equal(3, English.new(db):page("CHAPTER ETC.").total)
    end)

    it("uses fuzzy keys only to discover case variants, never different English spellings", function()
        local db = fake({ ["Aṅguttara Nikāya"] = items(1), ["Aspirated Dhamma"] = items(2),
            ["A'S"] = items(3), ["Two Words"] = items(4), ["US"] = items(5), us = items(6) })
        assert.equal(1, English.new(db):page("aṅguttara nikāya").total)
        for _, word in ipairs({ "anguttara nikaya", "aspirated dama", "as", "twowords" }) do
            assert.equal(0, English.new(db):page(word).total, word)
        end
        assert.equal(5, English.new(db):page("US").total, "literal case keeps precedence")
        assert.equal(6, English.new(db):page("us").total)
        db.columns.lookup.fuzzy_key = nil
        assert.equal(5, English.new(db):page("US").total, "older schemas retain exact lookup")
        assert.equal(0, English.new(db):page("aṅguttara nikāya").total)
    end)

    it("pages by 20 from one decoded key", function()
        local db = fake({ mind = items(45) })
        local e = English.new(db)
        local first = e:page("mind")
        assert.equal(20, #first.items)
        assert.equal(45, first.total)
        assert.is_true(first.has_more)
        local reads = #db.reads
        local last = e:page("mind", 40)
        assert.equal(5, #last.items)
        assert.equal("lemma41", last.items[1].lemma)
        assert.is_false(last.has_more)
        assert.equal(reads, #db.reads)
    end)

    it("reports damaged data instead of failing", function()
        local page = English.new(fake({ bad = "{not json" })):page("bad")
        assert.truthy(page.error)
        assert.equal(0, #page.items)
        -- Valid JSON of the wrong shape is damage too, not an empty entry.
        for _, raw in ipairs({ '{"unexpected":[]}', '{"1":["lemma","nt","m"]}' }) do
            page = English.new(fake({ shape = raw })):page("shape")
            assert.truthy(page.error)
            assert.equal(0, #page.items)
        end
    end)

    it("renders lemmas as links with Show more", function()
        local e = English.new(fake({ mind = items(25) }))
        local html = Render.render({ query = "mind", english = e:page("mind") }, { analyses = {} })
        assert.truthy(html:find("dpd:english%-item/20"))
        assert.truthy(html:find("dpd:english-more", 1, true))
        assert.truthy(html:find("20&nbsp;of&nbsp;25&nbsp;entries", 1, true))
    end)
end)
