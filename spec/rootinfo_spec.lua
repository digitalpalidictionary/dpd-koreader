local DB = require("dpd/db")
local RootInfo = require("dpd/rootinfo")
local Navigation = require("dpd/navigation")
local Render = require("ui/dpd_render")

local gam = {root="√gam", root_has_verb="･", root_group=1, root_sign="a", root_meaning="go", root_in_comps="",
    dhatupatha_num="-", dhatupatha_root="-", dhatupatha_pali="-", dhatupatha_english="-",
    dhatumanjusa_num="3", dhatumanjusa_root="gamu", dhatumanjusa_pali="gatimhi", dhatumanjusa_english="going",
    dhatumala_root="gamu", dhatumala_pali="gatiyaṃ", dhatumala_english="going",
    sanskrit_root="√gam", sanskrit_root_class="1", sanskrit_root_meaning="go",
    panini_root="gam ḷ", panini_sanskrit="gatau", panini_english="going", note=""}

local function fixture(bases, columns)
    -- As DB.new records them; a database without dpd_roots records none.
    local db = setmetatable({queries=0, columns={dpd_roots={}}}, DB)
    for name in pairs(columns or gam) do db.columns.dpd_roots[name] = true end
    function db:query(sql, params)
        self.queries = self.queries + 1
        if sql:find("FROM dpd_roots", 1, true) then
            for column in sql:match("^SELECT (.-) FROM"):gmatch("[^,]+") do
                assert(column:find("^[%w_]+$") or column:find("^'' AS [%w_]+$"), column)
            end
            if params[1] ~= "√gam" then return {} end
            local row = {}
            for name, v in pairs(gam) do row[name] = (columns == nil or columns[name]) and v or "" end
            return {row}
        end
        assert(sql:find("root_base FROM dpd_headwords WHERE root_key = ?", 1, true))
        local out = {}
        for _, base in ipairs(bases or {}) do out[#out+1] = {root_base=base} end
        return out
    end
    return RootInfo.new(db), db
end

local function rows(details)
    local out = {}
    for _, row in ipairs(details.rows) do
        local parts = {}
        for _, part in ipairs(row.parts) do parts[#parts+1] = part.text end
        out[row.label] = table.concat(parts)
    end
    return out
end

describe("root details", function()
    it("ports DPD's root info rows", function()
        local info = fixture({"√gam + a > gama", "√gam + a > gama > gaccha (irreg)", "√gam + a > gama", "", "√gam + *e > gāme (caus)"})
        local details = info:details("√gam")
        local r = rows(details)
        assert.equal("√gam･1 bhūvādigaṇa + a (go)", r["Pāḷi root"])
        assert.equal("gama, gāme (caus), gaccha (irreg)", r["Bases"], "shortest first")
        assert.equal("-", r["Dhātupātha"])
        assert.equal("gamu gatimhi (going) #3", r["Dhātumañjūsa"])
        assert.equal("gamu gatiyaṃ (going)", r["Saddanīti"])
        assert.equal("√gam 1 (go)", r["Sanskrit root"])
        assert.equal("gam ḷ gatau (going)", r["Pāṇinīya Dhātupāṭha"])
        assert.is_nil(r["Root in compounds"]); assert.is_nil(r["Notes"])
        assert.is_true(details.rows[1].parts[2].sup)
        assert.is_true(details.rows[4].parts[2].italic)
    end)

    it("labels a single base with a comma as Bases, as upstream does", function()
        local r = rows(fixture({"√añc + *e > aṅke (caus, irreg)"}):details("√gam"))
        assert.equal("aṅke (caus, irreg)", r["Bases"])
        assert.equal("-", rows(fixture({}):details("√gam"))["Base"])
    end)

    it("caches roots and tolerates databases without the optional columns", function()
        local info, db = fixture({})
        info:details("√gam"); local queries = db.queries
        info:details("√gam"); assert.equal(queries, db.queries)
        assert.is_nil(info:details("√none"))
        local minimal = fixture({}, {root=true, root_meaning=true})
        assert.equal("-", rows(minimal:details("√gam"))["Dhātumañjūsa"])
        local absent, absent_db = fixture({}, {})
        assert.is_nil(absent:details("√gam"))
        assert.equal(0, absent_db.queries)
    end)

    it("links from the root card and renders the opened view with markup", function()
        local card = {root="√gam", root_meaning="go", families={}}
        local html = Render.render({query="√gam", found=true, roots={card}, senses={}, grammar={},
            deconstructions={}, suggestions={}, references={}, variants={}}, {})
        assert.is_truthy(html:find('href="dpd:root-details/1">Root details</a>', 1, true))
        local details = fixture({"√gam + a > gama"}):details("√gam")
        html = Render.render({query="√gam", found=true, root_details=details, senses={}, roots={}, grammar={},
            deconstructions={}, suggestions={}, references={}, variants={}}, {})
        assert.is_truthy(html:find("<i>Pāḷi root:</i> √gam<sup>･</sup>1 bhūvādigaṇa", 1, true))
        assert.is_truthy(html:find("<i>Dhātumañjūsa:</i> gamu <i>gatimhi</i> (going) #3", 1, true))
    end)
end)
