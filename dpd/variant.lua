local Normalize = require("dpd/normalize")
local M = {}
local char_pattern = "[%z\1-\127\194-\244][\128-\191]*"
local separators = {}
for c in (" “”‘’«»–—…।॥√"):gmatch(char_pattern) do separators[c] = true end

local function wordChar(c)
    -- Treat unfamiliar Unicode letters/combining marks as part of a token,
    -- rather than incorrectly matching a Pali substring inside another word.
    return c:match("^[%w_]$") or (c:byte() >= 128 and not separators[c])
end

local function tokens(text)
    local out, word = {}, {}
    local function finish()
        if #word > 0 then out[#out + 1] = table.concat(word); word = {} end
    end
    text = Normalize.lower(Normalize.query(text))
    for c in text:gmatch(char_pattern) do
        if wordChar(c) then word[#word + 1] = c else finish() end
    end
    finish()
    return out
end

-- Reading notes hold several entries separated by ";". Each entry is the
-- reading, then provenance: "indakhile (ka.)", "mūsikukkaro – machasaṃ" or,
-- in grammar books, bare citations such as "ka. 60". Keep only the words
-- before provenance, skipping numbered citations.
local function readingWords(note)
    local words = {}
    note = note:gsub("<[^>]*>", ""):gsub("&[#%w]+;", " ")
    for entry in (note .. ";"):gmatch("([^;]*);") do
        local cut = #entry + 1
        for _, mark in ipairs({ "(", "[", "–" }) do
            local at = entry:find(mark, 1, true)
            if at and at < cut then cut = at end
        end
        local chunks = {}
        for chunk in entry:sub(1, cut - 1):gmatch("[^%s,]+") do chunks[#chunks + 1] = chunk end
        for i, chunk in ipairs(chunks) do
            -- Numbers and the book abbreviations before them ("pāci. 130",
            -- "saṃ. ni. 5.1020") are citations. Other dotted words stay: SYA
            -- writes its reading as "ma. gāvī.".
            local citation = chunk:find("%d")
            local j = i
            while not citation and chunks[j] and chunks[j]:find("%.$") do
                j = j + 1
                citation = chunks[j] and chunks[j]:find("^%d")
            end
            if not citation then
                for _, token in ipairs(tokens(chunk)) do words[#words + 1] = token end
            end
        end
    end
    return words
end

-- Cheap filter before tokenising: the note must contain the selected word's
-- longest ASCII run (after lowercasing and removing apostrophes). Readings of
-- common particles run to 1,679 notes (ca), so most notes are skipped here.
local function asciiRun(word)
    local best = ""
    for run in word:gmatch("[a-z]+") do if #run > #best then best = run end end
    return #best >= 2 and best or nil
end
local function mayContain(note, run)
    if not run then return true end
    local plain = note:gsub("<[^>]*>", ""):lower():gsub("'", ""):gsub("’", ""):gsub("‘", ""):gsub("ʼ", ""):gsub("ʻ", "")
    return plain:find(run, 1, true) ~= nil
end

function M.matches(form, variants)
    local selected = Normalize.lower(Normalize.query(form))
    local selected_tokens = tokens(selected)
    if #selected_tokens ~= 1 or selected_tokens[1] ~= selected then return {} end
    local run = asciiRun(selected)
    local out = {}
    for _, variant in ipairs(variants or {}) do
        local note = (variant.note or ""):gsub("<[bB][rR]%s*/?%s*>", " ")
        -- Match only reading words, never context or provenance.
        if mayContain(note, run) then
            for _, token in ipairs(readingWords(note)) do
                if token == selected then out[#out + 1] = variant; break end
            end
        end
    end
    return out
end

return M
