-- Per-book long-press and the Vocabulary builder, with real long-presses in
-- the test book, KOReader's own Vocabulary builder and a reopened book.
-- From a desktop KOReader directory, with a disposable KO_MULTIUSER=1/XDG_CONFIG_HOME:
-- SDL_VIDEODRIVER=dummy ./luajit <plugin>/tools/check_book_lookup.lua <plugin> <db> "$DPD_BOOK" [screenshots]
-- Use a fresh temporary EPUB copy with no .sdr for each run; see
-- docs/KOREADER_RUNBOOK.md for the DPD_BOOK setup.
require("setupkoenv")
local root, path, book, out = assert(arg[1]), assert(arg[2]), assert(arg[3]), arg[4]
G_defaults = require("luadefaults"):open()
local DataStorage = require("datastorage")
G_reader_settings = require("luasettings"):open(DataStorage:getDataDir() .. "/settings.reader.lua")
local lfs = require("libs/libkoreader-lfs")
local disabled = {}
for entry in lfs.dir("plugins") do
    if entry:sub(-9) == ".koplugin" and entry ~= "vocabbuilder.koplugin" then disabled[entry:sub(1, -10)] = true end
end
G_reader_settings:saveSetting("plugins_disabled", disabled)
G_reader_settings:saveSetting("extra_plugin_paths", { assert(root:match("^(.+)/[^/]+$")) })
G_reader_settings:saveSetting("dpd", { db_path = path, direct_lookup = true })
G_reader_settings:saveSetting("vocabulary_builder", { enabled = true, with_context = true })
G_defaults:saveSetting("DELAY_CLEAR_HIGHLIGHT_S", 0)
local Device = require("device")
require("document/canvascontext"):init(Device)
require("ui/bidi").setup()
local Event = require("ui/event")
local Geom = require("ui/geometry")
local UIManager = require("ui/uimanager")
local ReaderUI = require("apps/reader/readerui")
local SQ3 = require("lua-ljsqlite3/init")
local function flush() for _ = 1, 3 do UIManager:_checkTasks(); UIManager:_repaint() end end
local function shot(name) if out then flush(); Device.screen.bb:writePNG(out .. "/" .. name .. ".png") end end

