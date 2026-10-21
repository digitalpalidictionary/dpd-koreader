local Json = require("json")
local Frequency = require("dpd/frequency")
local Render = require("ui/dpd_render")

local function vectors(fill)
    local data = {FreqHeading="Frequency of <b>bhikkhu</b> and its declensions"}
    for prefix, length in pairs({Cst=49, Bjt=39, Sya=30, Sc=19}) do
        local counts, grades = {}, {}
        for i = 1, length do counts[i] = fill and fill(prefix, i) or i; grades[i] = i % 11 end
        data[prefix .. "Freq"], data[prefix .. "Grad"] = counts, grades
    end
    return data
end
local function fixture(raw)
    local db = {queries=0}
    function db:query(sql, params)
        self.queries = self.queries + 1
        assert(sql:find("SELECT freq_data FROM dpd_headwords WHERE id = ?", 1, true))
        return raw and {{freq_data=raw}} or {}
    end
    return Frequency.new(db), db
end
local function page(model, state)
    return Render.render({query="bhikkhu", found=true, frequency=model, senses={}, roots={}, grammar={},
        deconstructions={}, suggestions={}, references={}, variants={}}, state or {})
end

describe("frequency table model", function()
    it("places every count by DPD's layout with its grade and row span", function()
        local model = fixture(Json.encode(vectors())):table(5)
        assert.equal(4, #model.sections)
        local parajika = model.sections[1].rows[1]
        assert.equal("Pārājika", parajika.label)
        assert.same({value=1, grade=1, rowspan=1}, parajika.cells.cst_m)
        assert.same({value=34, grade=1, rowspan=5}, parajika.cells.cst_t)
        assert.equal("Frequency of <b>bhikkhu</b> and its declensions", model.heading)
    end)

    it("reports compound-only entries, missing data and damage", function()
        local empty = {FreqHeading="x", CstFreq={}, CstGrad={}, BjtFreq={}, BjtGrad={}, SyaFreq={}, SyaGrad={}, ScFreq={}, ScGrad={}}
        assert.is_true(fixture(Json.encode(empty)):table(1).only_compounds)
        assert.is_truthy(fixture(nil):table(1).error:find("no frequency data", 1, true))
        assert.is_truthy(fixture(""):table(1).error)
        for _, raw in ipairs({"{broken", '{"FreqHeading":1}', Json.encode(vectors(function(_, i) return i == 3 and -1 or i end)),
            string.rep(" ", 16385)}) do
            assert.is_truthy(fixture(raw):table(1).error:find("Replace the database", 1, true))
        end
    end)

    it("maps DPD's ten grades to three e-ink levels", function()
        assert.same({0, 0, 0, 1, 1, 1, 2, 2}, {Frequency.emphasis(0), Frequency.emphasis(1), Frequency.emphasis(3),
            Frequency.emphasis(4), Frequency.emphasis(6), Frequency.emphasis(5), Frequency.emphasis(7), Frequency.emphasis(10)})
    end)
end)

describe("frequency table rendering", function()
    local model = fixture(Json.encode(vectors())):table(5)
    model.lemma = "bhikkhu"

    it("shows all editions in one table when the popup is wide enough", function()
        local html = page(model, {content_em=40})
        local _, tables = html:gsub('<table class="freq">', "")
        assert.equal(1, tables)
        assert.is_truthy(html:find('<th class="corpus" colspan="3">CST</th><th class="corpus" colspan="2">BJT</th>', 1, true))
        assert.is_truthy(html:find('<tr><th class="section" colspan="9">Vinaya</th></tr>', 1, true))
        -- The CST ṭīkā count spans five Vinaya rows; covered rows get no cell.
        assert.is_truthy(html:find('<td rowspan="5">34</td>', 1, true))
        -- Index 21 has grade 10 in this fixture, so it is emphasized.
        assert.is_truthy(html:find('<tr><th>Pācittiya</th><td>2</td><td class="high"><b>21</b></td><td>2</td>', 1, true))
        assert.is_truthy(html:find("not of this sense alone", 1, true))
        -- The table starts the view; the key and the counting note follow it.
        local key, first_table = html:find("M mūla, A aṭṭhakathā, Ṭ ṭīkā.", 1, true), html:find('<table class="freq">', 1, true)
        assert.is_truthy(key and key > first_table)
        assert.is_truthy(html:find("not of this sense alone", 1, true) > key)
    end)

    it("splits editions into narrower tables on a small popup", function()
        local html = page(model, {content_em=24})
        local _, tables = html:gsub('<table class="freq">', "")
        assert.equal(2, tables)
        assert.is_truthy(html:find('<tr><th class="section" colspan="6">Vinaya</th></tr>', 1, true))
        assert.is_truthy(html:find('<tr><th class="section" colspan="4">Vinaya</th></tr>', 1, true))
    end)

    it("bolds high counts and greys the highest", function()
        local html = page(model, {content_em=40})
        assert.is_truthy(html:find('<td class="high"><b>7</b></td>', 1, true))
        assert.is_truthy(html:find("<td><b>4</b></td>", 1, true))
    end)

    it("links Frequency only from senses with data", function()
        local sense = {id=7, lemma_1="bhikkhu", pos="masc", meaning_combo="monk"}
        local html = Render.render({query="bhikkhu", found=true, senses={sense}, grammar={}, deconstructions={},
            suggestions={}, references={}, roots={}, variants={}}, {expanded={[7]=true}, details={[7]={has_frequency=1}}})
        assert.is_truthy(html:find('href="dpd:detail-frequency/7">Frequency</a>', 1, true))
        html = Render.render({query="bhikkhu", found=true, senses={sense}, grammar={}, deconstructions={},
            suggestions={}, references={}, roots={}, variants={}}, {expanded={[7]=true}, details={[7]={has_frequency=0}}})
        assert.is_falsy(html:find("detail-frequency", 1, true))
    end)
end)

describe("frequency layout", function()
    it("extracts a frequency layout covering every displayed vector position once", function()
        local layout = require("dpd/frequency_layout")
        local seen = { cst = {}, bjt = {}, sya = {}, sc = {} }
        for _, section in ipairs(layout.sections) do
            for _, row in ipairs(section.rows) do
                for _, cell in ipairs(row.cells) do
                    local corpus = cell.column:match("^(%a+)_")
                    assert.is_nil(seen[corpus][cell.index]); seen[corpus][cell.index] = true
                end
            end
        end
        for corpus, length in pairs(layout.lengths) do
            local unused = 0
            for _ in ipairs((layout.unused or {})[corpus] or {}) do unused = unused + 1 end
            local count = 0
            for _ in pairs(seen[corpus]) do count = count + 1 end
            assert.equal(length, count + unused, corpus)
        end
    end)
end)
