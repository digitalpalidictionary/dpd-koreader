-- The root matrix: a root's headwords grouped by part of speech and the
-- derivation in root_base (caus, pass, desid, intens, deno), as in DPD's
-- db/families/root_matrix.py. The rules are data in dpd/rootmatrix_rules.lua,
-- generated from that file. Reads one root's headwords through the root_key
-- index (largest root √ṭhā: 822 headwords) only when the matrix is opened.
local SortKey = require("dpd/sortkey")
local RootMatrix = {}
RootMatrix.__index = RootMatrix
RootMatrix.rules = require("dpd/rootmatrix_rules")

local CACHE, CACHE_BYTES = 8, 256 * 1024

function RootMatrix.new(db) return setmetatable({ db = db, cache = {}, order = {}, bytes = 0 }, RootMatrix) end

local function text(value) return value == nil and "" or tostring(value) end

-- Python's \w for the neighbours of a match: ASCII letters, digits and "_",
-- and Unicode letters and digits (Latin with diacritics, superscript digits).
local function wordChar(s, i, backwards)
    if backwards then
        while i > 0 and s:byte(i) >= 0x80 and s:byte(i) < 0xC0 do i = i - 1 end
    end
    local b = s:byte(i)
    if not b then return false end
    if b < 0x80 then return s:sub(i, i):match("[%w_]") ~= nil end
    local n = b >= 0xF0 and 4 or b >= 0xE0 and 3 or 2
    local cp = b % (2 ^ (7 - n))
    for k = 1, n - 1 do cp = cp * 64 + (s:byte(i + k) or 0x80) % 64 end
    return (cp >= 0xC0 and cp <= 0x24F and cp ~= 0xD7 and cp ~= 0xF7)
        or (cp >= 0x1E00 and cp <= 0x1EFF) or cp == 0xB2 or cp == 0xB3 or cp == 0xB9
        or (cp >= 0x2070 and cp <= 0x2079) or (cp >= 0x300 and cp <= 0x36F)
end

--- re.findall(r"\bword\b", s) is non-empty.
function RootMatrix.hasWord(s, word)
    local start = 1
    while true do
        local i, j = s:find(word, start, true)
        if not i then return false end
        if not wordChar(s, i - 1, true) and not wordChar(s, j + 1) then return true end
        start = i + 1
    end
end

local function holds(conditions, row)
    for _, c in ipairs(conditions) do
        if c.pos then
            if text(row.pos) ~= c.pos then return false end
        elseif c.lemma then
            if text(row.lemma_1) ~= c.lemma then return false end
        elseif c.word then
            if not RootMatrix.hasWord(text(row[c.field]), c.word) then return false end
        elseif not text(row[c.field]):find(c.text, 1, true) then return false end
    end
    return true
end

--- The { category, row } a headword belongs to, or nil (upstream skips it).
function RootMatrix.classify(row)
    for _, rule in ipairs(RootMatrix.rules.rules) do
        if holds(rule.when, row) then
            if rule.target then return rule.target end
            for _, step in ipairs(rule.chain) do
                if holds(step.when, row) then return step.target end
            end
            return nil
        end
    end
end

--- DPD's superscripter_uni: "gacchati 1" → "gacchati ¹" (hair space).
function RootMatrix.superscript(lemma)
    local digits = { ["0"] = "⁰", ["1"] = "¹", ["2"] = "²", ["3"] = "³", ["4"] = "⁴",
        ["5"] = "⁵", ["6"] = "⁶", ["7"] = "⁷", ["8"] = "⁸", ["9"] = "⁹", ["."] = "·" }
    return (text(lemma):gsub(" (%d)", "\226\128\138%1"):gsub("[%d%.]", digits))
end

--- Non-empty categories and rows for an exact root key, in DPD's order; each
--- row's headwords in Pāḷi alphabetical order. Cached and shared: read-only.
--- @return table { root, total, groups = { { name, rows = { { label, items = { { id, lemma } } } } } } }
function RootMatrix:matrix(root)
    if self.cache[root] then return self.cache[root] end
    local cells, total, bytes = {}, 0, 0
    for _, row in ipairs(self.db:query("SELECT id, lemma_1, pos, grammar, root_base FROM dpd_headwords"
        .. " WHERE root_key = ?", { root })) do
        local target = RootMatrix.classify(row)
        if target then
            local key = target[1] .. "\0" .. target[2]
            cells[key] = cells[key] or {}
            local item = { id = tonumber(row.id), lemma = row.lemma_1, sort_key = SortKey(row.lemma_1) }
            cells[key][#cells[key] + 1] = item
            total, bytes = total + 1, bytes + #row.lemma_1 + 48
        end
    end
    local result = { root = root, total = total, groups = {} }
    for _, category in ipairs(RootMatrix.rules.categories) do
        local group = { name = category.name, rows = {} }
        for _, label in ipairs(category.rows) do
            local items = cells[category.name .. "\0" .. label]
            if items then
                table.sort(items, function(a, b)
                    if a.sort_key == b.sort_key then return a.id < b.id end
                    return a.sort_key < b.sort_key
                end)
                for _, item in ipairs(items) do item.sort_key = nil end
                group.rows[#group.rows + 1] = { label = label, items = items }
            end
        end
        if #group.rows > 0 then result.groups[#result.groups + 1] = group end
    end
    while #self.order > 0 and (#self.order >= CACHE or self.bytes + bytes > CACHE_BYTES) do
        local old = table.remove(self.order, 1)
        self.bytes = self.bytes - self.cache[old].bytes
        self.cache[old] = nil
    end
    result.bytes = bytes
    self.cache[root], self.order[#self.order + 1], self.bytes = result, root, self.bytes + bytes
    return result
end

return RootMatrix
