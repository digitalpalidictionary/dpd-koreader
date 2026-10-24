-- Screenshots of the screens the checks do not capture, for a design review:
-- reader popups, every other dictionary, a long article mid-part, the DPD menu
-- and its submenus, Gesture manager's DPD actions, dictionary details, status,
-- About, Help, confirmations, diagnostics and the input dialog. Asserts nothing beyond reaching each screen; a step that
-- cannot is reported as STEPFAIL and the rest still run. The book is the
-- README passage (tools/readme_screenshots.py write_book). From a desktop
-- KOReader directory, with a disposable KO_MULTIUSER=1/XDG_CONFIG_HOME:
-- SDL_VIDEODRIVER=dummy DPD_TEST_FONT_SIZE=20 \
--   ./luajit <plugin>/tools/capture_screens.lua <plugin> <db> "$DPD_BOOK" <outdir>
-- DPD_BOOK must be a fresh temporary EPUB with no .sdr for each run; see
-- docs/KOREADER_RUNBOOK.md for the generated README-passage book setup.
-- The plugin directory's name must end in .koplugin for KOReader to load it.
require("setupkoenv")
local root, path, book, out = assert(arg[1]), assert(arg[2]), assert(arg[3]), assert(arg[4])
G_defaults = require("luadefaults"):open()
local DataStorage = require("datastorage")
G_reader_settings = require("luasettings"):open(DataStorage:getDataDir() .. "/settings.reader.lua")
local lfs = require("libs/libkoreader-lfs")
-- Gestures stays on: its Gesture manager lists DPD's actions.
local disabled = {}
for entry in lfs.dir("plugins") do
    if entry:sub(-9) == ".koplugin" and entry ~= "gestures.koplugin" then disabled[entry:sub(1,-10)] = true end
