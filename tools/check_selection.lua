-- Run in desktop KOReader with KO_MULTIUSER=1 and disposable XDG_CONFIG_HOME:
-- SDL_VIDEODRIVER=dummy ./luajit <plugin>/tools/check_selection.lua <plugin> <db> "$DPD_BOOK" [screenshots]
-- Use a fresh temporary EPUB copy with no .sdr for each run; see
-- docs/KOREADER_RUNBOOK.md for the DPD_BOOK setup.
-- Observe CRe/ReaderHighlight selection boundaries; do not widen reader words.
require("setupkoenv")
local root, path, book = assert(arg[1]), assert(arg[2]), assert(arg[3])
G_defaults = require("luadefaults"):open()
local DataStorage = require("datastorage")
G_reader_settings = require("luasettings"):open(DataStorage:getDataDir() .. "/settings.reader.lua")
local lfs = require("libs/libkoreader-lfs")
local disabled = {}
for entry in lfs.dir("plugins") do
    if entry:sub(-9) == ".koplugin" then disabled[entry:sub(1,-10)] = true end
end
G_reader_settings:saveSetting("plugins_disabled", disabled)
G_reader_settings:saveSetting("extra_plugin_paths", {assert(root:match("^(.+)/[^/]+$"))})
G_reader_settings:saveSetting("dpd", {db_path=path, direct_lookup=true})
local Device = require("device")
require("document/canvascontext"):init(Device)
require("ui/bidi").setup()
local Geom = require("ui/geometry")
local UIManager = require("ui/uimanager")
local ReaderUI = require("apps/reader/readerui")
local function flush() UIManager:_checkTasks(); UIManager:_repaint() end
ReaderUI:showReader(book)
flush(); flush()
local reader = assert(ReaderUI.instance)
local plugin = assert(reader.dpd)
local document = reader.document
local screenshot_dir = arg[4]
if screenshot_dir then lfs.mkdir(screenshot_dir) end
local function screenshot(name)
    if screenshot_dir then Device.screen.bb:writePNG(screenshot_dir .. "/" .. name .. ".png") end
end
local function clearPopups()
    if plugin.viewer then plugin.viewer:close(); flush() end
    if reader.dictionary.dict_window then reader.dictionary.dict_window:onClose(); flush() end
    reader.highlight:clear()
end
local function countCharacters(text)
    local count = 0
    for _ in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do count = count + 1 end
    return count
end
local function advance(pointer, offset)
    local prefix, index = pointer:match("^(.*%.)(%d+)$")
    assert(prefix, "Unexpected CRe text XPointer: " .. pointer)
    return prefix .. (tonumber(index) + offset)
end
local function boxesFor(pointer, offset, length)
    return document:getScreenBoxesFromPositions(advance(pointer, offset), advance(pointer, offset + length), true)
end

local cases = {"bhikkhave’ti", "yo’dha", "tass’eva", "akaṭa-anudhammena", "akaṇha-asukkaṃ", "dhammā",
    "saṃvidāvahāro", "avaharissāmā", "saṃmantayitvā", "indakhile"}
local split_count = 0
for case_index, word in ipairs(cases) do
    clearPopups()
    reader.rolling:_gotoPage(1)
    flush()
    local matches = assert(document:findText(word, 0, 0, false, reader.view.state.page, false, 100, 0), word)
    local match = assert(matches[1], word .. " not found in fixture")
    reader.rolling:_gotoXPointer(match.start)
    flush(); flush()
    document:clearSelection()
    local complete_model = plugin:getModel(word)
    assert(complete_model.found, "The complete fixture form must resolve when selected across its boundaries: " .. word)
    print("COMPLETE_FORM word=" .. word .. " query=" .. complete_model.query
        .. " via=" .. tostring(complete_model.matched_via))
    local delimiter = word:find("’",1,true) or word:find("-",1,true)
    local offsets = delimiter and {
        {label="left",offset=countCharacters(word:sub(1,delimiter - 1)) - 1},
        {label="right",offset=countCharacters(word:sub(1,delimiter - 1)) + 1},
    } or {{label="middle",offset=math.floor(countCharacters(word)/2)}}
    for _, sample in ipairs(offsets) do
        clearPopups()
        local boxes = boxesFor(match.start, sample.offset, 1)
        assert(#boxes > 0, word .. ": no on-screen glyph box for " .. sample.label)
        local box = boxes[1]
        local page_position = Geom:new{x=box.x + box.w/2, y=box.y + box.h/2}
        local position = reader.view:pageToScreenTransform(document:getCurrentPage(), page_position)
        local selected = assert(document:getWordFromPosition(page_position, true), word)
        assert(reader.highlight:onHold(nil, {pos=position}), word .. ": hold did not select text")
        local held = assert(reader.highlight.selected_text).text
        assert(held == selected.word, "ReaderHighlight differs from CRe word selection")
        local whole = held == word
        if not whole then split_count = split_count + 1 end
        flush()
        screenshot("selection-" .. case_index .. "-" .. sample.label)
        reader.highlight:lookupDictWord()
        flush()
        local viewer = plugin.viewer
        local lookup_model = plugin:getModel(held)
        if lookup_model.found then
            assert(viewer and viewer.model.original == held, "Selected text did not reach DPD unchanged")
        else assert(not viewer, "An unmatched selection must use the normal dictionary") end
        if case_index >= 7 then
            assert(whole and viewer, "Previously reported complete selection must stay in DPD: " .. word)
            if word ~= "saṃvidāvahāro" then assert(#viewer.model.suggestions > 0) end
            if word == "indakhile" then
                assert(viewer.model.single_suggestion)
                assert(not viewer.scroll.html_body:find("dpd:suggestion/1",1,true))
            end
        end
        print(string.format("SELECTION word=%s side=%s page=%d x=%.1f y=%.1f selected=%s whole=%s dpd=%s xp0=%s xp1=%s",
            word, sample.label, document:getCurrentPage(), position.x, position.y, held,
            tostring(whole), tostring(viewer ~= nil), selected.pos0, selected.pos1))
        screenshot("lookup-" .. case_index .. "-" .. sample.label)
    end
end
clearPopups()
plugin:onCloseDocument()
print("PASS: actual CRe glyph boxes, ReaderHighlight hold selections and dictionary dispatch; "
    .. split_count .. " samples differ from the complete fixture form (reader boundary observations, not plugin lookup failures)")
