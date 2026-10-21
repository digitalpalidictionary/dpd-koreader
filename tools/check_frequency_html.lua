-- Compare frequency tables with DPD's generated freq_html from the full
-- database of the same release: every book row's values and row spans.
-- ./luajit <plugin>/tools/check_frequency_html.lua <plugin> <dpd-mobile.db> <dpd.db>
require("setupkoenv")
local root, mobile_path, full_path = assert(arg[1]), assert(arg[2]), assert(arg[3])
package.path = root .. "/?.lua;" .. package.path
local DB = require("dpd/db")
local Frequency = require("dpd/frequency")
local mobile, full = DB.new(mobile_path), DB.new(full_path)
assert(mobile.info.dpd_release_version == full.info.dpd_release_version, "use databases of the same release")
local frequency = Frequency.new(mobile)
local order = {}
for _, corpus in ipairs(Frequency.corpora) do
    for _, column in ipairs(corpus.columns) do order[#order + 1] = column end
end
local checked, compounds, failures = 0, 0, {}
local function fail(id, message) if #failures < 20 then failures[#failures + 1] = id .. ": " .. message end end
for _, row in ipairs(full:query("SELECT id, freq_html FROM dpd_headwords WHERE freq_html != ''")) do
    local result = frequency:table(row.id)
    local body = row.freq_html:match("<tbody>(.-)</tbody>")
    if not body then
        if not result.only_compounds then fail(row.id, "DPD shows no table, generated one has data") end
        compounds = compounds + 1
    elseif result.error or result.only_compounds then
        fail(row.id, "no generated table: " .. tostring(result.error))
    else
        local expected = {}
        for tr in body:gmatch("<tr>(.-)</tr>") do
            local label = tr:match("<th>%s*(.-)%s*</th>")
            if label then
                local cells = {}
                for attributes, text in tr:gmatch("<td([^>]*)>%s*(.-)%s*</td>") do
                    if not attributes:find('class="gap"', 1, true) and text ~= "" then
                        cells[#cells + 1] = text .. "/" .. (attributes:match('rowspan="(%d+)"') or "1")
                    end
                end
                expected[#expected + 1] = label .. ": " .. table.concat(cells, " ")
            end
        end
        local generated = {}
        for _, section in ipairs(result.sections) do
            for _, line in ipairs(section.rows) do
                local cells = {}
                for _, column in ipairs(order) do
                    local cell = line.cells[column]
                    if cell then cells[#cells + 1] = cell.value .. "/" .. cell.rowspan end
                end
                generated[#generated + 1] = line.label .. ": " .. table.concat(cells, " ")
            end
        end
        if #generated ~= #expected then fail(row.id, #generated .. " rows ≠ " .. #expected) end
        for i = 1, math.min(#generated, #expected) do
            if generated[i] ~= expected[i] then fail(row.id, generated[i] .. " ≠ " .. expected[i]); break end
        end
        checked = checked + 1
    end
end
for _, message in ipairs(failures) do print("FAIL " .. message) end
assert(#failures == 0, "frequency tables differ from DPD's")
print(string.format("PASS: %d frequency tables match DPD's generated HTML; %d compound-only entries (%s)",
    checked, compounds, mobile.info.dpd_release_version))
mobile:close(); full:close()
