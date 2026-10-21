-- Autocomplete for the manual lookup dialog. Never used for long-press.
--
-- Pāḷi mode, tier 1: headwords whose lemma_1 starts with the typed text,
-- read from a capped slice of the lemma_1 index (at most SCAN rows), with
-- numbered senses collapsed to one clean lemma. An exact match comes first,
-- then the most frequent candidates in the early texts (ebt_count), then Pāḷi order.
-- Tier 2, for input without diacritics or with diacritics that start no
-- headword: lookup forms whose fuzzy_key starts with the folded text,
-- labelled approximate (the fold also drops aspiration and doubled
-- consonants), from a capped slice of that index, with up to two places kept
-- for them, or all places when tier 1 found nothing.
-- English mode: English keys that have English→Pāḷi entries, exact first,
-- single words before phrases, then those with the most entries, from
-- capped slices of likely English keys (a few hundred rows read at most).
local Normalize = require("dpd/normalize")
local SortKey = require("dpd/sortkey")
local Suggest = {}
Suggest.__index = Suggest
Suggest.limit = 6
Suggest.scan = 1000
Suggest.english_scan = 400
Suggest.english_letter_scan = 10
Suggest.english_capital_scan = 50
Suggest.approximate_limit = 3
local CACHE = 32
local TOP = "\244\143\191\191"

function Suggest.new(db) return setmetatable({ db = db, cache = {}, order = {} }, Suggest) end

local function clean(lemma) return (lemma:gsub(" %d[%d.]*$", "")) end

