-- Native HTML link focus, key dispatch, paging and reflow regression.
-- ./luajit <plugin>/tools/check_keyboard.lua <plugin> <db> [screenshots]
require("setupkoenv")
local root, path = assert(arg[1]), assert(arg[2])
package.path = root .. "/?.lua;" .. package.path
G_defaults = require("luadefaults"):open()
G_reader_settings = require("luasettings"):wrap({})
local Device = require("device")
require("document/canvascontext"):init(Device)
require("ui/bidi").setup()
local UIManager = require("ui/uimanager")
local Event = require("ui/event")
local Key = require("device/key")
local Geom = require("ui/geometry")
local Viewer = require("ui/dpd_viewer")
local db = require("dpd/db").new(path)
local lookup = require("dpd/lookup").new(db)
local function flush() UIManager:_checkTasks(); UIManager:_repaint() end
local function shot(name)
    if arg[3] then Device.screen.bb:writePNG(arg[3] .. "/" .. name .. ".png") end
end
local function key(viewer, name, modifiers)
    assert(viewer:handleEvent(Event:new("KeyPress", Key:new(name, modifiers or {}))), name)
end
local function focusUri(viewer, uri)
    for _ = 1, 1000 do
        key(viewer,"Tab")
        if viewer.keyboard_focus and viewer.keyboard_focus.target.uri == uri then return end
    end
    error("keyboard target missing: " .. uri)
end
assert(Device:hasKeys(), "desktop keyboard required")
local viewer = Viewer:new{model=lookup:get("dhamma"),lookup=lookup,
    font_size=tonumber(os.getenv("DPD_TEST_FONT_SIZE")) or 26,normal_callback=function() end,
    edit_callback=function() end}
UIManager:show(viewer); flush(); shot("keyboard-before")
key(viewer,"Tab"); flush(); shot("keyboard-link-focus")
local first = assert(viewer.keyboard_focus).target.uri
assert(viewer.keyboard_focus.target.rects, "rendered link receives initial focus")
key(viewer,"Right")
assert(viewer.keyboard_focus.target.uri ~= first, "Right moves focus")
key(viewer,"Left"); assert(viewer.keyboard_focus.target.uri == first)
key(viewer,"Down"); key(viewer,"Up"); assert(viewer.keyboard_focus.target.uri == first)
key(viewer,"Tab"); key(viewer,"Tab",{Shift=true}); assert(viewer.keyboard_focus.target.uri == first)

