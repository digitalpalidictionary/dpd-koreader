-- Compare root details with DPD's generated root_info HTML from the full
-- database of the same release: every row label and value for every root.
-- Missing Sanskrit roots use a single dash instead of upstream's empty parentheses.
-- ./luajit <plugin>/tools/check_rootinfo_html.lua <plugin> <dpd-mobile.db> <dpd.db>
require("setupkoenv")
local root, mobile_path, full_path = assert(arg[1]), assert(arg[2]), assert(arg[3])
package.path = root .. "/?.lua;" .. package.path
local DB = require("dpd/db")
local RootInfo = require("dpd/rootinfo")
local mobile, full = DB.new(mobile_path), DB.new(full_path)
assert(mobile.info.dpd_release_version == full.info.dpd_release_version, "use databases of the same release")
local info = RootInfo.new(mobile)
local function strip(html) return (html:gsub("<[^>]+>", ""):gsub("&amp;", "&")) end
local function set(list)
    local out = {}
    for item in (list .. ", "):gmatch("(.-), ") do out[#out + 1] = item end
    table.sort(out)
    return table.concat(out, ", ")
end
local checked, failures = 0, {}
for _, row in ipairs(full:query("SELECT root, root_info, sanskrit_root FROM dpd_roots WHERE root_info != ''")) do
    local expected = {}
    for label, value in row.root_info:gmatch("<th>(.-):</th><td>(.-)</td>") do
        local missing_sanskrit = label:lower() == "sanskrit root"
            and (row.sanskrit_root == "" or row.sanskrit_root == "-")
        expected[#expected + 1] = { label = label:lower(), value = missing_sanskrit and "-" or strip(value) }
    end
    local result = info:details(row.root)
    local ok = result and #result.rows == #expected
    for i, line in ipairs(ok and result.rows or {}) do
        local parts = {}
        for _, part in ipairs(line.parts) do parts[#parts + 1] = part.text end
        local value, want = strip(table.concat(parts)), expected[i].value
        if line.label:match("^Bases?$") then value, want = set(value), set(want) end
        if line.label:lower() ~= expected[i].label or value ~= want then
            ok = false
            if #failures < 20 then
                failures[#failures + 1] = row.root .. ": " .. line.label .. " “" .. value .. "” ≠ "
                    .. expected[i].label .. " “" .. want .. "”"
            end
        end
    end
    if not ok and #failures < 20 and not (result and #result.rows == #expected) then
        failures[#failures + 1] = row.root .. ": row count"
    end
    checked = checked + 1
end
for _, message in ipairs(failures) do print("FAIL " .. message) end
assert(#failures == 0, "root details differ from DPD's root_info")
print(string.format("PASS: %d roots match DPD's generated root info (%s)", checked, mobile.info.dpd_release_version))
mobile:close(); full:close()
