-- Check sutta information against DPD's rules for a release: which
-- headwords get the link (cache_load.load_sutta_info_set), the link label
-- (SuttaInfo.is_samyutta/is_pannasaka/is_vagga/is_nipata, restated here
-- independently of dpd/sutta.lua) and that no panel shows an empty field.
-- Comma-separated release aliases are accepted in addition to upstream's semicolons.
-- ./luajit <plugin>/tools/check_sutta.lua <plugin> <dpd-mobile.db>
require("setupkoenv")
local root, path = assert(arg[1]), assert(arg[2])
package.path = root .. "/?.lua;" .. package.path
local db = require("dpd/db").new(path)
local reader = require("dpd/sutta").new(db)

local rows, by_name, eligible, canonical = db:query("SELECT * FROM sutta_info"), {}, {}, {}
local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
for _, r in ipairs(rows) do
    by_name[r.dpd_sutta] = r
    canonical[r.dpd_sutta] = r.dpd_sutta
    for alias in (r.dpd_sutta_var .. ";"):gmatch("([^;,]*)[;,]") do
        alias = trim(alias)
        if alias ~= "" then canonical[alias] = canonical[alias] == alias and alias or r.dpd_sutta end
    end
end
for _, r in ipairs(rows) do
    if r.dpd_code ~= "" then
        eligible[r.dpd_sutta] = true
        for alias in (r.dpd_sutta_var .. ";"):gmatch("([^;,]*)[;,]") do
            if trim(alias) ~= "" then eligible[trim(alias)] = true end
        end
    end
end
local function has(s, needle) return s:find(needle, 1, true) ~= nil end
local function label(r)
    local code, name, var = r.dpd_code, r.dpd_sutta, r.dpd_sutta_var
    local whole = name ~= "" and code ~= "" and not has(code, ".") and not has(code, "-")
    local function either(f) return (name ~= "" and f(name)) or (var ~= "" and f(var)) end
    if whole and (name:gsub(" %d+$", "")):sub(-#"saṃyutta") == "saṃyutta" then return "saṃyutta" end
    if either(function(n) return has(n, "paṇṇāsapāḷi") or has(n, "paṇṇāsaka") end) then return "paṇṇāsaka" end
    if either(function(n) return has(n, "vagga") or has(n, "vaggo") end)
        or (has(code, "-") and (r.cst_vagga ~= "" or r.sc_vagga ~= "" or r.bjt_vagga ~= "")) then return "vagga" end
    if whole and either(function(n) return has(n, "nipāta") end) then return "nipāta" end
    return "sutta"
end

local started = os.clock()
reader:has("")
reader:has("not a sutta")
local first_ms = (os.clock() - started) * 1000
local checked, linked, failures = 0, 0, {}
started = os.clock()
for _, r in ipairs(db:query("SELECT DISTINCT lemma_1 FROM dpd_headwords")) do
    local got = reader:has(r.lemma_1)
    local want = eligible[r.lemma_1] and label(by_name[canonical[r.lemma_1]]) or nil
    if got ~= want then failures[#failures + 1] = r.lemma_1 .. ": " .. tostring(got) .. " ~= " .. tostring(want) end
    if got then
        linked = linked + 1
        local info = reader:info(r.lemma_1)
        for _, record in ipairs(info and info.records or {}) do
            for _, section in ipairs(record.sections) do
                for _, field in ipairs(section.fields) do
                    if field.value == "" then failures[#failures + 1] = r.lemma_1 .. ": empty " .. field.label end
                end
            end
        end
        if not info or #info.records == 0 then failures[#failures + 1] = r.lemma_1 .. ": no record" end
    end
    checked = checked + 1
end
local each_ms = (os.clock() - started) * 1000 / checked
print(string.format("Release %s: %d headwords, %d with sutta information", tostring(db.info.dpd_release_version), checked, linked))
print(string.format("first use (alias table) %.1f ms; per headword with panel build %.3f ms", first_ms, each_ms))
for i = 1, math.min(#failures, 20) do print("FAIL " .. failures[i]) end
assert(#failures == 0, #failures .. " mismatches")
assert(linked > 5116, "aliases should add headwords beyond the canonical names")
if db.info.dpd_release_version == "v0.4.20260926" then
    assert(linked == 5383, "this release includes four headword aliases in a comma-separated list")
end
print("PASS: sutta links and panels follow DPD's rules")