local original, followed = viewer.onLink, {}
viewer.onLink = function(_, uri) followed[#followed+1]=uri end
key(viewer,"Press"); key(viewer,"Return")
assert(#followed == 2 and followed[1] == first and followed[2] == first, "one dispatch per activation key")
-- Touch still dispatches the same native link with a keyboard focus present.
local box = viewer.scroll.htmlbox_widget
local rect = viewer.keyboard_focus.target.rects[1]
viewer.built_at=nil
assert(box:onTapText(nil,{pos=Geom:new{x=box.dimen.x+(rect.x0+rect.x1)/2,
    y=box.dimen.y+(rect.y0+rect.y1)/2}}))
assert(#followed == 3 and followed[3] == first, "touch link dispatch preserved")
viewer.onLink=original

local id = viewer.navigation:current().model.senses[1].id
focusUri(viewer,"dpd:sense/" .. id)
key(viewer,"Return")
assert(viewer._pending_update, "activation queues one rebuild")
key(viewer,"Return"); key(viewer,"Tab")
flush()
assert(viewer.navigation:current().expanded[id], "repeated activation during pending rebuild is ignored")
assert(not viewer.keyboard_focus, "expansion clears old rectangles")
focusUri(viewer,"dpd:detail-paradigm/" .. id)
key(viewer,"Press"); flush()
assert(#viewer.navigation.stack == 2 and not viewer.keyboard_focus, "keyboard opens detail")
key(viewer,"Tab"); key(viewer,"Back"); flush()
assert(#viewer.navigation.stack == 1 and not viewer.keyboard_focus, "Back clears detail focus")

viewer.scroll:scrollToRatio(0); flush()
box=viewer.scroll.htmlbox_widget
assert(box.page_count > 1, "expanded dhamma fixture paginates")
key(viewer,"Tab"); key(viewer,Device.input.group.PgFwd[1]); flush()
assert(box.page_number == 2 and not viewer.keyboard_focus, "native page key clears focus")
key(viewer,Device.input.group.PgBack[1]); flush()
assert(box.page_number == 1, "native previous page still works")
-- The shared footer sequence reaches enabled buttons and paints their native focus.
focusUri(viewer,"dpd:normal"); flush(); shot("keyboard-footer-focus")
assert(viewer.keyboard_focus.target.button.frame.invert, "visible native footer focus")
focusUri(viewer,"dpd:edit-search"); flush(); shot("keyboard-pencil-focus")
local old_pencil = viewer.edit_button
assert(viewer.keyboard_focus.target.button == old_pencil and old_pencil.image.invert,
    "visible native pencil focus")

local ffi = require("ffi")
ffi.cdef[[bool SDL_SetWindowSize(SDL_Window *, int, int);]]
local SDL = require("ffi/SDL3")
local width, height = Device.screen:getWidth(), Device.screen:getHeight()
assert(SDL.SDL.SDL_SetWindowSize(SDL.screen,height,width))
SDL.SDL.SDL_SyncWindow(SDL.screen)
Device.screen:resize(height,width)
local size = Device.screen:getSize()
Device.screen.screen_size.w, Device.screen.screen_size.h=size.w,size.h
UIManager:broadcastEvent(Event:new("SetDimensions",size)); flush()
assert(not viewer.keyboard_focus, "native rotation reflow clears focus")
key(viewer,"Tab"); flush(); shot("keyboard-landscape-focus")
assert(viewer.keyboard_focus.box == viewer.scroll.htmlbox_widget, "focus uses reflowed native document")
focusUri(viewer,"dpd:edit-search"); flush(); shot("keyboard-landscape-pencil-focus")
assert(viewer.edit_button ~= old_pencil and viewer.keyboard_focus.target.button == viewer.edit_button
    and viewer.edit_button.image.invert, "pencil focus uses the reflowed title")
local retained_tree, retained_scroll, visible_pencil = viewer[1], viewer.scroll, viewer.edit_button
local Scroll = require("ui/widget/scrollhtmlwidget")
local restore, show_error, reported = Scroll.scrollToRatio, viewer.showError
Scroll.scrollToRatio = function() error("injected scroll restoration failure") end
viewer.showError = function(_, err) reported = err end
viewer:update(true); flush()
Scroll.scrollToRatio, viewer.showError = restore, show_error
assert(reported and reported:find("injected scroll restoration failure", 1, true), "failed reflow control ran")
assert(not viewer.closed and viewer[1] == retained_tree and viewer.scroll == retained_scroll,
    "failed reflow retains the visible tree")
viewer:clearKeyboardFocus()
focusUri(viewer,"dpd:edit-search"); flush(); shot("keyboard-failed-reflow-pencil-focus")
assert(viewer.edit_button == visible_pencil and viewer.keyboard_focus.target.button == visible_pencil
    and visible_pencil.image.invert, "failed reflow keeps focus on the visible pencil")
viewer:close(); flush()

-- Exercise the actual plugin's editor and ownership callbacks, not a counter.
local DPD = dofile(root .. "/main.lua")
local editor = setmetatable({db=db,lookup=lookup,settings={font_size=20,dictionaries_off={}},ui={}}, {__index=DPD})
local function shown(widget)
    for _, window in ipairs(UIManager._window_stack) do if window.widget == widget then return true end end
    return false
end
local function editPopup(popup, draft, mode, name)
    if not popup.keyboard_focus or popup.keyboard_focus.target.uri ~= "dpd:edit-search" then
        focusUri(popup,"dpd:edit-search")
    end
    key(popup,"Return"); flush()
    local input = assert(editor.input_dialog,"keyboard opens the real editor")
    assert(shown(input) and shown(popup) and not popup.closed, "editor leaves its popup open")
    assert(input:getInputText() == draft and input.mode == mode, "editor preserves its draft and mode")
    shot(name)
    return input
end
local function cancelEditor(popup, input)
    key(input,Device.input.group.Back[1]); flush()
    assert(not shown(input) and not editor.input_dialog and shown(popup)
        and editor.viewer == popup and not popup.closed, "keyboard Cancel returns to the edited popup")
end
local function submitEditor(input, text)
    input:setInputText(text)
    for _, row in ipairs(input.buttons) do
        for _, button in ipairs(row) do
            if button.text == "Look up" then button.callback(); flush(); return end
        end
    end
    error("editor Look up button missing")
end
for _, trial in ipairs({{"dhamma","pali"},{"good","english"},{"dharma","dictionaries"}}) do
    local draft = "  " .. trial[1] .. "  "
    editor:lookupInput(trial[1],trial[2],draft); flush()
    local popup = assert(editor.viewer)
    assert(popup.model.found and popup.edit_button, "successful edit-enabled fixture")
    cancelEditor(popup,editPopup(popup,draft,trial[2],"keyboard-editor-" .. trial[2]))
    editor:closeViewers(); flush()
end
editor:lookupInput("dhamma","pali","  dhamma  "); flush()
local root_popup = assert(editor.viewer)
local input = editPopup(root_popup,"  dhamma  ","pali","keyboard-editor-root")
submitEditor(input,"buddha")
assert(root_popup.closed and #editor.viewers == 1, "submitted root edit replaces its owner")
root_popup = assert(editor.viewer)
root_popup:openView(root_popup:ratio(),lookup.get,"dhamma"); flush()
assert(#root_popup.navigation.stack == 2, "linked entry fixture")
cancelEditor(root_popup,editPopup(root_popup,"dhamma","pali","keyboard-editor-linked"))
input = editPopup(root_popup,"dhamma","pali","keyboard-editor-linked-submit")
submitEditor(input,"kamma")
local child = assert(editor.viewer)
assert(child ~= root_popup and child.parent_viewer == root_popup and #editor.viewers == 2
    and not root_popup.closed and #root_popup.navigation.stack == 2, "linked edit opens a child")
cancelEditor(child,editPopup(child,"kamma","pali","keyboard-editor-child"))
input = editPopup(child,"kamma","pali","keyboard-editor-child-submit")
submitEditor(input,"dhamma")
assert(child.closed and #editor.viewers == 2 and editor.viewer.parent_viewer == root_popup,
    "submitted child edit replaces only that child")
key(editor.viewer,"Back"); flush()
assert(editor.viewer == root_popup and not root_popup.closed, "Back returns to the linked parent")
editor:closeViewers(); flush()
editor:lookupInput("zzzzzzzzzzz","pali","  zzzzzzzzzzz  "); flush()
local miss = assert(editor.viewer)
assert(not miss.model.found, "no-result fixture")
focusUri(miss,"dpd:edit-search")
assert(miss.keyboard_focus.target.rects, "existing no-result HTML edit remains reachable")
cancelEditor(miss,editPopup(miss,"  zzzzzzzzzzz  ","pali","keyboard-editor-miss"))
editor:closeViewers(); flush()
print("PASS: visible title-pencil focus survives reflow; keyboard opens real Pali/English/dictionary editors; root, linked and child edits preserve Cancel and replacement ownership; no-result editing remains reachable")

viewer = Viewer:new{model=lookup:otherDictionaries({query="kamma"},{"cpd"}),lookup=lookup,
    font_size=26,dictionaries={"cpd"},normal_callback=function() end}
UIManager:show(viewer); flush()
local frame=viewer.navigation:current()
local selected
for i, entry in ipairs(frame.model.dictionaries.groups[1].entries) do
    if lookup:dictionaryPage(entry.id,0).has_more then selected=i; break end
end
local suffix="1/" .. assert(selected,"multi-part dictionary fixture")
focusUri(viewer,"dpd:dict-entry/" .. suffix)
key(viewer,"Return"); flush()
assert(viewer.action_buttons["dpd:dict-prev/" .. suffix].enabled == false)
for _, target in ipairs(viewer:keyboardTargets()) do
    assert(target.uri ~= "dpd:dict-prev/" .. suffix,"disabled footer control skipped")
end
focusUri(viewer,"dpd:dict-next/" .. suffix); key(viewer,"Return"); flush()
assert(frame.dictionary_pages[suffix].part == 2,"keyboard article pager activates once")
viewer:close(); flush(); db:close()
print("PASS: native Tab/Shift-Tab, arrows, Press/Return, visible HTML/footer focus, touch dispatch, page keys, pending rebuild, Back, rotation and disabled footer controls")