end
G_reader_settings:saveSetting("plugins_disabled", disabled)
G_reader_settings:saveSetting("extra_plugin_paths", {assert(root:match("^(.+)/[^/]+$"))})
G_reader_settings:saveSetting("dpd", {db_path=path, direct_lookup=true, font_size=tonumber(os.getenv("DPD_TEST_FONT_SIZE")) or 20})
G_reader_settings:saveSetting("color_rendering", false)
local Device = require("device")
require("document/canvascontext"):init(Device)
require("ui/bidi").setup()
local Geom = require("ui/geometry")
local UIManager = require("ui/uimanager")
local ReaderUI = require("apps/reader/readerui")
local function flush() for _=1,3 do UIManager:_checkTasks(); UIManager:_repaint() end end
ReaderUI:showReader(book)
flush()
local reader = assert(ReaderUI.instance)
local plugin = assert(reader.dpd)
local document = reader.document
lfs.mkdir(out)
local function shot(name) flush(); Device.screen.bb:writePNG(out .. "/" .. name .. ".png"); print("SHOT " .. name) end
local function closeTop()
    local stack = UIManager._window_stack
    local top = stack[#stack]
    if top and top.widget ~= reader then UIManager:close(top.widget); flush() end
end
local function clear()
    plugin:closeViewers(); flush()
    if reader.dictionary.dict_window then reader.dictionary.dict_window:onClose(); flush() end
    reader.highlight:clear(); flush()
    for _ = 1, 6 do closeTop() end
end
local function hold(word)
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
    reader.highlight:onHoldRelease(); flush()
    assert(plugin.viewer, "DPD did not open for " .. word)
end
local function tap(uri) plugin.viewer:onLink(uri); flush() end
local function step(name, fn)
    local ok, err = pcall(fn)
    if not ok then print("STEPFAIL " .. name .. ": " .. tostring(err)) end
end

step("reader-popup", function() hold("dhammaṃ"); shot("reader-dhammam") end)
step("reader-compound", function() hold("vissajjiyavebhaṅgiyaṃ"); shot("reader-compound") end)
step("dict-all", function()
    plugin.settings.dictionaries_off = {}
    hold("dhammaṃ"); tap("dpd:dictionaries"); shot("dict-all-1")
    local scroll = plugin.viewer.scroll
    for page = 2, 4 do
        scroll:scrollToRatio((page - 1 + .1) / scroll.htmlbox_widget.page_count); flush(); shot("dict-all-" .. page)
    end
end)
step("dict-kaye", function() hold("kāye"); tap("dpd:dictionaries"); shot("dict-kaye-1")
    local scroll = plugin.viewer.scroll
    scroll:scrollToRatio((1 + .1) / scroll.htmlbox_widget.page_count); flush(); shot("dict-kaye-2")
end)
step("dict-bhikkhu-open", function()
    hold("bhikkhū"); tap("dpd:dictionaries")
    tap("dpd:dict-entry/1/1"); shot("dict-bhikkhu-open")
end)
step("dict-none", function()
    plugin.settings.dictionaries_off = {"dppn", "cpd", "pts", "nyanatiloka", "peu", "bhs", "mw", "wordnet"}
    hold("saṃmantayitvā"); tap("dpd:dictionaries"); shot("dict-none")
end)
-- The first article with more than one part, part 2, half-way down: the
-- footer's part buttons in the middle of a long article.
step("dict-article-mid", function()
    plugin.settings.dictionaries_off = {}
    hold("dhammaṃ"); tap("dpd:dictionaries")
    local frame = plugin.viewer.navigation:current()
    for key in plugin.viewer.scroll.html_body:gmatch("dpd:dict%-entry/(%d+/%d+)") do
        tap("dpd:dict-entry/" .. key)
        if frame.dictionary_pages[key].has_more then
            tap("dpd:dict-next/" .. key)
            local scroll = plugin.viewer.scroll
            local count = scroll.htmlbox_widget.page_count
            scroll:scrollToRatio((math.floor(count / 2) + .1) / count); flush(); shot("dict-article-mid")
            return
        end
        tap("dpd:dict-entry/" .. key)
    end
    error("no article with more than one part")
end)
plugin.settings.dictionaries_off = nil
step("family", function() hold("dhammaṃ"); tap("dpd:sense/34628"); shot("sense-open")
    tap("dpd:detail-family/34628/3"); shot("family-idioms") end)
step("root", function() hold("gacchati"); shot("reader-gacchati") end)

-- Menus and dialogs.
local function searchTab()
    reader.menu:onShowMenu(); flush()
    local container = reader.menu.menu_container
    local menu = container[1]
    for i, tab in ipairs(menu.tab_item_table) do
        if tab.icon == "appbar.search" then menu:switchMenuTab(i); flush(); return menu end
    end
    error("no search tab")
end
local function findItem(menu, text)
    for _, item in ipairs(menu.item_table) do
        local label = item.text or (item.text_func and item.text_func())
        if label == text then return item end
    end
    error("no menu item " .. text)
end
step("menu-search", function()
    clear(); local menu = searchTab(); shot("menu-search-tab")
    menu:onMenuSelect(findItem(menu, "Digital Pāḷi Dictionary")); shot("menu-dpd")
    menu:onMenuSelect(findItem(menu, "Other dictionaries")); shot("menu-dictionaries")
    menu:onBack(); flush()
    menu:onMenuSelect(findItem(menu, "Recent lookups")); shot("menu-recent")
    menu:onBack(); flush()
    menu:onMenuSelect(findItem(menu, "Database: ready")); shot("menu-database")
    menu:onBack(); flush()
    menu:onMenuSelect(findItem(menu, "Help")); shot("menu-help")
    menu:onMenuSelect(findItem(menu, "Diagnostics")); shot("menu-diagnostics")
    menu:onBack(); flush(); menu:onBack(); flush()
    menu:onMenuSelect(findItem(menu, "Display and input")); shot("menu-display")
    menu:onMenuSelect(findItem(menu, "Popup font size: " .. plugin.settings.font_size)); shot("font-size-spin")
end)
-- Gesture manager's action lists for one gesture, on the page with DPD's
-- actions, and the notice the per-book long-press toggle shows.
local function showPage(menu, text)
    for i, item in ipairs(menu.item_table) do
        if (item.text or (item.text_func and item.text_func())) == text then
            menu:updateItems(math.ceil(i / menu.perpage)); flush(); return
        end
    end
    error("no menu item " .. text)
end
step("gestures", function()
    clear(); reader.menu:onShowMenu(); flush()
    local menu = reader.menu.menu_container[1]
    for i, tab in ipairs(menu.tab_item_table) do
        if tab.icon == "appbar.settings" then menu:switchMenuTab(i); flush() end
    end
    menu:onMenuSelect({ text = "Bottom left", sub_item_table = assert(reader.gestures):genMenu("tap_left_bottom_corner") })
    menu:onMenuSelect(findItem(menu, "General")); showPage(menu, "DPD: Look up a word"); shot("gesture-general")
    menu:onBack(); flush()
    menu:onMenuSelect(findItem(menu, "Reader")); showPage(menu, "DPD: Toggle long-press in this book")
    shot("gesture-reader")
    clear(); plugin:onDPDToggleBookLongPress(); shot("gesture-toggle-notice")
    plugin:onDPDToggleBookLongPress(); clear()
end)
step("dict-hold", function() clear(); plugin:ensureLookup()
    UIManager:show(require("ui/widget/infomessage"):new{text=plugin:dictionaryDetails("peu")}); shot("dict-details-peu") end)
step("status", function() clear(); plugin:databaseStatus(); shot("database-status") end)
step("about", function() clear(); plugin:aboutLicenses(); shot("about") end)
step("help", function() clear(); plugin:showHelp(); shot("help") end)
step("history-clear", function() clear(); plugin:getHistory():add("dhamma"); plugin:clearHistory(); shot("history-clear-confirm") end)
step("history-off", function() clear(); plugin:getHistory():add("dhamma"); plugin:toggleHistory(); shot("history-off-confirm") end)
step("diag-on", function() clear(); plugin:diagnosticsMenu().sub_item_table[1].callback(); shot("diagnostics-on")
    require("dpd/diag").setEnabled(false) end)
step("input", function() clear(); plugin:inputLookup(); shot("input-empty") end)
step("dict-popup-dpd", function()
    clear(); plugin.settings.direct_lookup = false; plugin:syncDirectMode()
    reader.dictionary:onLookupWord("dhamma"); flush(); shot("koreader-dict-popup")
end)
clear()
plugin:onCloseDocument()
print("DONE")
os.exit(0)
