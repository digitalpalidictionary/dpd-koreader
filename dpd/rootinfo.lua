-- Fuller root information behind a "Root details" link, ported from DPD's
-- db/families/root_info.py and the bases rule in family_root.py.
-- tools/check_rootinfo_html.lua compares it with DPD's generated HTML.
-- SPDX-License-Identifier: MIT
local RootInfo = {}
RootInfo.__index = RootInfo

local columns = { "root", "root_has_verb", "root_group", "root_sign", "root_meaning", "root_in_comps",
    "dhatupatha_num", "dhatupatha_root", "dhatupatha_pali", "dhatupatha_english",
    "dhatumanjusa_num", "dhatumanjusa_root", "dhatumanjusa_pali", "dhatumanjusa_english",
    "dhatumala_root", "dhatumala_pali", "dhatumala_english",
    "sanskrit_root", "sanskrit_root_class", "sanskrit_root_meaning",
    "panini_root", "panini_sanskrit", "panini_english", "note" }
local groups = { "bhūvādigaṇa", "rudhādigaṇa", "divādigaṇa", "svādigaṇa",
    "kiyādigaṇa", "gahādigaṇa", "tanādigaṇa", "curādigaṇa" }
local CACHE = 16

function RootInfo.new(db) return setmetatable({ db = db, cache = {}, order = {} }, RootInfo) end

local function text(value)
    if value == nil then return "" end
    return tostring(value)
end
local function plain(value) return { text = text(value) } end
local function italic(value) return { text = text(value), italic = true } end
local function sup(value) return { text = text(value), sup = true } end
local function length(value) return select(2, value:gsub("[^\128-\191]", "")) end
local function present(value) return text(value) ~= "" and text(value) ~= "-" end

-- Distinct root bases of the root's headwords: the last step of root_base
-- ("√gam + a > gama > gaccha (irreg)" → "gaccha (irreg)"), shortest first.
function RootInfo:bases(root)
    local seen, out = {}, {}
    for _, row in ipairs(self.db:query("SELECT root_base FROM dpd_headwords WHERE root_key = ?", { root })) do
        local base = text(row.root_base):gsub("^.+> ", "")
        if base ~= "" and not seen[base] then seen[base] = true; out[#out + 1] = base end
    end
    -- Upstream sorts a set by length only, so ties have no defined order;
    -- break them alphabetically to stay stable.
    table.sort(out, function(a, b)
        local la, lb = length(a), length(b)
        if la == lb then return a < b end
        return la < lb
    end)
    return out
end

--- Rows of { label, parts = { { text, italic, sup } } } for one exact root key.
function RootInfo:details(root)
    if self.cache[root] then return self.cache[root] end
    -- The database records dpd_roots' columns when it opens; it is optional.
    if not self.db.columns.dpd_roots.root then return nil end
    local r = self.db:query("SELECT " .. self.db:selectColumns("dpd_roots", columns)
        .. " FROM dpd_roots WHERE root = ?", { root })[1]
    if not r then return nil end
    local rows = {}
    local function add(label, parts) rows[#rows + 1] = { label = label, parts = parts } end
    local group = tonumber(r.root_group)
    add("Pāḷi root", { plain((text(r.root):gsub(" %d*$", ""))), sup(r.root_has_verb),
        plain(text(r.root_group) .. " " .. (groups[group] or "") .. " + " .. text(r.root_sign)
            .. " (" .. text(r.root_meaning) .. ")") })
    local bases = self:bases(root)
    -- As upstream: "Bases" whenever the joined text has a comma, even within one base.
    local joined = #bases > 0 and table.concat(bases, ", ") or "-"
    add(joined:find(",", 1, true) and "Bases" or "Base", { plain(joined) })
    if text(r.root_in_comps) ~= "" then add("Root in compounds", { plain(r.root_in_comps) }) end
    if present(r.dhatupatha_root) then
        add("Dhātupātha", { plain(r.dhatupatha_root .. " "), italic(r.dhatupatha_pali),
            plain(" (" .. text(r.dhatupatha_english) .. ") #" .. text(r.dhatupatha_num)) })
    else add("Dhātupātha", { plain("-") }) end
    if present(r.dhatumanjusa_root) then
        add("Dhātumañjūsa", { plain(r.dhatumanjusa_root .. " "), italic(r.dhatumanjusa_pali),
            plain(" (" .. text(r.dhatumanjusa_english) .. ") #" .. text(r.dhatumanjusa_num)) })
    else add("Dhātumañjūsa", { plain("-") }) end
    if present(r.dhatumala_root) then
        add("Saddanīti", { plain(r.dhatumala_root .. " "), italic(r.dhatumala_pali),
            plain(" (" .. text(r.dhatumala_english) .. ")") })
    else add("Saddanīti", { plain("-") }) end
    if present(r.sanskrit_root) then
        add("Sanskrit root", { plain(text(r.sanskrit_root) .. " " .. text(r.sanskrit_root_class)
            .. " (" .. text(r.sanskrit_root_meaning) .. ")") })
    else add("Sanskrit root", { plain("-") }) end
    if present(r.panini_root) then
        add("Pāṇinīya Dhātupāṭha", { plain(r.panini_root .. " "), italic(r.panini_sanskrit),
            plain(" (" .. text(r.panini_english) .. ")") })
    else add("Pāṇinīya Dhātupāṭha", { plain("-") }) end
    if text(r.note) ~= "" then add("Notes", { plain(r.note) }) end
    local result = { root = root, rows = rows }
    if #self.order >= CACHE then self.cache[table.remove(self.order, 1)] = nil end
    self.order[#self.order + 1] = root
    self.cache[root] = result
    return result
end

return RootInfo
