-- Run from desktop KOReader when changing dpd/suggest.lua:
-- ./luajit <plugin>/tools/check_suggest_recall.lua <plugin> <database> [sample size, default 1500]
-- Samples headwords with a letter KOReader's keyboard cannot type (ṅ ḍ ṇ ḷ ṃ;
-- its long-press popups have ā ī ū ñ ṭ) and prints how often Pāḷi
-- autocomplete offers each one in its six places, typed four ways: whole or
-- two letters past that letter, as the keyboard can type it or in plain ASCII.
-- Compare the numbers before and after a change. Leaves the database read-only.
require("setupkoenv")
local root, path = assert(arg[1], "plugin directory required"), assert(arg[2], "DPD database required")
local size = tonumber(arg[3] or 1500)
package.path = root .. "/?.lua;" .. package.path
local DB = require("dpd/db")
local Suggest = require("dpd/suggest")

local db = assert(DB.new(path))
local untypable = { ["ṅ"] = "n", ["ḍ"] = "d", ["ṇ"] = "n", ["ḷ"] = "l", ["ṃ"] = "m" }
local plain = { ["ā"] = "a", ["ī"] = "i", ["ū"] = "u", ["ñ"] = "n", ["ṭ"] = "t" }
for k, v in pairs(untypable) do plain[k] = v end
local char_pattern = "[%z\1-\127\194-\244][\128-\191]*"
local function map(text, to) return (text:gsub(char_pattern, function(c) return to[c] or c end)) end
local function chars(text)
    local out = {}
    for c in text:gmatch(char_pattern) do out[#out + 1] = c end
    return out
end
local function head(text, count) return table.concat(chars(text), "", 1, count) end

-- Distinct single-word lemmas, shuffled with a fixed seed.
local seen, lemmas = {}, {}
for _, row in ipairs(db:query("SELECT lemma_1 FROM dpd_headwords", {})) do
    local lemma = row.lemma_1:gsub(" %d[%d.]*$", "")
    if not seen[lemma] and not lemma:find(" ") then seen[lemma] = true; lemmas[#lemmas + 1] = lemma end
end
table.sort(lemmas)
math.randomseed(7)
for i = #lemmas, 2, -1 do
    local j = math.random(i)
    lemmas[i], lemmas[j] = lemmas[j], lemmas[i]
end

local stats, misses, sampled, started = {}, {}, 0, os.clock()
for _, lemma in ipairs(lemmas) do
    if sampled >= size then break end
    local letters, first = chars(lemma), nil
    for i, c in ipairs(letters) do if untypable[c] then first = i; break end end
    if first and #letters >= 4 then
        sampled = sampled + 1
        local cut = math.min(#letters, first + 2)
        local keyboard, ascii = map(lemma, untypable), map(lemma, plain)
        local suggest = Suggest.new(db)
        for _, case in ipairs{ { "keyboard, whole", keyboard }, { "keyboard, prefix", head(keyboard, cut) },
                               { "ASCII, whole", ascii }, { "ASCII, prefix", head(ascii, cut) } } do
            -- Typed diacritics take a different path from plain ASCII.
            local name = case[1] .. (case[2]:find("[\128-\255]") and ", with ā ī ū ñ ṭ" or "")
            local found = false
            for _, item in ipairs(suggest:complete(case[2], "pali", 6)) do
                if item.text == lemma then found = true; break end
            end
            local s = stats[name] or { name = name, n = 0, found = 0, examples = {} }
            stats[name] = s
            s.n = s.n + 1
            if found then s.found = s.found + 1
            elseif #s.examples < 4 then s.examples[#s.examples + 1] = case[2] .. " → " .. lemma end
        end
    end
end

local names = {}
for name in pairs(stats) do names[#names + 1] = name end
table.sort(names)
print(("%d headwords with ṅ ḍ ṇ ḷ ṃ, %.1f s; found in the six suggestions:"):format(sampled, os.clock() - started))
for _, name in ipairs(names) do
    local s = stats[name]
    print(("  %s%s %5.1f%%  (n=%d)"):format(name, (" "):rep(34 - #chars(name)), 100 * s.found / s.n, s.n))
end
print("Some misses:")
for _, name in ipairs(names) do
    for _, example in ipairs(stats[name].examples) do misses[#misses + 1] = "  " .. name .. ": " .. example end
end
print(table.concat(misses, "\n"))
