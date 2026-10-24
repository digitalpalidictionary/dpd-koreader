-- Run from a disposable desktop KOReader extraction, with KO_MULTIUSER=1 and
-- XDG_CONFIG_HOME pointing to a disposable directory:
-- SDL_VIDEODRIVER=dummy ./luajit <plugin>/tools/check_reader.lua <plugin> <db> "$DPD_BOOK"
-- Use a fresh temporary EPUB copy with no .sdr for each run; see
-- docs/KOREADER_RUNBOOK.md for the DPD_BOOK setup.
require("setupkoenv")
local root, path, book = assert(arg[1]), assert(arg[2]), assert(arg[3])
G_defaults = require("luadefaults"):open()
local DataStorage = require("datastorage")
G_reader_settings = require("luasettings"):open(DataStorage:getDataDir() .. "/settings.reader.lua")
local lfs = require("libs/libkoreader-lfs")
local disabled = {}
for entry in lfs.dir("plugins") do
    if entry:sub(-9)==".koplugin" then disabled[entry:sub(1,-10)]=true end
end
G_reader_settings:saveSetting("plugins_disabled", disabled)
G_reader_settings:saveSetting("extra_plugin_paths", { assert(root:match("^(.+)/[^/]+$")) })
G_reader_settings:saveSetting("dpd", {db_path=path,direct_lookup=true})
G_reader_settings:saveSetting("dict_font_size", 26)
local Device = require("device")
require("document/canvascontext"):init(Device)
require("ui/bidi").setup()
local UIManager = require("ui/uimanager")
local ReaderUI = require("apps/reader/readerui")
local function flush() UIManager:_checkTasks(); UIManager:_repaint() end
ReaderUI:showReader(book)
flush(); flush()
local reader = assert(ReaderUI.instance, "test EPUB must open in the actual reader")
local plugin = assert(reader.dpd, "KOReader must discover and instantiate dpd.koplugin")
-- DPD is on Search's first page, right after KOReader's own dictionary items,
-- once, however many times the plugin is instantiated.
for _, name in ipairs({"ui/elements/reader_menu_order", "ui/elements/filemanager_menu_order"}) do
    local search, at, count = require(name).search, nil, 0
    for i, id in ipairs(search) do
        if id == "dpd" then at, count = i, count + 1 end
    end
    assert(count == 1 and search[at - 1] == "vocabbuilder", name .. ": DPD not placed after Vocabulary builder")
end
local search_menu
if not reader.menu.tab_item_table then reader.menu:setUpdateItemTable() end
for _, tab in ipairs(reader.menu.tab_item_table) do
    for _, item in ipairs(tab) do if item.id == "dpd" then search_menu = tab end end
end
assert(search_menu, "DPD missing from the reader menu")
local dpd_row
for i, item in ipairs(search_menu) do if item.id == "dpd" then dpd_row = i end end
assert(search_menu[dpd_row - 1].id == "vocabbuilder" or search_menu[dpd_row - 1].id == "dictionary_lookup_history",
    "DPD not beside the dictionary items in the built Search menu")
assert(reader.dictionary._dict_buttons.dpd)
assert(reader.highlight._highlight_buttons["06_dpd"])
reader.dictionary:onLookupWord("pacchima",false,nil,reader.highlight)
flush()
assert(plugin.viewer and #plugin.viewer.model.senses==8)
assert(plugin.settings.font_size==16 and plugin.viewer.font_size==16,
    "DPD must default to 16 independently of the normal dictionary font")
assert(plugin.viewer.scroll.default_font_size==Device.screen:scaleBySize(16))
plugin.viewer:close(); flush()
reader.dictionary:onLookupWord("vajjakammappabhedanti",false,nil,reader.highlight)
flush(); assert(plugin.viewer and #plugin.viewer.model.deconstructions==5)
plugin.viewer:close(); flush()
for _, word in ipairs({"saṃvidāvahāro", "avaharissāmā", "saṃmantayitvā", "indakhile", "vanditva", "dham­ma"}) do
    reader.dictionary:onLookupWord(word,false,nil,reader.highlight)
    flush(); assert(plugin.viewer, word .. " must remain in the DPD plugin")
    if word ~= "saṃvidāvahāro" and word ~= "dham­ma" then assert(#plugin.viewer.model.suggestions > 0) end
    if word == "indakhile" or word == "avaharissāmā" then
        assert(plugin.viewer.model.single_suggestion)
        assert(not plugin.viewer.scroll.html_body:find("dpd:suggestion/1",1,true))
    end
    plugin.viewer:close(); flush()
end
reader.dictionary:onLookupWord("uyyokhajja",false,nil,reader.highlight)
flush();assert(not plugin.viewer,"unrescued variant-only selections must reach the normal dictionary")
plugin:showLookup("uyyokhajja")
flush();assert(plugin.viewer and plugin.viewer.navigation:current().variants_open)
plugin.viewer:close();flush()
reader.dictionary:onLookupWord("dpdtestnomatch",false,nil,reader.highlight)
flush(); assert(not plugin.viewer and reader.dictionary.highlight==reader.highlight)
-- Exercise the real dictionary-popup button API, including custom layouts.
reader.dictionary:showDict("pacchima", {{dict="Test dictionary",definition="Test definition"}})
flush()
local popup = assert(reader.dictionary.dict_window)
local button = assert(popup.button_table.button_by_id.dpd, "DPD button must be visible")
button.callback(); flush(); assert(plugin.viewer)
plugin.viewer:close(); popup:onClose(); flush()
plugin.settings.direct_lookup=false; plugin:syncDirectMode()
assert(reader.dictionary.onLookupWord==require("apps/reader/modules/readerdictionary").onLookupWord)
-- Plugin management stops the instance in-session: its buttons must go and no
-- remaining entry point may reopen the database before KOReader restarts.
plugin:stopPlugin(); flush()
assert(not reader.dictionary._dict_buttons.dpd and not reader.highlight._highlight_buttons["06_dpd"])
assert(not plugin:showLookup("pacchima") and not plugin.db and not plugin.viewer)
flush()
print("PASS: EPUB opening, real plugin discovery, Search menu placement, ReaderDictionary direct lookup/fallback, dictionary-popup button and in-session stop")
