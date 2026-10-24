local RootMatrix = require("dpd/rootmatrix")
local Render = require("ui/dpd_render")

local function h(id, lemma, pos, grammar, root_base)
    return { id = id, lemma_1 = lemma, pos = pos, grammar = grammar or "", root_base = root_base or "" }
end

local gam = {
    h(1, "gacchati 1", "pr", "pr", "√gam + a > gaccha"),
    h(2, "gameti 1", "pr", "pr", "√gam + e > game (caus)"),
    h(3, "āgacchati 1", "pr", "pr", "ā + √gam + a > āgaccha"),
    h(4, "adhigacchati 1", "pr", "pr", "adhi + √gam + a > adhigaccha"),
    h(5, "gata 1", "pp", "pp", ""),
    h(6, "gamana 1", "nt", "nt", ""),
    h(7, "gāmika", "adj", "adj, from pp", ""),
    h(8, "x", "sandhi", "", ""),
}

local function fixture(rows)
    local db = { reads = 0 }
    function db:query(sql, params)
        assert(sql:find("WHERE root_key = ?", 1, true))
        self.reads = self.reads + 1
        return params[1] == "√gam" and rows or {}
    end
    return RootMatrix.new(db), db
end

describe("root matrix", function()
    it("matches whole words as Python's \\b does, counting diacritics as letters", function()
        assert.is_true(RootMatrix.hasWord("√gam + e > game (caus)", "caus"))
        assert.is_false(RootMatrix.hasWord("causative", "caus"))
        assert.is_false(RootMatrix.hasWord("ppā", "pp"))
        assert.is_true(RootMatrix.hasWord("√pass", "pass"))
        assert.is_true(RootMatrix.hasWord("adj, from pp", "pp"))
        assert.is_false(RootMatrix.hasWord("āpp", "pp"))
    end)

    it("places headwords by the first matching rule, as upstream", function()
        assert.same({ "verbs", "pr" }, RootMatrix.classify(gam[1]))
        assert.same({ "verbs", "pr caus" }, RootMatrix.classify(gam[2]))
        assert.same({ "verbs", "pr caus & pass" }, RootMatrix.classify(h(9, "y", "pr", "", "√x + e > xe (caus) > xiya (pass)")))
        assert.same({ "participles", "pp" }, RootMatrix.classify(gam[5]))
        -- Adjectives from past participles share the pp row upstream.
        assert.same({ "participles", "pp" }, RootMatrix.classify(gam[7]))
        assert.same({ "nouns", "nt" }, RootMatrix.classify(h(10, "sogandhika 3", "adj", "", "")))
        assert.is_nil(RootMatrix.classify(gam[8]))
    end)

    it("keeps denominative causatives in their own tense", function()
        assert.same({ "verbs", "fut deno & caus" },
            RootMatrix.classify(h(11, "x", "fut", "", "√x > xe (deno, caus)")))
        assert.same({ "verbs", "aor deno & caus" },
            RootMatrix.classify(h(12, "y", "aor", "", "√x > xe (deno, caus)")))
    end)

    it("groups a root in DPD's order with rows in Pāḷi alphabetical order", function()
        local matrix = fixture(gam):matrix("√gam")
        assert.equal(7, matrix.total)
        local names = {}
        for _, group in ipairs(matrix.groups) do names[#names + 1] = group.name end
        assert.same({ "verbs", "participles", "nouns" }, names)
        local pr = matrix.groups[1].rows[1]
        assert.equal("pr", pr.label)
        local lemmas = {}
        for _, item in ipairs(pr.items) do lemmas[#lemmas + 1] = item.lemma end
        assert.same({ "adhigacchati 1", "āgacchati 1", "gacchati 1" }, lemmas)
        assert.equal("pr caus", matrix.groups[1].rows[2].label)
    end)

    it("caches a bounded number of roots", function()
        local matrix, db = fixture(gam)
        matrix:matrix("√gam"); matrix:matrix("√gam")
        assert.equal(1, db.reads)
        for i = 1, 9 do matrix:matrix("√r" .. i) end
        matrix:matrix("√gam")
        assert.equal(11, db.reads)
        assert.is_true(#matrix.order <= 8)
    end)

    it("superscripts sense numbers like DPD", function()
        assert.equal("gacchati\226\128\138¹", RootMatrix.superscript("gacchati 1"))
        assert.equal("dhamma\226\128\138¹·⁰¹", RootMatrix.superscript("dhamma 1.01"))
    end)

    it("renders the category list and one row's headword links", function()
        local matrix = fixture(gam):matrix("√gam")
        local list = Render.render({ query = "√gam", root_matrix = matrix }, { analyses = {} })
        assert.truthy(list:find("dpd:matrix%-row/1/1"))
        assert.truthy(list:find('<p class="section">participles</p>', 1, true))
        local row = matrix.groups[1].rows[1]
        local page = Render.render({ query = "√gam", matrix_row = { root = "√gam", group = "verbs", label = "pr",
            items = row.items } }, { analyses = {} })
        assert.truthy(page:find("dpd:matrix%-item/3"))
        assert.truthy(page:find("gacchati\226\128\138¹", 1, true))
    end)
end)
