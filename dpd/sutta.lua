-- Sutta information behind a link on expanded entries, ported from DPD's
-- sutta panel (exporter/webapp templates/dpd_headword.html and SuttaInfo in
-- db/models.py). A headword qualifies when its lemma_1 is a sutta's
-- dpd_sutta or one of its semicolon/comma-separated dpd_sutta_var aliases (267 aliases
-- in v0.4.20260926 are themselves headwords). Web links are omitted; file
-- paths stay as text.
-- SPDX-License-Identifier: MIT
local Sutta = {}
Sutta.__index = Sutta

local CACHE = 8
local KNOWN = 256
local label_columns = { "dpd_code", "dpd_sutta", "dpd_sutta_var", "cst_vagga", "sc_vagga", "bjt_vagga" }

-- Upstream conditions: "samyutta" hides the vagga and sutta rows, "vagga"
-- hides the sutta rows, "whole" hides the PTS, catalogue and parallels.
local sections = {
    { title = "Chaṭṭha Saṅgāyana Tipiṭaka (CST)", fields = {
        { "cst_code", "CST Code" }, { "cst_nikaya", "Nikāya" }, { "cst_book", "Book" },
        { "cst_section", "Section" }, { "cst_vagga", "Vagga", "samyutta" },
        { "cst_sutta", "Sutta", "vagga" }, { "cst_paranum", "Paragraph" }, { "cst_file", "File" } } },
    { title = "CST Page Numbers in Printed Editions", fields = {
        { "cst_m_page", "Myanmar" }, { "cst_t_page", "Thai" }, { "cst_v_page", "VRI" }, { "cst_p_page", "PTS" } } },
    { title = "SuttaCentral", fields = {
        { "sc_code", "SC Code" }, { "sc_book", "Book" }, { "sc_vagga", "Vagga", "samyutta" },
        { "sc_sutta", "Sutta", "vagga" }, { "sc_eng_sutta", "Title", "samyutta", true },
        { "sc_blurb", "Blurb", "vagga", true }, { "sc_file_path", "File" } } },
    { title = "Buddha Jayanti Tipiṭaka (BJT)", fields = {
        { "bjt_sutta_code", "Sutta Code" }, { "bjt_piṭaka", "Piṭaka" }, { "bjt_nikāya", "Nikāya" },
        { "bjt_major_section", "Major Section" }, { "bjt_book", "Book" },
        { "bjt_minor_section", "Minor Section" }, { "bjt_vagga", "Vagga", "samyutta" },
        { "bjt_sutta", "Sutta", "vagga" }, { "bjt_book_id", "Book ID" },
        { "bjt_page_num", "Page Number" }, { "bjt_filename", "Filename" } } },
    { title = "Pali Text Society", whole = true, fields = { { "dv_pts", "PTS" } } },
    { title = "Dhamma Vinaya Tools: Sutta Catalogue", whole = true, fields = {
        { "dv_main_theme", "General Theme" }, { "dv_subtopic", "Particular Topic" },
        { "dv_summary", "Summary" }, { "dv_key_excerpt1", "Key Excerpts 1" },
        { "dv_key_excerpt2", "Key Excerpts 2" }, { "dv_similes", "Similes" },
        { "dv_stage", "Stage of Training" }, { "dv_training", "Training In" },
        { "dv_aspect", "Type of Teaching" }, { "dv_teacher", "Teacher" },
        { "dv_audience", "Audience" }, { "dv_method", "Method of Teaching" },
        { "dv_length", "Sutta Length" }, { "dv_prominence", "Prominence" },
        { "dv_suggested_suttas", "Suggested Reading" } } },
    { title = "Parallels", whole = true, fields = {
        { "dv_nikayas_parallels", "Nikāyas" }, { "dv_āgamas_parallels", "Āgamas" },
        { "dv_taisho_parallels", "Taisho" }, { "dv_sanskrit_parallels", "Sanskrit" },
        { "dv_vinaya_parallels", "Vinaya" }, { "dv_others_parallels", "Others" } } },
}
Sutta.sections = sections

function Sutta.new(db)
    return setmetatable({ db = db, aliases = nil, known = {}, known_order = {}, cache = {}, order = {} }, Sutta)
end

local function text(value) return value == nil and "" or tostring(value) end
local function names(row) return { text(row.dpd_sutta), text(row.dpd_sutta_var) } end
local function any(row, test)
    for _, name in ipairs(names(row)) do if name ~= "" and test(name) then return true end end
    return false
end
local function plain(s, needle) return s:find(needle, 1, true) ~= nil end

