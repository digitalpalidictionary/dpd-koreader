-- Compare generated tables with DPD's own generated inflection HTML, cell by
-- cell: column headers, row labels, cell grammar and the exact forms in order.
-- Needs a mobile and a full database of the same release:
-- ./luajit <plugin>/tools/check_inflection_html.lua <plugin> <dpd-mobile.db> <dpd.db>
require("setupkoenv")
local root, mobile_path, full_path = assert(arg[1]), assert(arg[2]), assert(arg[3])
package.path = root .. "/?.lua;" .. package.path
local DB = require("dpd/db")
local Inflection = require("dpd/inflection")
local mobile, full = DB.new(mobile_path), DB.new(full_path)
assert(mobile.info.dpd_release_version == full.info.dpd_release_version,
    "use databases of the same release: " .. tostring(mobile.info.dpd_release_version)
    .. " and " .. tostring(full.info.dpd_release_version))
local inflection = Inflection.new(mobile)

local function text(html) return (html:gsub("<[^>]+>", "")) end
-- Parse DPD's table into headers and rows of { label, cells = { [header] = { title, forms } } }.
local function parse(html)
    local tbl = html:match("<table class='inflection'>(.-)</table>")
    if not tbl then return nil end
    local headers, rows, first = {}, {}, true
    for row in tbl:gmatch("<tr>(.-)</tr>") do
        if first then
            for header in row:gmatch("<th>(.-)</th>") do headers[#headers + 1] = text(header) end
            table.remove(headers, 1) -- the empty corner cell
            first = false
        else
            local label = text(row:match("^<th>(.-)</th>") or "")
            local cells, index = {}, 0
            for title, body in row:gmatch("<td title='(.-)'>(.-)</td>") do
                index = index + 1
                local forms = {}
                for form in (body .. "<br>"):gmatch("(.-)<br>") do
                    form = text(form)
                    if form ~= "" then forms[#forms + 1] = form end
                end
                cells[headers[index]] = { title = title, forms = forms }
            end
            rows[#rows + 1] = { label = label, cells = cells }
        end
    end
    return headers, rows
end

local checked, extra, failures = 0, 0, {}
local function fail(lemma, message)
    if #failures < 20 then failures[#failures + 1] = lemma .. ": " .. message end
end
local html_by_id = {}
for _, row in ipairs(full:query("SELECT id, inflections_html FROM dpd_headwords WHERE inflections_html != ''")) do
    html_by_id[row.id] = row.inflections_html
end
for _, row in ipairs(mobile:query("SELECT id, lemma_1, stem, pattern FROM dpd_headwords")) do
    local html = html_by_id[row.id]
    if Inflection.available(row) then
        local headers, rows = nil, nil
        if html then headers, rows = parse(html) end
        if not headers then
            extra = extra + 1
        else
            local result = inflection:paradigm(row, row.lemma_1, nil)
            local grid, labels = {}, {}
            for _, line in ipairs(rows) do grid[line.label] = line.cells; labels[#labels + 1] = line.label end
            local generated_headers = {}
            for _, section in ipairs(result.sections) do
                for j, header in ipairs(section.headers) do
                    generated_headers[#generated_headers + 1] = header
                    local present = {}
                    for _, line in ipairs(section.rows) do
                        present[line.label] = true
                        local expected = (grid[line.label] or {})[header]
                        local cell = line.cells[j]
                        local forms = {}
                        for _, form in ipairs(cell.forms) do forms[#forms + 1] = form.text end
                        if not expected then
                            fail(row.lemma_1, "no " .. line.label .. " / " .. header .. " cell in DPD's table")
                        else
                            if table.concat(forms, "|") ~= table.concat(expected.forms, "|") then
                                fail(row.lemma_1, line.label .. " / " .. header .. ": " .. table.concat(forms, ",")
                                    .. " ≠ " .. table.concat(expected.forms, ","))
                            end
                            if #forms > 0 and cell.grammar ~= expected.title then
                                fail(row.lemma_1, line.label .. " / " .. header .. " grammar " .. cell.grammar
                                    .. " ≠ " .. expected.title)
                            end
                        end
                    end
                    -- Rows the section omits must be empty in DPD's table too.
                    for _, label in ipairs(labels) do
                        local expected = grid[label][header]
                        if not present[label] and expected and #expected.forms > 0 then
                            fail(row.lemma_1, "omitted non-empty " .. label .. " / " .. header)
                        end
                    end
                end
            end
            if table.concat(generated_headers, "|") ~= table.concat(headers, "|") then
                fail(row.lemma_1, "headers " .. table.concat(generated_headers, ",") .. " ≠ " .. table.concat(headers, ","))
            end
            checked = checked + 1
        end
    end
end
for _, message in ipairs(failures) do print("FAIL " .. message) end
assert(#failures == 0, "generated tables differ from DPD's")
print(string.format("PASS: %d tables match DPD's generated HTML cell by cell (%s); %d patterned headwords have no DPD table",
    checked, tostring(mobile.info.dpd_release_version), extra))
mobile:close(); full:close()
