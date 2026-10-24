-- From desktop KOReader with a disposable profile:
-- SDL_VIDEODRIVER=dummy KO_MULTIUSER=1 XDG_CONFIG_HOME=<temporary directory> \
-- ./luajit <plugin>/tools/check_ux.lua <plugin> <mobile.db> [screenshots]
-- Repeat at DPD_TEST_FONT_SIZE=16, 20 and 26 (and 26 in landscape). Uses real UI, SQLite and MuPDF.
require("setupkoenv")
local root, path = assert(arg[1]), assert(arg[2])
package.path = root .. "/?.lua;" .. package.path
G_defaults = require("luadefaults"):open()
G_reader_settings = require("luasettings"):wrap({})
local Device = require("device")
require("document/canvascontext"):init(Device)
require("ui/bidi").setup()
local UIManager = require("ui/uimanager")
local Geom = require("ui/geometry")
local Input = require("ui/dpd_input")
local DPD = require("main")
local Viewer = require("ui/dpd_viewer")
Viewer.link_guard_s = 0 -- existing check_learning covers the guard
local font_size = tonumber(os.getenv("DPD_TEST_FONT_SIZE")) or 16
local function flush() UIManager:_checkTasks(); UIManager:_repaint() end
local function top() return UIManager._window_stack[#UIManager._window_stack].widget end
local function shown(widget)
    for _,window in ipairs(UIManager._window_stack) do if window.widget == widget then return true end end
    return false
end
local function button(widget, label)
    for _,row in ipairs(widget.buttons_layout or widget.buttons or {}) do
        for _,item in ipairs(row) do if item.text == label then return item end end
    end
    for _,child in ipairs(widget) do
        local found = button(child, label)
        if found then return found end
    end
end
local function press(widget, label)
    assert(button(widget, label), label).callback(); flush()
end
local function screenshot(name)
    if arg[3] then Device.screen.bb:writePNG(arg[3] .. "/" .. name .. ".png") end
end
local function pause()
    require("ffi/util").usleep(math.floor((Input.idle_s + .15) * 1e6)); flush()
end
local FileManager = require("apps/filemanager/filemanager")
FileManager:showFiles(assert(path:match("^(.*)/[^/]+$"))); flush()
-- Dismiss first-run notices from the disposable host before testing DPD.
while #UIManager._window_stack > 1 do UIManager:close(top()); flush() end
local plugin = setmetatable({settings={db_path=path .. ".missing",font_size=font_size},
    ui=assert(FileManager.instance)}, {__index=DPD})
plugin:inputLookup(false, "  ~naa.na  ", "english"); flush()
-- The recovery title names DB.new's reason, which the reader can act on.
local missing_reason = "DPD database not found or unreadable: " .. path .. ".missing"
local recovery = top()
assert(recovery.title == missing_reason and not plugin.input_dialog, recovery.title)
screenshot("database-recovery")
press(recovery, "Cancel")
assert(not shown(recovery) and not plugin.input_dialog)
-- Database status is a detour: dismissing its error returns to recovery.
plugin:inputLookup(false, "  ~naa.na  ", "english"); flush()
press(top(), "Database status")
assert(top().text:find(missing_reason, 1, true) == 1)
UIManager:close(top()); flush()
recovery = top()
assert(recovery.title == missing_reason and not plugin.input_dialog)
press(recovery, "Choose database file")
local chooser = top()
assert(chooser.onConfirm)
chooser.onConfirm(path .. ".missing"); flush()
assert(top().text:find(missing_reason, 1, true) == 1)
assert(not plugin.input_dialog and plugin.settings.db_path == path .. ".missing")
-- Dismiss the invalid-file notice, then simulate confirming a valid file.
UIManager:close(top()); UIManager:close(chooser); flush()
chooser.onConfirm(path); flush()
local dialog = plugin.input_dialog
assert(shown(dialog) and dialog:getInputText() == "  ~naa.na  " and dialog.mode == "english")
press(dialog, "Cancel")
plugin:showHelp(); flush()
assert(top().title == "DPD help")
screenshot("help")
UIManager:close(top()); flush()

-- Distinct status copy occupies the same reserved area; ordinary lookup works.
for _,case in ipairs({
    {name="empty",suggest=function() return {} end,text="No suggestions"},
    {name="unavailable",suggest=function() return nil,"unavailable" end,text="check Database status"},
    {name="error",suggest=function() error("test diagnostic") end,text="Suggestions failed"},
}) do
    local submitted
    dialog = Input.show{settings={},suggest=case.suggest,on_lookup=function(text) submitted=text end}
    flush()
    local area, height = dialog.suggestion_area, dialog.suggestion_area:getSize().h
    dialog:setInputText("unknown"); pause()
    assert(area[1].text:find(case.text,1,true))
    assert(area:getSize().h == height and area[1]:getSize().h <= height, "status fits reserved height")
    screenshot("suggestions-" .. case.name)
    press(dialog, "Look up")
    assert(submitted == "unknown" and not shown(dialog))
end
dialog = Input.show{settings={},suggest=function() error("ID must not query") end,on_lookup=function() end}
flush(); dialog:setInputText("12345"); pause()
assert(dialog.suggestion_area[1].text == nil)
press(dialog, "Cancel")

local lookup = plugin:ensureLookup()
local viewer = Viewer:new{model=lookup:otherDictionaries({query="kamma"},{"cpd"}),lookup=lookup,font_size=font_size}
UIManager:show(viewer); flush()
local function tap(uri, padding)
    local box = viewer.scroll.htmlbox_widget
    for number=1,box.page_count do
        local page = box.document:openPage(number)
        local links = page:getPageLinks(); page:close()
        for _,link in ipairs(links) do
            if link.uri == uri then
                viewer.scroll:scrollToRatio((number-.9)/box.page_count); flush()
                local cell = viewer.control_layout.buttons[uri]
                local x = (link.x0+link.x1)/2
                if padding then x = cell and (x - cell.width_em * viewer.font_px / 2 + 3) or 3 end
                local pos = Geom:new{x=box.dimen.x+x,y=box.dimen.y+(link.y0+link.y1)/2}
                assert(viewer:linkAt(box,pos) and viewer:linkAt(box,pos).uri == uri, "padding routes to " .. uri)
                assert(box:onTapText(nil,{pos=pos})); flush()
                return
            end
        end
    end
    error("missing rendered link " .. uri)
end
local frame = viewer.navigation:current()
local group = frame.model.dictionaries.groups[1]
local selected
for index,entry in ipairs(group.entries) do
    local loaded = lookup:dictionaryPage(entry.id,0)
    if loaded.has_more then selected=index;break end
end
local key = "1/" .. assert(selected)
tap("dpd:dict-entry/" .. key)
assert(viewer.scroll.html_body:find("Part 1",1,true))
print("LAYOUT dictionary part 1: " .. viewer.scroll.htmlbox_widget.page_count .. " pages")
local part = frame.dictionary_pages[key]
local old_html = part.html
screenshot("dictionary-part-1")
tap("dpd:dict-next/" .. key,true)
assert(frame.dictionary_pages[key].part == 2)
screenshot("dictionary-part-2")
tap("dpd:dict-prev/" .. key,true)
assert(frame.dictionary_pages[key].part == 1 and frame.dictionary_pages[key].html == old_html)
viewer:close();flush()

viewer = Viewer:new{model=lookup:get("saṃmantayitvā"),lookup=lookup,font_size=font_size}
UIManager:show(viewer);flush()
frame=viewer.navigation:current()
assert(#frame.suggestions > 1 and frame.suggestions[1].open and frame.suggestions[2].open)
print("LAYOUT similar open: " .. viewer.scroll.htmlbox_widget.page_count .. " pages")
screenshot("similar-open")
tap("dpd:similar/1")
assert(not frame.suggestions[1].open and frame.suggestions[2].open)
print("LAYOUT similar first collapsed: " .. viewer.scroll.htmlbox_widget.page_count .. " pages")
screenshot("similar-collapsed")
viewer:close();flush()

viewer=Viewer:new{model=lookup:paradigm(lookup:get("sabba").senses[1].id,"sabba"),lookup=lookup,font_size=font_size}
UIManager:show(viewer);flush()
assert(viewer.scroll.html_body:find('class="form"',1,true))
print("LAYOUT sabba paradigm: " .. viewer.scroll.htmlbox_widget.page_count .. " pages")
screenshot("paradigm-spacing")
viewer:close();flush()
viewer=Viewer:new{model=lookup:rootMatrix("√gam",1,1),lookup=lookup,font_size=font_size}
UIManager:show(viewer);flush()
assert(viewer.scroll.html_body:find('<p><a href="dpd:matrix-item/',1,true))
print("LAYOUT matrix row: " .. viewer.scroll.htmlbox_widget.page_count .. " pages")
screenshot("matrix-spacing")
viewer:close();flush()
plugin:closeDatabase()
print("PASS: native recovery/retry, help, fixed-height suggestion states, pager padding/part replacement, candidate disclosure and dense-link renders at font " .. font_size)
