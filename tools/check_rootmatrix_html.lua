-- Compare root matrices with DPD's generated root_matrix HTML from the full
-- database of the same release: for every root, the categories and rows in
-- order and the headwords in each row. Rows are compared as sets: the stored
-- HTML keeps entries added later at the end of a row, while the plugin
-- lists each row in Pāḷi alphabetical order.
-- ./luajit <plugin>/tools/check_rootmatrix_html.lua <plugin> <dpd-mobile.db> <dpd.db>
require("setupkoenv")
local root, mobile_path, full_path = assert(arg[1]), assert(arg[2]), assert(arg[3])
package.path = root .. "/?.lua;" .. package.path
local DB = require("dpd/db")
local RootMatrix = require("dpd/rootmatrix")
local mobile, full = DB.new(mobile_path), DB.new(full_path)
assert(mobile.info.dpd_release_version == full.info.dpd_release_version, "use databases of the same release")
local matrix = RootMatrix.new(mobile)

local function sorted(list) table.sort(list); return table.concat(list, ", ") end
local function expected(html)
    local out, group = {}, nil
    for th, label, words in html:gmatch("<tr>(.-)<td><b>(.-)</b></td><td>(.-)</td></tr>") do
        local name = th:match("<th colspan='2'>(.-)</th>")
        if name then group = name end
        local list = {}
        for word in (words .. ", "):gmatch("(.-), ") do list[#list + 1] = word end
        out[#out + 1] = group .. "/" .. label .. ": " .. sorted(list)
    end
    return out
end
local function actual(result)
    local out = {}
    for _, group in ipairs(result.groups) do
        for _, row in ipairs(group.rows) do
            local list = {}
            for _, item in ipairs(row.items) do list[#list + 1] = RootMatrix.superscript(item.lemma) end
            out[#out + 1] = group.name .. "/" .. row.label .. ": " .. sorted(list)
        end
    end
    return out
end

local checked, words, failures, slowest, slowest_root = 0, 0, {}, 0, ""
for _, row in ipairs(full:query("SELECT root, root_matrix FROM dpd_roots WHERE root_matrix != ''")) do
    local started = os.clock()
    local result = matrix:matrix(row.root)
    local ms = (os.clock() - started) * 1000
    if ms > slowest then slowest, slowest_root = ms, row.root end
    local want, got = expected(row.root_matrix), actual(result)
    local same = #want == #got
    for i = 1, math.max(#want, #got) do
        if want[i] ~= got[i] then
            same = false
            failures[#failures + 1] = row.root .. "\n  want " .. tostring(want[i]) .. "\n  got  " .. tostring(got[i])
            break
        end
    end
    checked, words = checked + 1, words + result.total
end
print(string.format("Release %s: %d roots, %d headwords placed; slowest %s %.1f ms",
    tostring(mobile.info.dpd_release_version), checked, words, slowest_root, slowest))
for i = 1, math.min(#failures, 10) do print("FAIL " .. failures[i]) end
assert(#failures == 0, #failures .. " roots differ")
print("PASS: every root matrix matches DPD's categories, rows and headwords")