local function letters(text)
    local out = {}
    for c in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do out[#out + 1] = c end
    return out
end

function Suggest:_headwords(text, limit)
    local has_ebt = self.db.columns.dpd_headwords and self.db.columns.dpd_headwords.ebt_count
    local rows = self.db:query("SELECT lemma_1, " .. (has_ebt and "ebt_count" or "0 AS ebt_count")
        .. " FROM dpd_headwords WHERE lemma_1 >= ? AND lemma_1 < ? ORDER BY lemma_1 LIMIT ?",
        { text, text .. TOP, Suggest.scan })
    local by_lemma, list = {}, {}
    for _, row in ipairs(rows) do
        local lemma = clean(row.lemma_1)
        local ebt = tonumber(row.ebt_count) or 0
        local item = by_lemma[lemma]
        if not item then
            item = { text = lemma, ebt = ebt, sort_key = SortKey(lemma) }
            by_lemma[lemma] = item
            list[#list + 1] = item
        elseif ebt > item.ebt then item.ebt = ebt end
    end
    table.sort(list, function(a, b)
        local ea, eb = a.text == text, b.text == text
        if ea ~= eb then return ea end
        if a.ebt ~= b.ebt then return a.ebt > b.ebt end
        return a.sort_key < b.sort_key
    end)
    local out = {}
    for i = 1, math.min(limit, #list) do out[i] = { text = list[i].text } end
    return out
end

-- Orders candidates { text, order, distance?, whole? }: the closest spellings
-- first when a distance is given, then whole-word matches before longer
-- forms, then forms that are themselves headwords, the most frequent first
-- (one statement, an index probe each), then by `order`.
function Suggest:_rank(candidates)
    if #candidates == 0 then return end
    local has_ebt = self.db.columns.dpd_headwords and self.db.columns.dpd_headwords.ebt_count
    local parts, params = {}, {}
    for i, item in ipairs(candidates) do
        item.headword, item.ebt = false, 0
        parts[i] = "SELECT " .. i .. " AS k, count(*) AS n, max(" .. (has_ebt and "ebt_count" or "0") .. ") AS ebt"
            .. " FROM dpd_headwords WHERE lemma_1 = ? OR (lemma_1 >= ? AND lemma_1 < ?)"
        params[#params + 1], params[#params + 2], params[#params + 3] = item.text, item.text .. " ", item.text .. " " .. TOP
    end
    for _, probe in ipairs(self.db:query(table.concat(parts, " UNION ALL "), params)) do
        local item = candidates[tonumber(probe.k)]
        if item then item.headword, item.ebt = (tonumber(probe.n) or 0) > 0, tonumber(probe.ebt) or 0 end
    end
    table.sort(candidates, function(a, b)
        if a.distance ~= b.distance then return a.distance < b.distance end
        if a.whole ~= b.whole then return a.whole end
        if a.headword ~= b.headword then return a.headword end
        if a.ebt ~= b.ebt then return a.ebt > b.ebt end
        return a.order < b.order
    end)
end

function Suggest:_approximate(text, seen, limit)
    if not (self.db.columns.lookup and self.db.columns.lookup.fuzzy_key) then return {} end
    local key = Normalize.fuzzy(text)
    if key == "" then return {} end
    local rows = self.db:query("SELECT lookup_key, headwords FROM (SELECT lookup_key, headwords FROM lookup"
        .. " WHERE fuzzy_key >= ? AND fuzzy_key < ? ORDER BY fuzzy_key LIMIT ?)"
        .. " WHERE coalesce(headwords, '') NOT IN ('', '[]') ORDER BY length(lookup_key), lookup_key",
        { key, key .. TOP, 200 })
    -- Forms whose opening letters are closest to the typed text first, so
    -- anattika finds āṇattika before aññātikā; then whole-word matches, so
    -- tinasanthara finds tiṇasanthara before the more frequent
    -- tiṇasanthāraka; then forms that are themselves headwords, the most
    -- frequent first (one probe statement for at most 20 candidates).
    local typed = #letters(text)
    local candidates = {}
    for _, row in ipairs(rows) do
        -- A form that starts with the typed text is not approximate.
        if not seen[row.lookup_key] and row.lookup_key:sub(1, #text) ~= text then
            seen[row.lookup_key] = true
            local opening = table.concat(letters(row.lookup_key), "", 1, math.min(typed, #letters(row.lookup_key)))
            candidates[#candidates + 1] = { text = row.lookup_key, entries = row.headwords, order = #candidates,
                distance = Suggest.distance(text, opening), whole = Normalize.fuzzy(row.lookup_key) == key }
        end
    end
    table.sort(candidates, function(a, b)
        if a.distance ~= b.distance then return a.distance < b.distance end
        if a.whole ~= b.whole then return a.whole end
        return a.order < b.order
    end)
    for i = #candidates, 21, -1 do candidates[i] = nil end
    self:_rank(candidates)
    -- One place per entry: an inflection of entries already offered
    -- (āṇattikā after āṇattika) gives way to other words. A form that is
    -- itself a headword stays, since jaṇṇuka and jaṇṇukā share their entries.
    local out, offered = {}, {}
    for _, item in ipairs(candidates) do
        if #out >= limit then break end
        local entries = item.entries and item.entries:gsub("%s", "")
        if item.headword or not (entries and offered[entries]) then
            if entries then offered[entries] = true end
            out[#out + 1] = { text = item.text, approximate = true }
        end
    end
    return out
end

-- Letters KOReader's English keyboard has no key for (its popups have ā ī ū ñ ṭ).
local untypable = { ["ṅ"] = true, ["ḍ"] = true, ["ṇ"] = true, ["ḷ"] = true, ["ṃ"] = true }

-- A headword that differs from the typed word only where the typed letter
-- lacks a mark: kāla also offers kāḷa, pāna pāṇa, which the keyboard cannot
-- type. Marks the reader typed are kept, so kāla never offers kala, and
-- headwords that differ only in letters without a key come first, so kāla
-- offers kāḷa before kālā. The most frequent of those, from one indexed
-- fuzzy_key probe; nil if none.
function Suggest:_alternative(text, seen)
    if not (self.db.columns.lookup and self.db.columns.lookup.fuzzy_key) then return nil end
    local typed = letters(text)
    local candidates = {}
    for _, row in ipairs(self.db:query("SELECT lookup_key FROM lookup WHERE fuzzy_key = ? LIMIT 50",
            { Normalize.fuzzy(text) })) do
        local chars = letters(row.lookup_key)
        local same = not seen[row.lookup_key] and row.lookup_key ~= text and #chars == #typed
        local keyless = true
        for i = 1, same and #typed or 0 do
            local t, c = typed[i], chars[i]
            if t ~= c then
                if Normalize.base(t) ~= t or Normalize.base(c) ~= t then same = false; break end
                keyless = keyless and untypable[c]
            end
        end
        if same then
            seen[row.lookup_key] = true
            candidates[#candidates + 1] = { text = row.lookup_key, order = #candidates, distance = keyless and 0 or 1 }
        end
    end
    self:_rank(candidates)
    for _, item in ipairs(candidates) do
        if item.headword then return { text = item.text, approximate = true } end
    end
end

function Suggest:_english(text, limit)
    if not (self.db.columns.lookup and self.db.columns.lookup.epd) then return {} end
    -- Whether a key has English entries is in its row, and reading thousands
    -- of rows under a crowded Pāḷi prefix (26,000 keys start with sam) takes
    -- seconds on an e-reader. So choose candidates from the key index alone:
    -- keys that look English, plain ASCII or with a space or capital
    -- ("epithet of Nibbāna"); all but ten of DPD's 79,596 English keys pass
    -- (niggahīta, vīṇā: Pāḷi words Pāḷi mode finds). Pāḷi forms without
    -- diacritics pass too, so read at most the first 400 of them and,
    -- from three characters, the first few for each next letter, so that sama…
    -- forms cannot crowd out same. A rare word under a crowded prefix (mahout)
    -- appears a letter or two later.
    local _, length = text:gsub("[^\128-\191]", "")
    local likely = " AND (lookup_key NOT GLOB '*[^ -~]*' OR lookup_key GLOB '*[ A-Z]*')"
    local slices, params = {}, {}
    local function slice(from, to, count)
        slices[#slices + 1] = "SELECT * FROM (SELECT lookup_key FROM lookup WHERE lookup_key >= ? AND lookup_key < ?"
            .. likely .. " ORDER BY lookup_key LIMIT ?)"
        params[#params + 1], params[#params + 2], params[#params + 3] = from, to, count
    end
    slice(text, text .. TOP, length >= 3 and Suggest.english_scan or 200)
    -- Names are capitalised keys (Nibbāna, Buddha, Sakka), which sort before
    -- the lowercased typed text: read their own slice.
    local capital = text:gsub("^%l", string.upper)
    if capital ~= text then slice(capital, capital .. TOP, Suggest.english_capital_scan) end
    if length >= 3 then
        -- Punctuation, digits and capitals; a to z; then non-ASCII letters.
        local bounds = { text }
        for byte = 97, 123 do bounds[#bounds + 1] = text .. string.char(byte) end
        bounds[#bounds + 1] = text .. TOP
        for i = 1, #bounds - 1 do slice(bounds[i], bounds[i + 1], Suggest.english_letter_scan) end
    end
    params[#params + 1], params[#params + 2], params[#params + 3] = text, capital, limit
    local rows = self.db:query("SELECT lookup_key FROM lookup WHERE lookup_key IN ("
        .. table.concat(slices, " UNION ") .. ") AND coalesce(epd, '') NOT IN ('', '[]')"
        -- Exact first, single words before phrases, then keys with the most entries.
        .. " ORDER BY lookup_key IN (?, ?) DESC, instr(lookup_key, ' ') > 0, length(epd) DESC, lookup_key LIMIT ?",
        params)
    local out = {}
    for _, row in ipairs(rows) do out[#out + 1] = { text = row.lookup_key } end
    return out
end

-- Folded keys contain only these letters (dpd/normalize.lua M.fuzzy).
local LETTERS = "abcdeghijklmnoprstuvy"
Suggest.spelling_limit = 5

--- Every key one edit (delete, swap, change, insert) from a folded key,
--- folded again and without the key itself.
function Suggest.edits(key)
    local seen, out = { [key] = true }, {}
    local function add(variant)
        variant = Normalize.fuzzy(variant)
        if variant ~= "" and not seen[variant] then seen[variant] = true; out[#out + 1] = variant end
    end
    for i = 1, #key do
        add(key:sub(1, i - 1) .. key:sub(i + 1))
        if i < #key then add(key:sub(1, i - 1) .. key:sub(i + 1, i + 1) .. key:sub(i, i) .. key:sub(i + 2)) end
        for c in LETTERS:gmatch(".") do add(key:sub(1, i - 1) .. c .. key:sub(i + 1)) end
    end
    for i = 1, #key + 1 do
        for c in LETTERS:gmatch(".") do add(key:sub(1, i - 1) .. c .. key:sub(i)) end
    end
    return out
end

--- Edits from typed text to a spelling (drop, add, change or swap a letter).
--- A diacritic alone (a/ā, m/ṃ) costs a quarter, or nothing when the typed
--- text has no diacritics: samadhy is 1 from samādhi. A missing or extra ṃ
--- costs half, since sandhi often drops it (jāneyyu’’nti for jāneyyuṃ ti):
--- jāneyyu is then nearer jāneyyuṃ than jāneyya.
local function gap(char) return char == "ṃ" and 0.5 or 1 end

function Suggest.distance(a, b)
    local mark = a:find("[\128-\255]") and 0.25 or 0
    a, b = letters(a), letters(b)
    local prev2, prev, row = nil, { [0] = 0 }, nil
    for j = 1, #b do prev[j] = prev[j - 1] + gap(b[j]) end
    for i = 1, #a do
        row = { [0] = prev[0] + gap(a[i]) }
        for j = 1, #b do
            local change = a[i] == b[j] and 0 or Normalize.base(a[i]) == Normalize.base(b[j]) and mark or 1
            local best = math.min(prev[j] + gap(a[i]), row[j - 1] + gap(b[j]), prev[j - 1] + change)
            if prev2 and i > 1 and j > 1 and a[i] == b[j - 1] and a[i - 1] == b[j] then
                best = math.min(best, prev2[j - 2] + 1)
            end
            row[j] = best
        end
        prev2, prev = prev, row
    end
    return prev[#b]
end

--- Spelling suggestions after a manual miss: dictionary forms whose folded
--- key is one edit from the typed word's. The closest spellings come first
--- (diacritics counting little), then headwords and frequent ones.
--- Bounded: one indexed IN query over at most ~900 keys returning at most
--- 200 forms, and one probe statement for the closest 20; not a promise of
--- the closest word in the whole dictionary.
--- @return table { { text, approximate = true } }
function Suggest:spelling(text, limit)
    limit = limit or Suggest.spelling_limit
    if not (self.db.columns.lookup and self.db.columns.lookup.fuzzy_key) then return {} end
    text = Normalize.lower(tostring(text or ""))
    local key = Normalize.fuzzy(text)
    if #key < 3 or #key > 20 or key:find("[^a-z]") then return {} end
    local keys = Suggest.edits(key)
    local marks = {}
    for i = 1, #keys do marks[i] = "?" end
    keys[#keys + 1] = 200
    local rows = self.db:query("SELECT lookup_key FROM lookup WHERE fuzzy_key IN (" .. table.concat(marks, ",")
        .. ") AND coalesce(headwords, '') NOT IN ('', '[]') LIMIT ?", keys)
    local candidates, seen = {}, {}
    for _, row in ipairs(rows) do
        if not seen[row.lookup_key] then
            seen[row.lookup_key] = true
            candidates[#candidates + 1] = { text = row.lookup_key, order = #candidates,
                distance = Suggest.distance(text, row.lookup_key) }
        end
    end
    -- Rank all of them by distance before cutting, so the cut never drops a
    -- closer spelling; only the closest 20 are probed for headwords.
    table.sort(candidates, function(a, b)
        if a.distance ~= b.distance then return a.distance < b.distance end
        return a.order < b.order
    end)
    for i = #candidates, 21, -1 do candidates[i] = nil end
    self:_rank(candidates)
    local out = {}
    for i = 1, math.min(limit, #candidates) do out[i] = { text = candidates[i].text, approximate = true } end
    return out
end

--- English text as suggestions and lookups read it: one space between
--- words, without trailing sentence punctuation (monk. is monk).
function Suggest.english(text)
    return (Normalize.trim(Normalize.nfc(text)):gsub("%s+", " "):gsub("[%.,;:!?]+$", ""))
end

--- Suggestions for typed text: { { text, approximate } }, at most `limit`.
--- Nothing for empty input or a typed ID. Cached and shared: read-only.
function Suggest:complete(text, mode, limit)
    mode, limit = mode or "pali", limit or Suggest.limit
    text = tostring(text or "")
    -- Pāḷi pasted text gets the same punctuation, soft-hyphen and niggahīta
    -- cleanup as a lookup. English retains its own punctuation and letters.
    text = Normalize.lower(mode == "english" and Suggest.english(text) or Normalize.query(text))
    if text == "" or text:match("^%d+$") then return {} end
    local id = mode .. "\0" .. limit .. "\0" .. text
    if self.cache[id] then return self.cache[id] end
    local out
    if mode == "english" then
        out = self:_english(text, limit)
    else
        out = self:_headwords(text, limit)
        -- Without diacritics the reader may mean ā or ñ: keep up to two places
        -- (more if headwords leave room) for approximate forms, and all of
        -- them when no headword matched. Typed diacritics that start no
        -- headword may lack one the keyboard has no key for (ānattika for
        -- āṇattika): offer approximate forms instead.
        if not text:find("[\128-\255]") or #out == 0 then
            local seen = {}
            for _, item in ipairs(out) do seen[item.text] = true end
            local approximate = self:_approximate(text, seen,
                #out == 0 and limit or math.min(Suggest.approximate_limit, limit))
            local keep = math.min(#out, limit - math.min(#approximate, 2))
            for i = #out, keep + 1, -1 do out[i] = nil end
            for _, item in ipairs(approximate) do
                if #out >= limit then break end
                out[#out + 1] = item
            end
        else
            local seen = {}
            for _, item in ipairs(out) do seen[item.text] = true end
            -- The last place, never the first: an exact match stays first.
            local alternative = limit > 1 and self:_alternative(text, seen)
            if alternative then out[math.min(#out + 1, limit)] = alternative end
        end
    end
    if #self.order >= CACHE then self.cache[table.remove(self.order, 1)] = nil end
    self.order[#self.order + 1] = id
    self.cache[id] = out
    return out
end

return Suggest
