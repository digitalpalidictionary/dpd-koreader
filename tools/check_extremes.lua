-- Run from a desktop KOReader directory with its bundled luajit:
-- SDL_VIDEODRIVER=dummy DPD_TEST_FONT_SIZE=26 ./luajit <plugin>/tools/check_extremes.lua <plugin> <dpd-mobile.db> [screenshot-dir]
-- Renders the database's extremes instead of hand-picked words: for each
-- displayed field, the headwords with its longest unbroken words, and the
-- longest headwords with an inflection table. Every word must end inside
-- the popup in the expanded sense and the table. Run at fonts 26 and 32 on
-- the Paperwhite and at 26 on 600x800 (EMULATE_READER_W/H), and for each new
-- release.
require("setupkoenv")
local root = assert(arg[1], "plugin directory required")
local path = assert(arg[2], "DPD database required")
package.path = root .. "/?.lua;" .. package.path
G_defaults = require("luadefaults"):open()
G_reader_settings = require("luasettings"):wrap({})
local Device = require("device")
require("document/canvascontext"):init(Device)
require("ui/bidi").setup()
local UIManager = require("ui/uimanager")
local Viewer = require("ui/dpd_viewer")
local DB = require("dpd/db")
local Lookup = require("dpd/lookup")
local db = DB.new(path)
local lookup = Lookup.new(db)
local font_size = tonumber(os.getenv("DPD_TEST_FONT_SIZE")) or 26
local per_field = 3

local function flush() UIManager:_checkTasks(); UIManager:_repaint() end

-- Fields an expanded sense displays, and the family keys its buttons name.
local fields = { "lemma_1", "lemma_ipa", "construction", "compound_construction", "derived_from", "root_base",
    "sanskrit", "cognate", "phonetic", "commentary", "notes", "synonym", "antonym", "variant", "var_text",
    "example_1", "example_2", "sutta_1", "sutta_2", "source_1", "source_2", "link",
    "meaning_1", "meaning_2", "meaning_lit", "family_compound", "family_word", "family_idioms", "family_set" }
local columns = {}
for _, row in ipairs(db:query("PRAGMA table_info(dpd_headwords)")) do columns[row.name] = true end

local cases, chosen = {}, {}
local function choose(id, reason)
    if chosen[id] then return end
    chosen[id] = true
    cases[#cases + 1] = { id = id, reason = reason }
end
local function longestWord(text)
    local longest = 0
    for word in tostring(text):gsub("<[^>]*>", " "):gmatch("%S+") do
        local _, letters = word:gsub("[^\128-\191]", "")
        if letters > longest then longest = letters end
    end
    return longest
end
for _, field in ipairs(fields) do
    if columns[field] then
        local top = {}
        -- Only a value longer than 30 bytes can hold a word that matters here.
        for _, row in ipairs(db:query("SELECT id, " .. field .. " AS value FROM dpd_headwords WHERE length("
                .. field .. ") > 30")) do
            local length = longestWord(row.value)
            if #top < per_field or length > top[#top].length then
                top[#top + 1] = { id = row.id, length = length }
                table.sort(top, function(a, b) return a.length > b.length end)
                top[per_field + 1] = nil
            end
        end
        for _, item in ipairs(top) do choose(item.id, field .. " " .. item.length) end
    end
end
for _, row in ipairs(db:query("SELECT id, length(lemma_1) AS length FROM dpd_headwords WHERE pattern <> ''"
        .. " ORDER BY length(lemma_1) DESC LIMIT " .. per_field)) do
    choose(row.id, "table lemma " .. row.length)
end

-- Short irregular headwords can have whole-word endings wider than a column.
for _, row in ipairs(db:query("SELECT MIN(id) AS id FROM dpd_headwords WHERE stem IN ('*', '!', '!*', '*!')"
        .. " AND pattern <> '' GROUP BY pattern")) do
    choose(row.id, "whole-word irregular table")
end

-- A word may end a few pixels out: a tie bar (t͡ʃ) at a line break overhangs.
local slack = 3
-- One line per view that overflows: how many words, and the furthest.
local function overflow(viewer, label)
    local box = viewer.scroll.htmlbox_widget
    local width, count, worst = box.dimen.w, 0, nil
    for page = 1, box.page_count do
        local opened = box.document:openPage(page)
        local text = opened:getPageText()
        opened:close()
        for _, line in ipairs(text or {}) do
            for _, word in ipairs(line) do
                if word.x1 > width + slack then
                    count = count + 1
                    if not worst or word.x1 > worst.x1 then worst = { x1 = word.x1, word = word.word, page = page } end
                end
            end
        end
    end
    if count == 0 then return end
    if arg[3] then
        Device.screen.bb:writePNG(string.format("%s/%s-%d.png", arg[3], label:gsub("[^%w]+", "-"), font_size))
    end
    return string.format("%s: %d words past the edge, up to %.0f of %d (%q on page %d)",
        label, count, worst.x1, width, worst.word:sub(1, 40), worst.page)
end

local failures, tables = {}, 0
for _, case in ipairs(cases) do
    local ok, err = pcall(function()
        local viewer = Viewer:new{ model = assert(lookup:byId(case.id), "no headword"), lookup = lookup,
            font_size = font_size }
        UIManager:show(viewer); flush()
        viewer:onLink("dpd:sense/" .. case.id); flush()
        local label = case.id .. " (" .. case.reason .. ")"
        failures[#failures + 1] = overflow(viewer, label .. " sense")
        if viewer.navigation:current().details[case.id].paradigm_kind then
            viewer:onLink("dpd:detail-paradigm/" .. case.id); flush()
            assert(viewer.navigation:current().model.paradigm, "no table opened")
            tables = tables + 1
            failures[#failures + 1] = overflow(viewer, label .. " table")
        end
        viewer:close(); flush()
    end)
    if not ok then failures[#failures + 1] = case.id .. " (" .. case.reason .. "): " .. tostring(err) end
end
db:close()

assert(#failures == 0, "\n" .. table.concat(failures, "\n"))
print(string.format("PASS: %d extreme headwords and %d of their tables fit the popup at font %d",
    #cases, tables, font_size))