-- SuttaInfo.is_samyutta / is_nipata / is_vagga / is_pannasaka.
function Sutta.types(row)
    local code, name = text(row.dpd_code), text(row.dpd_sutta)
    local whole = name ~= "" and code ~= "" and not plain(code, ".") and not plain(code, "-")
    return {
        samyutta = whole and (name:gsub(" %d+$", "")):sub(-#"saṃyutta") == "saṃyutta",
        nipata = whole and any(row, function(n) return plain(n, "nipāta") end),
        vagga = any(row, function(n) return plain(n, "vagga") or plain(n, "vaggo") end)
            or (plain(code, "-") and (text(row.cst_vagga) ~= "" or text(row.sc_vagga) ~= ""
                or text(row.bjt_vagga) ~= "")),
        pannasaka = any(row, function(n) return plain(n, "paṇṇāsapāḷi") or plain(n, "paṇṇāsaka") end),
    }
end

--- The link label upstream shows on the entry.
function Sutta.label(types)
    if types.samyutta then return "saṃyutta" elseif types.pannasaka then return "paṇṇāsaka"
    elseif types.vagga then return "vagga" elseif types.nipata then return "nipāta" end
    return "sutta"
end

-- Older or partial databases may lack the table or the fields the link needs.
function Sutta:_ready()
    if self.ready == nil then
        local ok, rows = pcall(self.db.query, self.db, "PRAGMA table_info(sutta_info)")
        local columns = {}
        if ok then for _, row in ipairs(rows) do columns[row.name] = true end end
        self.ready = true
        for _, column in ipairs(label_columns) do
            if not columns[column] then self.ready = false; break end
        end
    end
    return self.ready
end

-- alias → list of canonical dpd_sutta, built once per database (one read of
-- the two name columns, ~5,000 rows) on the first expansion that is not a
-- canonical name. A new database gets a new Sutta reader.
function Sutta:_aliases()
    if self.aliases then return self.aliases end
    local map = {}
    for _, row in ipairs(self.db:query("SELECT dpd_sutta, dpd_sutta_var FROM sutta_info WHERE dpd_code != ''")) do
        for alias in text(row.dpd_sutta_var):gmatch("[^;,]+") do
            alias = alias:match("^%s*(.-)%s*$")
            if alias ~= "" then
                local list = map[alias] or {}
                local seen = false
                for _, existing in ipairs(list) do seen = seen or existing == row.dpd_sutta end
                if not seen then list[#list + 1] = row.dpd_sutta end
                map[alias] = list
            end
        end
    end
    self.aliases = map
    return map
end

--- Canonical dpd_sutta keys for a name: itself when canonical, else every
--- record the alias names (sorted). Empty when none.
function Sutta:resolveAlias(name)
    name = text(name)
    if name == "" or not self:_ready() then return {} end
    if #self.db:query("SELECT 1 FROM sutta_info WHERE dpd_sutta = ? AND dpd_code != ''", { name }) > 0 then
        return { name }
    end
    local list = {}
    for _, key in ipairs(self:_aliases()[name] or {}) do list[#list + 1] = key end
    table.sort(list)
    return list
end

local function remember(cache, order, limit, key, value)
    if cache[key] == nil then
        if #order >= limit then cache[table.remove(order, 1)] = nil end
        order[#order + 1] = key
    end
    cache[key] = value
end

local function fetch(db, key)
    return db:query("SELECT * FROM sutta_info WHERE dpd_sutta = ?", { key })[1]
end

--- The link label for a headword with sutta information, or nil. Positive
--- and negative results are cached (bounded).
function Sutta:has(lemma)
    lemma = text(lemma)
    local known = self.known[lemma]
    if known ~= nil then return known or nil end
    local keys = self:resolveAlias(lemma)
    local label = false
    if #keys > 0 then
        -- Only the fields the label needs; the panel reads the rest when opened.
        local row = self.db:query("SELECT " .. table.concat(label_columns, ", ")
            .. " FROM sutta_info WHERE dpd_sutta = ?", { keys[1] })[1]
        label = row and Sutta.label(Sutta.types(row)) or false
    end
    remember(self.known, self.known_order, KNOWN, lemma, label)
    return label or nil
end

local function value(row, column)
    -- Keep DPD's italics but drop their attributes so the renderer keeps them.
    local v = text(row[column]):gsub("<(%/?)i [^>]*>", "<%1i>")
    if column == "bjt_filename" and v ~= "" then v = v .. ".json" end
    return v
end

local function record(row)
    local types = Sutta.types(row)
    local out = { name = row.dpd_sutta, code = text(row.dpd_code), label = Sutta.label(types), sections = {} }
    for _, section in ipairs(sections) do
        if not (section.whole and (types.vagga or types.samyutta)) then
            local fields = {}
            for _, field in ipairs(section.fields) do
                local column, label, hide, italic = field[1], field[2], field[3], field[4]
                local hidden = (hide == "samyutta" and types.samyutta)
                    or (hide == "vagga" and (types.vagga or types.samyutta))
                local v = value(row, column)
                if v ~= "" and not hidden then fields[#fields + 1] = { label = label, value = v, italic = italic } end
            end
            if #fields > 0 then out.sections[#out.sections + 1] = { title = section.title, fields = fields } end
        end
    end
    return out
end

--- The view model for a headword, or nil when it has no sutta information.
--- Cached and shared: callers must not change it.
--- @return table { lemma, records = { { name, code, label, sections = { { title,
---   fields = { { label, value, italic } } } } } } }
function Sutta:info(lemma)
    lemma = text(lemma)
    if self.cache[lemma] then return self.cache[lemma] end
    local result = { lemma = lemma, records = {} }
    for _, key in ipairs(self:resolveAlias(lemma)) do
        local row = fetch(self.db, key)
        if row then result.records[#result.records + 1] = record(row) end
    end
    if #result.records == 0 then return nil end
    remember(self.cache, self.order, CACHE, lemma, result)
    return result
end

return Sutta
