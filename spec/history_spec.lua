local History = require("dpd/history")

describe("recent lookups", function()
    it("keeps newest first, moves a repeat to the front and trims to the limit", function()
        local settings = {}
        local h = History.new(settings, 3)
        h:add("dhamma"); h:add("buddha"); h:add(" dhamma "); h:add("saṅgha"); h:add("kamma")
        local queries = {}
        for _, item in ipairs(h:list()) do queries[#queries + 1] = item.query end
        assert.same({ "kamma", "saṅgha", "dhamma" }, queries)
    end)

    it("lists at most the limit from hand-edited settings and preserves long queries", function()
        local settings = { history = {} }
        for i = 1, 500 do settings.history[i] = { query = "w" .. i, mode = "pali" } end
        local h = History.new(settings)
        assert.equal(50, #h:list())
        assert.equal("w1", h:list()[1].query)
        local query = string.rep("a", 99) .. "ā" .. string.rep("b", 50)
        h:add(query)
        assert.equal(query, h:list()[1].query)
    end)

    it("omits oversized queries and drafts instead of storing a different lookup", function()
        local settings = { history = { { query = string.rep("a", History.max_query + 1) } } }
        local h = History.new(settings)
        assert.same({}, h:list())
        h:add("dhamma")
        h:add(string.rep("ā", History.max_query))
        h:add("vacūm", "dictionaries", string.rep("a", History.max_query + 1))
        assert.same({ { query = "dhamma", mode = "pali" } }, h:list())
        h:add(string.rep("a", History.max_query))
        assert.equal(History.max_query, #h:list()[1].query)
    end)

    it("keeps dictionary literal fallbacks distinct and reuses legacy records", function()
        local settings = { history = { { query = "vacūm", mode = "dictionaries" } } }
        local h = History.new(settings)
        h:add("vacūm", "dictionaries", "vacuum")
        assert.same({
            { query = "vacūm", mode = "dictionaries", draft = "vacuum" },
            { query = "vacūm", mode = "dictionaries" },
        }, h:list())
        h:add("vacūm", "dictionaries", "vacūm")
        assert.equal(2, #h:list())
        assert.is_nil(h:list()[1].draft)
        h:add("vacūm", "dictionaries", "vacuum")
        assert.equal(2, #h:list())
        assert.equal("vacuum", h:list()[1].draft)
    end)

    it("deduplicates trimmed and NFC-equivalent dictionary drafts", function()
        local h = History.new({})
        h:add("dharma", "dictionaries", "dharma")
        h:add("dharma", "dictionaries", " dharma ")
        assert.same({ { query = "dharma", mode = "dictionaries" } }, h:list())
        h:add("ānanda", "dictionaries", "ānanda")
        h:add("ānanda", "dictionaries", " ānanda\t")
        assert.equal(2, #h:list())
        assert.is_nil(h:list()[1].draft)
        h:add("vacūm", "dictionaries", " vacuum ")
        h:add("vacūm", "dictionaries", "vacuum")
        assert.equal(3, #h:list())
        assert.equal("vacuum", h:list()[1].draft)
        h:add("vacūm", "dictionaries", " vacūm ")
        assert.equal(4, #h:list(), "the literal vacuum fallback remains a distinct search")
        assert.is_nil(h:list()[1].draft)
        assert.equal("vacuum", h:list()[2].draft)
    end)

    it("compares existing dictionary drafts using the same canonical form", function()
        local settings = { history = {
            { query = "vacūm", mode = "dictionaries", draft = " vacuum " },
            { query = "ānanda", mode = "dictionaries", draft = "ānanda" },
        } }
        local h = History.new(settings)
        h:add("vacūm", "dictionaries", "vacuum")
        h:add("ānanda", "dictionaries")
        assert.same({
            { query = "ānanda", mode = "dictionaries" },
            { query = "vacūm", mode = "dictionaries", draft = "vacuum" },
        }, h:list())
    end)

    it("stores the search mode and treats modes separately", function()
        local h = History.new({})
        h:add("peace", "english"); h:add("peace")
        assert.same({ { query = "peace", mode = "pali" }, { query = "peace", mode = "english" } }, h:list())
    end)

    it("ignores empty queries and damaged entries", function()
        local settings = { history = { "old string", { query = 5 }, { query = "ok", mode = "pali" } } }
        local h = History.new(settings)
        h:add("  ")
        assert.same({ { query = "ok", mode = "pali" } }, h:list())
        h:add("new")
        assert.equal(2, #settings.history)
    end)

    it("clears, and turning it off forgets and stops recording", function()
        local settings = {}
        local h = History.new(settings)
        h:add("a"); h:clear()
        assert.same({}, h:list())
        h:add("b"); h:setEnabled(false)
        assert.is_false(h:enabled())
        h:add("c")
        assert.same({}, h:list())
        h:setEnabled(true); h:add("d")
        assert.equal("d", h:list()[1].query)
        assert.is_nil(settings.history_off)
    end)
end)