local reader, plugin, announced
local function open()
    ReaderUI:showReader(book); flush()
    reader = assert(ReaderUI.instance, "the test EPUB must open in the reader")
    plugin = assert(reader.dpd, "KOReader must discover dpd.koplugin")
    local vocabulary = assert(reader.vocabbuilder, "the Vocabulary builder must be enabled")
    -- Count what reaches the Vocabulary builder, from DPD or KOReader's dictionary.
    announced = {}
    local original = vocabulary.onWordLookedUp
    vocabulary.onWordLookedUp = function(self, word, ...)
        announced[#announced + 1] = word
        return original(self, word, ...)
    end
end
local function top() local stack = UIManager._window_stack; return stack[#stack].widget end
local function clear()
    plugin:closeViewers(); flush()
    if reader.dictionary.dict_window then reader.dictionary.dict_window:onClose(); flush() end
    reader.highlight:clear(); flush()
    while top() ~= reader do UIManager:close(top()); flush() end
end
-- A real long-press and release on the word's glyphs in the book. `as` is
-- the selection as a PDF or OCR text may deliver it, punctuation included.
local function hold(word, as)
    clear()
    local document = reader.document
    reader.rolling:_gotoPage(1); flush()
    local matches = assert(document:findText(word, 0, 0, false, reader.view.state.page, false, 100, 0), word)
    local m = assert(matches[1], word .. " is not in the test book")
    reader.rolling:_gotoXPointer(m.start); flush()
    local b = assert(document:getScreenBoxesFromPositions(m.start, m["end"], true)[1], "no box for " .. word)
    local pos = reader.view:pageToScreenTransform(document:getCurrentPage(), Geom:new{ x = b.x + b.w / 2, y = b.y + b.h / 2 })
    assert(reader.highlight:onHold(nil, { pos = pos }), "the hold must select " .. word)
    assert(reader.highlight.selected_text.text == word, "the hold must select exactly " .. word)
    if as then reader.highlight.selected_text.text = as end
    reader.highlight:onHoldRelease(); flush()
end
local function saved(word)
    local conn = SQ3.open(DataStorage:getSettingsDir() .. "/vocabulary_builder.sqlite3")
    local stmt = conn:prepare("SELECT prev_context, next_context FROM vocabulary WHERE word = ?")
    local row = stmt:bind(word):step()
    stmt:close(); conn:close()
    return row
end
local function count(word)
    local n = 0
    for _, value in ipairs(announced) do if value == word then n = n + 1 end end
    return n
end

open()
-- The book's checkbox sits right below the default one, in the open reader's menu.
local function bookItem()
    if not reader.menu.tab_item_table then reader.menu:setUpdateItemTable() end
    for _, tab in ipairs(reader.menu.tab_item_table) do
        for _, item in ipairs(tab) do
            if item.id == "dpd" then
                for i, entry in ipairs(item.sub_item_table) do
                    if entry.text == "Open DPD on long-press in this book" then
                        assert(item.sub_item_table[i - 1].text == "Open DPD on long-press by default")
                        return entry
                    end
                end
            end
        end
    end
    error("DPD's long-press checkbox for this book is missing from the reader menu")
end
local book_item = bookItem()
assert(book_item.checked_func() == true and book_item.help_text_func():find("follows the default", 1, true),
    "A new book follows the default, which opens DPD")

-- A DPD hit reaches the Vocabulary builder once, with its sentence context.
hold("pacchima")
assert(plugin.viewer and plugin.viewer.model.query == "pacchima", "pacchima must open DPD")
assert(count("pacchima") == 1, "DPD must announce its lookup exactly once")
local row = assert(saved("pacchima"), "The Vocabulary builder must save a DPD lookup")
assert(row[1] or row[2], "The saved word must keep its sentence context")
shot("vocabulary-hit")
-- A word already saved isn't announced again: no "Vocabulary exists" dialog
-- hidden under the popup and left open after it.
hold("pacchima")
assert(top() == plugin.viewer and UIManager._window_stack[#UIManager._window_stack - 1].widget == reader,
    "A saved word must open DPD with no Vocabulary builder notice beneath it")
assert(count("pacchima") == 1, "A saved word must not be announced again")
shot("vocabulary-saved")
-- Saved as KOReader's dictionary would clean it, not as a second card.
hold("pacchimassa", "pacchimassa,")
assert(plugin.viewer and count("pacchimassa") == 1 and saved("pacchimassa") and not saved("pacchimassa,"),
    "A punctuated selection must be saved as its cleaned word")
-- Handing the word to KOReader's dictionary doesn't announce it either, and
-- a punctuated selection reaches it cleaned, not as a "pacchima," card.
for _, as in ipairs({ false, "pacchima," }) do
    hold("pacchima", as or nil)
    plugin.viewer:onLink("dpd:normal"); flush()
    assert(not plugin.viewer and reader.dictionary.dict_window, "KOReader's dictionary must open pacchima")
    assert(count("pacchima") == 1 and count("pacchima,") == 0 and not saved("pacchima,"),
        "The handoff must not announce pacchima again")
    shot(as and "vocabulary-handoff-punctuated" or "vocabulary-handoff")
end
-- A word DPD lacks goes to KOReader's dictionary, which announces it itself.
hold("plugin")
assert(not plugin.viewer and reader.dictionary.dict_window, "plugin must open KOReader's dictionary")
assert(count("plugin") == 1, "A fallback must be announced once, by KOReader's dictionary")
clear()
-- A long Pāḷi selection with no usable parts follows the same fallback. Feed
-- the selection text through the real hold/release path, as for OCR above.
local long_miss = string.rep("ñ", 18)
hold("plugin", long_miss)
assert(not plugin.viewer and reader.dictionary.dict_window,
    "A long word without known parts must open KOReader's dictionary")
assert(count(long_miss) == 1, "The normal dictionary must announce the long miss exactly once")
reader.dictionary.dict_window:onClose(); flush()
assert(not reader.highlight.selected_text and not plugin.viewer,
    "Closing a long-miss fallback must clear the book selection")
print("PASS: long Pāḷi miss without parts reaches the normal dictionary and cleans up its selection")
clear()

-- Reviewing the saved word opens DPD, without announcing or recording it again.
local function review(word)
    reader.vocabbuilder:onShowVocabBuilder(); flush()
    local widget = assert(reader.vocabbuilder.widget)
    local history, announcements = #plugin:getHistory():list(), #announced
    -- As a review item's callback does (vocabbuilder.koplugin VocabularyBuilderWidget).
    widget.current_lookup_word = word
    reader:handleEvent(Event:new("LookupWord", word, true, nil, nil, nil)); flush()
    assert(plugin.viewer and plugin.viewer.model.query == word, "A review must open DPD")
    assert(#announced == announcements and #plugin:getHistory():list() == history,
        "A review must not be announced or recorded")
    shot("vocabulary-review")
    plugin:closeViewers(); widget:onClose(); flush()
    assert(not reader.vocabbuilder.widget)
end
review("pacchima")

-- Off for this book: long-press uses KOReader's dictionary, and stays off after reopening.
book_item.callback(); flush()
assert(not book_item.checked_func())
assert(reader.doc_settings:readSetting("dpd_direct_lookup") == false)
hold("pacchima")
assert(not plugin.viewer and reader.dictionary.dict_window, "The book's setting must turn DPD off")
clear()
reader:onClose(false); flush()
assert(G_reader_settings:readSetting("dpd").direct_lookup == true, "The global setting must not change")
open()
assert(reader.doc_settings:readSetting("dpd_direct_lookup") == false, "The book's setting must persist")
hold("pacchima")
assert(not plugin.viewer and reader.dictionary.dict_window, "A reopened book must keep DPD off")
clear()
-- Reviews follow the global setting, not the book that happens to be open.
review("pacchima")
-- Back on matches the global setting, so the book follows it again.
book_item = bookItem()
assert(not book_item.checked_func() and book_item.help_text_func():find("its own setting", 1, true))
book_item.callback(); flush()
assert(reader.doc_settings:readSetting("dpd_direct_lookup") == nil)
hold("pacchima")
assert(plugin.viewer, "Following the global setting must turn DPD back on")
clear()
reader:onClose(false); flush()
print("PASS: per-book long-press persists across reopening; DPD lookups reach the Vocabulary builder once, "
    .. "without a notice for saved words, with context and without punctuation; reviews open DPD, also in a book with DPD off; fallbacks are announced by KOReader")
