local Json = require("json")
local Inflection = {}
Inflection.__index = Inflection

-- Paradigms are generated on demand from a headword's stem and its pattern's
-- template, as DPD's own exporter does. Templates are small (largest ~2 KB);
-- keep only a few decoded ones.
local MAX_TEMPLATE, TEMPLATE_CACHE = 65536, 8
local DAMAGE = "Unreadable DPD inflection data. Replace the database with a fresh DPD mobile download."
local section_titles = { masc="Masculine", fem="Feminine", neut="Neuter", nt="Neuter",
    reflexive="Reflexive", [""]="Active" }

local function present(value) return type(value) == "string" and value:match("%S") ~= nil end

function Inflection.new(db)
    return setmetatable({ db = db, templates = {}, order = {} }, Inflection)
end

-- A stem of "-" marks an indeclinable. "!" (the headword is itself an
-- inflected form) and "*" (the template holds whole irregular words) are
-- markers, not letters of the stem.
function Inflection.available(detail)
    return type(detail) == "table" and present(detail.pattern) and present(detail.stem)
        and detail.stem ~= "-"
end

local verbal = { pr=true, aor=true, fut=true, opt=true, imp=true, cond=true, perf=true, imperf=true }

-- Pattern names end with a part of speech ("ati pr", "aor irreg", "a masc").
function Inflection.kind(pattern)
    for word in tostring(pattern or ""):gmatch("%S+") do
        if verbal[word] then return "Conjugation" end
    end
    return "Declension"
end

function Inflection:_template(pattern)
    if self.templates[pattern] then return self.templates[pattern] end
    local ok, value = pcall(function()
        local rows = self.db:query('SELECT "like",data FROM inflection_templates WHERE pattern = ? LIMIT 1', { pattern })
        local row = rows[1]
        if not row then return { missing = true } end
        local raw = row.data
        assert(type(raw) == "string" and #raw <= MAX_TEMPLATE, "Invalid inflection template")
        local decoded, position, decode_error = Json.decode(raw)
        assert(not decode_error and (type(position) ~= "number" or raw:sub(position):match("^%s*$")),
            "Invalid inflection template")
        -- Every row is [label], then pairs of [endings...], [grammar].
        assert(type(decoded) == "table" and #decoded >= 2, "Invalid inflection template")
        local width = #decoded[1]
        assert(width >= 3 and width % 2 == 1, "Invalid inflection template")
        for _, line in ipairs(decoded) do
            assert(type(line) == "table" and #line == width, "Invalid inflection template")
            for _, cell in ipairs(line) do
                assert(type(cell) == "table", "Invalid inflection template")
                for _, text in ipairs(cell) do assert(type(text) == "string", "Invalid inflection template") end
            end
        end
        return { like = type(row.like) == "string" and row.like or "", rows = decoded }
    end)
    value = ok and value or { error = DAMAGE }
    if #self.order >= TEMPLATE_CACHE then self.templates[table.remove(self.order, 1)] = nil end
    self.order[#self.order + 1] = pattern
    self.templates[pattern] = value
    return value
end

-- Group adjacent columns by their gender/voice prefix ("masc sg", "masc pl").
-- Single-column groups stay together in one section with full labels.
local function sections(headers)
    local groups = {}
    for index, header in ipairs(headers) do
        local prefix, number = header:match("^(.-)%s*(%S+)$")
        prefix = prefix or ""
        local last = groups[#groups]
        if not last or last.prefix ~= prefix then
            last = { prefix = prefix, columns = {} }
            groups[#groups + 1] = last
        end
        last.columns[#last.columns + 1] = { index = index, label = number or header, full = header }
    end
    local split = #groups > 1
    for _, group in ipairs(groups) do if #group.columns < 2 then split = false end end
    if not split then
        local columns = {}
        for index, header in ipairs(headers) do columns[index] = { index = index, label = header, full = header } end
        return { { title = nil, columns = columns } }
    end
    for _, group in ipairs(groups) do group.title = section_titles[group.prefix] or group.prefix end
    return groups
end

-- Returns a view model of the headword's complete paradigm. Each distinct form
-- is listed once in `forms` so that its cells can link to an exact lookup.
function Inflection:paradigm(detail, lemma, selected)
    local result = { lemma = lemma, pattern = detail and detail.pattern, sections = {}, forms = {} }
    if not Inflection.available(detail) then result.error = "No declension or conjugation for this entry."; return result end
    local template = self:_template(detail.pattern)
    if template.error or template.missing then
        result.error = template.error or ("DPD has no inflection template “" .. detail.pattern .. "”.")
        return result
    end
    result.like = template.like
    local stem = detail.stem:gsub("[!*]", "")
    local rows = template.rows
    local headers = {}
    for column = 2, #rows[1], 2 do headers[#headers + 1] = rows[1][column][1] or "" end
    result.kind = Inflection.kind(detail.pattern)
    local form_index, selected_count = {}, 0
    local lines = {}
    for line = 2, #rows do
        local cells = {}
        for column = 2, #rows[line], 2 do
            local forms = {}
            for _, ending in ipairs(rows[line][column]) do
                if ending ~= "" then
                    local form = stem .. ending
                    if not form_index[form] then
                        result.forms[#result.forms + 1] = form
                        form_index[form] = #result.forms
                    end
                    local hit = form == selected
                    if hit then selected_count = selected_count + 1 end
                    forms[#forms + 1] = { text = form, ending = ending, index = form_index[form], selected = hit }
                end
            end
            cells[#cells + 1] = { forms = forms, grammar = rows[line][column + 1][1] or "" }
        end
        lines[#lines + 1] = { label = rows[line][1][1] or "", cells = cells }
    end
    for _, section in ipairs(sections(headers)) do
        -- `headers` keeps the template's full column names ("masc sg").
        local out = { title = section.title, columns = {}, headers = {}, rows = {} }
        for _, column in ipairs(section.columns) do
            out.columns[#out.columns + 1] = column.label
            out.headers[#out.headers + 1] = column.full
        end
        for _, line in ipairs(lines) do
            local cells, filled = {}, false
            for _, column in ipairs(section.columns) do
                local cell = line.cells[column.index]
                cells[#cells + 1] = cell
                if #cell.forms > 0 then filled = true end
            end
            -- e.g. "in comps" has a form only in the first column.
            if filled then out.rows[#out.rows + 1] = { label = line.label, cells = cells } end
        end
        result.sections[#result.sections + 1] = out
    end
    result.selected = selected_count > 0 and selected or nil
    result.selected_count = selected_count
    return result
end

return Inflection
