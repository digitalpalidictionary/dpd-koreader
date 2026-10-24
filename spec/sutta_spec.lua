local Sutta = require("dpd/sutta")
local Render = require("ui/dpd_render")

local function row(fields)
    local out = { dpd_sutta = "", dpd_sutta_var = "", dpd_code = "", cst_vagga = "", sc_vagga = "", bjt_vagga = "" }
    for k, v in pairs(fields) do out[k] = v end
    return out
end

local rows = {
    row{ dpd_sutta = "brahmajālasutta", dpd_code = "DN1", cst_code = "DN1.1", cst_sutta = "1. Brahmajālasuttaṃ",
        sc_eng_sutta = "The Divine Net", sc_blurb = "On <i lang='pi' translate='no'>sīla</i>.", bjt_filename = "dn-1",
        dv_pts = "D i 1,7", dv_main_theme = "Ethics", dv_taisho_parallels = "T1" },
    row{ dpd_sutta = "pāthikavaggapāḷi", dpd_sutta_var = "pāṭikavagga; pāthikavagga", dpd_code = "DN24-34",
        cst_vagga = "Pāthikavagga", cst_sutta = "hidden", dv_pts = "hidden" },
    row{ dpd_sutta = "devatāsaṃyutta", dpd_code = "SN1", cst_vagga = "hidden", sc_eng_sutta = "hidden", cst_book = "Sagāthā" },
    row{ dpd_sutta = "ekakanipāta", dpd_code = "AN1" },
    row{ dpd_sutta = "mūlapaṇṇāsapāḷi", dpd_code = "MN1-50" },
    row{ dpd_sutta = "first", dpd_sutta_var = "shared", dpd_code = "X1.1" },
    row{ dpd_sutta = "second", dpd_sutta_var = "shared ; first", dpd_code = "X1.2" },
    row{ dpd_sutta = "nocode", dpd_sutta_var = "orphan", dpd_code = "" },
    row{ dpd_sutta = "aṭṭhikamahapphalasutta", dpd_code = "SN46.57",
        dpd_sutta_var = "aññataraphalasutta, phāsuvihārasutta, mahatthasutta; yogakkhemasutta, saṃvegasutta" },
}

