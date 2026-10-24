-- Capture the README screenshots in desktop KOReader; run by tools/readme_screenshots.py:
-- SDL_VIDEODRIVER=dummy ./luajit readme_capture.lua <plugin> <db> <book.epub> <outdir> <paperwhite|large-type>
-- Book words are long-pressed; other words go through the manual lookup a
-- reader would use, then popup links are followed as a reader would tap them.
-- Both profiles use Paperwhite resolution; larger popup type feeds the slim tiles.
require("setupkoenv")
local root, path, book, out, profile = assert(arg[1]), assert(arg[2]), assert(arg[3]), assert(arg[4]), assert(arg[5])
assert(profile == "paperwhite" or profile == "large-type", "Unknown capture profile")
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
G_reader_settings:saveSetting("dpd", {db_path=path, direct_lookup=true, font_size=20})
G_reader_settings:saveSetting("color_rendering", false)
local Device = require("device")
require("document/canvascontext"):init(Device)
require("ui/bidi").setup()
local Geom = require("ui/geometry")
local UIManager = require("ui/uimanager")
local ReaderUI = require("apps/reader/readerui")
local ffiutil = require("ffi/util")
local function flush() for _=1,3 do UIManager:_checkTasks(); UIManager:_repaint() end end
ReaderUI:showReader(book)
flush()
local reader = assert(ReaderUI.instance)
local plugin = assert(reader.dpd)
local document = reader.document
local Input = require("ui/dpd_input") -- on the path once the plugin has loaded
lfs.mkdir(out)

local function shot(name)
    flush()
    Device.screen.bb:writePNG(out .. "/" .. name .. ".png")
    print("SHOT " .. name)
end
local function clear()
    plugin:closeViewers(); flush()
    if reader.dictionary.dict_window then reader.dictionary.dict_window:onClose(); flush() end
    reader.highlight:clear(); flush()
    for _ = 1, 4 do
        local top = UIManager._window_stack[#UIManager._window_stack]
        if top and top.widget ~= reader then UIManager:close(top.widget); flush() end
    end
end
local function font(size) plugin.settings.font_size = size end
local function hold(word, backdrop)
    clear()
    reader.rolling:_gotoPage(1); flush()
    local matches = assert(document:findText(word, 0, 0, false, reader.view.state.page, false, 100, 0), word)
    local m = assert(matches[1], word .. " not found in the book")
    if #document:getScreenBoxesFromPositions(m.start, m["end"], true) == 0 then
        reader.rolling:_gotoXPointer(m.start); flush()
    end
    local b = assert(document:getScreenBoxesFromPositions(m.start, m["end"], true)[1], "No box for " .. word)
    local pos = reader.view:pageToScreenTransform(document:getCurrentPage(), Geom:new{x=b.x+b.w/2, y=b.y+b.h/2})
    assert(reader.highlight:onHold(nil, {pos=pos}), "Hold did not select " .. word)
    assert(reader.highlight.selected_text.text == word, "Selected the wrong text for " .. word)
    if backdrop then shot(backdrop) end
    reader.highlight:onHoldRelease(); flush()
    assert(plugin.viewer, "DPD did not open for " .. word)
end
-- A word typed into Look up a word and submitted.
local function typed(word, mode)
    clear()
    plugin:lookupInput(word, mode or "pali"); flush()
    assert(plugin.viewer, "DPD did not open for " .. word)
end
-- Follow a rendered popup link. Calling the viewer's handler skips the tap
-- guard that ignores taps right after a rebuild.
local function tap(uri)
    local viewer = assert(plugin.viewer)
    if viewer.action_buttons[uri] then viewer:onLink(uri); flush(); return end
    local box = viewer.scroll.htmlbox_widget
    for n=1,box.page_count do
        local page = box.document:openPage(n)
        local links = page:getPageLinks()
        page:close()
        for _, link in ipairs(links) do
            if link.uri == uri then viewer:onLink(uri); flush(); return end
        end
    end
    error("No rendered link: " .. uri)
end
-- Typing into the lookup dialog, a character at a time, then pausing for suggestions.
local function dialog(text, velthuis)
    clear()
    plugin.settings.velthuis = velthuis or nil
    plugin:inputLookup(false, nil, "pali"); flush()
    local input = assert(plugin.input_dialog)._input_widget
    for ch in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do input:addChars(ch) end
    for _ = 1, 2 do ffiutil.usleep(math.floor((Input.idle_s + 0.3) * 1e6)); flush() end
end

if profile == "large-type" then
    font(30); hold("dhammaṃ"); shot("senses")
    typed("dhammacakkappavattanasutta"); tap("dpd:sense/34679"); tap("dpd:detail-sutta/34679"); shot("sutta")
    typed("citta"); tap("dpd:sense/26555"); tap("dpd:detail-family/26555/2"); shot("family-word")
    typed("rūpa"); tap("dpd:sense/55151"); tap("dpd:detail-family/55151/2"); shot("family")
    font(24); typed("peace", "english"); shot("find-english")
    typed("khamma")
    local frame = plugin.viewer.navigation:current()
    for i = #(frame.suggestions or {}), 1, -1 do
        if frame.suggestions[i].open then tap("dpd:similar/" .. i) end
    end
    shot("find-similar")
else
    -- Hero
    font(20); hold("sīlasamādhipaññāvimuttivimuttiñāṇadassanasampannā", "compound-book"); shot("compound")
    typed("mettā"); tap("dpd:sense/53212"); tap("dpd:detail-paradigm/53212"); shot("declension")
    typed("bhāveti"); tap("dpd:sense/49849"); tap("dpd:detail-paradigm/49849"); shot("conjugation")
    -- Find any word
    font(16); typed("peace", "english"); shot("english")
    typed("khamma")
    -- The first similar forms open by themselves; shut them to show the list.
    local frame = plugin.viewer.navigation:current()
    for i = #(frame.suggestions or {}), 1, -1 do
        if frame.suggestions[i].open then tap("dpd:similar/" .. i) end
    end
    shot("similar")
    typed("butdha"); shot("spelling")
    dialog("sati"); shot("suggestions")
    dialog("sa.msaara", true); shot("velthuis")
    clear()
    plugin.settings.velthuis = nil
    local history = plugin:getHistory()
    history:clear()
    for _, word in ipairs({"nibbāna", "magga", "nirodha", "samudaya", "dukkha"}) do history:add(word) end
    plugin:inputLookup(true); shot("recent")
    -- Go deeper
    typed("bhikkhū"); tap("dpd:sense/49885"); tap("dpd:detail-frequency/49885"); shot("frequency")
    font(20); typed("√gam"); tap("dpd:root-matrix/1"); shot("matrix")
    font(16)
    plugin.settings.dictionaries = {"dppn", "cpd", "pts", "nyanatiloka", "peu", "bhs", "mw", "apte", "wordnet"}
    hold("kāye"); tap("dpd:dictionaries"); shot("dictionaries")
    plugin.settings.dictionaries = nil
    -- Extra hero capture comes last to preserve the other workflows and history.
    font(20); hold("dhammaṃ"); shot("hero-senses")
end
clear()
plugin:onCloseDocument()
print("DONE")
os.exit(0)
