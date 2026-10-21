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

    it("lists at most the limit from hand-edited settings and shortens pasted text", function()
        local settings = { history = {} }
        for i = 1, 500 do settings.history[i] = { query = "w" .. i, mode = "pali" } end
        local h = History.new(settings)
        assert.equal(50, #h:list())
        assert.equal("w1", h:list()[1].query)
        h:add(string.rep("a", 99) .. "ā" .. string.rep("b", 50))
        -- Cut on a character boundary: ā would straddle byte 100.
        assert.equal(string.rep("a", 99), h:list()[1].query)
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