local function fixture(missing)
    local db = { reads = {} }
    function db:query(sql, params)
        self.reads[#self.reads + 1] = sql
        if sql:find("PRAGMA", 1, true) then
            local columns = {}
            if missing ~= true then
                for name in pairs(rows[1]) do
                    if name ~= missing then columns[#columns + 1] = { name = name } end
                end
            end
            return columns
        end
        if sql:find("SELECT 1", 1, true) then
            for _, r in ipairs(rows) do if r.dpd_sutta == params[1] and r.dpd_code ~= "" then return { { 1 } } end end
            return {}
        end
        if sql:find("SELECT dpd_sutta, dpd_sutta_var", 1, true) then
            local out = {}
            for _, r in ipairs(rows) do if r.dpd_code ~= "" then out[#out + 1] = r end end
            return out
        end
        local label = sql:match("^SELECT (dpd_code, .-) FROM sutta_info WHERE dpd_sutta = %?$")
        if label then
            -- The link label reads only the fields it needs.
            for _, r in ipairs(rows) do
                if r.dpd_sutta == params[1] then
                    local narrow = {}
                    for column in label:gmatch("[%w_]+") do narrow[column] = r[column] end
                    return { narrow }
                end
            end
            return {}
        end
        assert(sql:find("SELECT * FROM sutta_info WHERE dpd_sutta = ?", 1, true), sql)
        for _, r in ipairs(rows) do if r.dpd_sutta == params[1] then return { r } end end
        return {}
    end
    return Sutta.new(db), db
end

local function fields(record)
    local out = {}
    for _, section in ipairs(record.sections) do
        for _, field in ipairs(section.fields) do out[section.title .. "/" .. field.label] = field.value end
    end
    return out
end

describe("sutta information", function()
    it("labels the link with upstream's sutta type", function()
        local s = fixture()
        assert.equal("sutta", s:has("brahmajālasutta"))
        assert.equal("vagga", s:has("pāthikavaggapāḷi"))
        assert.equal("saṃyutta", s:has("devatāsaṃyutta"))
        assert.equal("nipāta", s:has("ekakanipāta"))
        assert.equal("paṇṇāsaka", s:has("mūlapaṇṇāsapāḷi"))
        assert.is_nil(s:has("dhamma 1.01"))
    end)

    it("applies the type rules the release data does not exercise", function()
        assert.equal("vagga", Sutta.label(Sutta.types(row{ dpd_sutta = "x", dpd_sutta_var = "paṭhamavaggo", dpd_code = "A1.1" })))
        -- A range code is never a whole saṃyutta or nipāta.
        assert.equal("sutta", Sutta.label(Sutta.types(row{ dpd_sutta = "devatāsaṃyutta", dpd_code = "SN1-2" })))
        assert.equal("sutta", Sutta.label(Sutta.types(row{ dpd_sutta = "ekakanipāta", dpd_code = "AN1.1" })))
        assert.equal("saṃyutta", Sutta.label(Sutta.types(row{ dpd_sutta = "devatāsaṃyutta 2", dpd_code = "SN1" })))
        assert.equal("vagga", Sutta.label(Sutta.types(row{ dpd_sutta = "x", dpd_code = "SN1-3", sc_vagga = "v" })))
    end)

    it("resolves aliases on expansion, keeps every record an alias names and skips rows without a code", function()
        local s = fixture()
        assert.equal("vagga", s:has("pāṭikavagga"))
        assert.same({ "pāthikavaggapāḷi" }, s:resolveAlias("pāṭikavagga"))
        assert.same({ "first", "second" }, s:resolveAlias("shared"))
        -- A canonical name stays itself even when another row lists it as an alias.
        assert.same({ "first" }, s:resolveAlias("first"))
        assert.is_nil(s:has("orphan"))
        assert.is_nil(s:has("nocode"))
        assert.equal(2, #s:info("shared").records)
    end)

    it("builds the alias table once and caches positive and negative answers", function()
        local s, db = fixture()
        s:has("dhamma 1.01"); s:has("pāṭikavagga")
        local before = #db.reads
        s:has("dhamma 1.01"); s:has("pāṭikavagga")
        assert.equal(before, #db.reads)
        local builds = 0
        for _, sql in ipairs(db.reads) do if sql:find("^SELECT dpd_sutta, dpd_sutta_var") then builds = builds + 1 end end
        assert.equal(1, builds)
    end)

    it("resolves aliases separated by commas or semicolons", function()
        local s = fixture()
        for _, alias in ipairs({ "aññataraphalasutta", "phāsuvihārasutta", "mahatthasutta", "yogakkhemasutta", "saṃvegasutta" }) do
            assert.equal("sutta", s:has(alias))
            assert.equal("aṭṭhikamahapphalasutta", s:info(alias).records[1].name)
        end
    end)

    it("names the canonical record when a single alias opens it", function()
        local s = fixture()
        local html = Render.render({query="pāṭikavagga",sutta=s:info("pāṭikavagga")}, {})
        assert.truthy(html:find("DPD record: pāthikavaggapāḷi · DN24-34", 1, true))
        html = Render.render({query="brahmajālasutta",sutta=s:info("brahmajālasutta")}, {})
        assert.is_nil(html:find("DPD record:", 1, true))
    end)

    it("omits empty fields and the rows upstream hides for vaggas and saṃyuttas", function()
        local s = fixture()
        local sutta = fields(s:info("brahmajālasutta").records[1])
        assert.equal("1. Brahmajālasuttaṃ", sutta["Chaṭṭha Saṅgāyana Tipiṭaka (CST)/Sutta"])
        assert.equal("dn-1.json", sutta["Buddha Jayanti Tipiṭaka (BJT)/Filename"])
        assert.equal("On <i>sīla</i>.", sutta["SuttaCentral/Blurb"])
        assert.equal("D i 1,7", sutta["Pali Text Society/PTS"])
        assert.equal("T1", sutta["Parallels/Taisho"])
        assert.is_nil(sutta["Chaṭṭha Saṅgāyana Tipiṭaka (CST)/Book"])
        local vagga = fields(s:info("pāṭikavagga").records[1])
        assert.equal("Pāthikavagga", vagga["Chaṭṭha Saṅgāyana Tipiṭaka (CST)/Vagga"])
        assert.is_nil(vagga["Chaṭṭha Saṅgāyana Tipiṭaka (CST)/Sutta"])
        assert.is_nil(vagga["Pali Text Society/PTS"])
        local samyutta = fields(s:info("devatāsaṃyutta").records[1])
        assert.equal("Sagāthā", samyutta["Chaṭṭha Saṅgāyana Tipiṭaka (CST)/Book"])
        assert.is_nil(samyutta["Chaṭṭha Saṅgāyana Tipiṭaka (CST)/Vagga"])
        assert.is_nil(samyutta["SuttaCentral/Title"])
    end)

    it("is unavailable without a sutta_info table", function()
        local s = fixture(true)
        assert.is_nil(s:has("brahmajālasutta"))
        assert.is_nil(s:info("brahmajālasutta"))
    end)

    it("disables incomplete sutta schemas once, without attempting data reads", function()
        for _, column in ipairs({ "dpd_sutta", "dpd_code", "dpd_sutta_var", "cst_vagga", "sc_vagga", "bjt_vagga" }) do
            local s, db = fixture(column)
            assert.is_nil(s:has("brahmajālasutta"))
            assert.is_nil(s:has("pāṭikavagga"))
            assert.is_nil(s:info("brahmajālasutta"))
            assert.equal(1, #db.reads)
        end
    end)

    it("renders the link on the entry and the panel", function()
        local html = Render.render({ query = "x", senses = { { id = 7, lemma_1 = "brahmajālasutta", pos = "masc" } } },
            { expanded = { [7] = true }, details = { [7] = { sutta_kind = "sutta" } }, analyses = {} })
        assert.truthy(html:find("dpd:detail%-sutta/7"))
        assert.truthy(html:find(">Sutta information</a>", 1, true))
        assert.falsy(html:find("Sutta information · sutta", 1, true))
        local vagga = Render.render({ query = "x", senses = { { id = 7, lemma_1 = "brahmajālasutta", pos = "masc" } } },
            { expanded = { [7] = true }, details = { [7] = { sutta_kind = "vagga" } }, analyses = {} })
        assert.truthy(vagga:find("Sutta information · vagga", 1, true))
        local s = fixture()
        local panel = Render.render({ query = "brahmajālasutta", sutta = s:info("brahmajālasutta") }, { analyses = {} })
        assert.truthy(panel:find("<i>Title:</i> <i>The Divine Net</i>", 1, true))
        assert.truthy(panel:find('<p class="section">Parallels</p>', 1, true))
        -- The title bar names the sutta, and source file paths cannot be opened.
        assert.falsy(panel:find("<h3", 1, true))
        assert.falsy(panel:find("<i>File", 1, true))
    end)
end)
