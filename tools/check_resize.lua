-- Run from a desktop KOReader directory with its bundled luajit:
-- SDL_VIDEODRIVER=dummy ./luajit <plugin>/tools/check_resize.lua <plugin> <dpd-mobile.db> [screenshot-dir]
-- Exercises native SDL/framebuffer resizing, MuPDF reflow, and KOReader's real
-- event dispatch. This checks desktop resize behavior, not hardware rotation.
require("setupkoenv")
local root = assert(arg[1], "plugin directory required")
local path = assert(arg[2], "DPD database required")
package.path = root .. "/?.lua;" .. package.path
G_defaults = require("luadefaults"):open()
G_reader_settings = require("luasettings"):wrap({dict_font_size=26})
local Device = require("device")
require("document/canvascontext"):init(Device)
require("ui/bidi").setup()
local UIManager = require("ui/uimanager")
local Event = require("ui/event")
local Geom = require("ui/geometry")
local Viewer = require("ui/dpd_viewer")
local DB = require("dpd/db")
local Lookup = require("dpd/lookup")
local db = DB.new(path)
local lookup = Lookup.new(db)
local ffi = require("ffi")
ffi.cdef[[bool SDL_SetWindowSize(SDL_Window *, int, int);]]
local SDL = require("ffi/SDL3")
local original_width, original_height = Device.screen:getWidth(), Device.screen:getHeight()

local function flush() UIManager:_checkTasks(); UIManager:_repaint() end
local function resize(width, height)
    assert(SDL.SDL.SDL_SetWindowSize(SDL.screen, width, height))
    SDL.SDL.SDL_SyncWindow(SDL.screen)
    Device.screen:resize(width, height)
    local size = Device.screen:getSize()
    Device.screen.screen_size.w, Device.screen.screen_size.h = size.w, size.h
    UIManager:broadcastEvent(Event:new("SetDimensions", size))
    UIManager:broadcastEvent(Event:new("ScreenResize", size))
    UIManager:setDirty("all", "full")
end
local function checkGeometry(viewer, width, height)
    assert(Device.screen:getWidth() == width and Device.screen:getHeight() == height,
        "the native framebuffer must really change dimensions")
    assert(viewer.dimen.w == width and viewer.dimen.h == height)
    assert(viewer[1].dimen == viewer.dimen, "centering must use the new screen geometry")
    local window = viewer.window.dimen
    assert(window.w == math.floor(width * .92) and window.h == math.floor(height * .85))
    assert(window.x >= 0 and window.y >= 0 and window.x + window.w <= width and window.y + window.h <= height,
        "the complete popup must fit inside the resized framebuffer")
    assert(window.x == math.floor((width - window.w)/2) and window.y == math.floor((height - window.h)/2))
    if viewer.ges_events.TapOutside then
        local range = viewer.ges_events.TapOutside[1].range()
        assert(range == viewer.dimen and range.x == 0 and range.y == 0)
        assert(range:contains(Geom:new{x=width-1,y=height-1,w=0,h=0}), "outside-tap range must reach the new corner")
    end
end
local function checkScroll(viewer, ratio)
    local box = viewer.scroll.htmlbox_widget
    local expected_page = math.min(box.page_count, 1 + math.floor(box.page_count * ratio))
    assert(box.page_number == expected_page, "resize must restore scroll to the same document fraction")
    assert(viewer:ratio() > 0, "the regression must exercise restoration beyond the first page")
end

-- Enter a child frame containing real DPD data and enough reading notes to
-- exercise scrolling. Preserve its parent, expanded detail and variant controls.
local parent = lookup:get("pacchima")
local child = lookup:get("ca")
assert(parent.found and child.found and #child.variants > 0)
local font_size = tonumber(os.getenv("DPD_TEST_FONT_SIZE")) or 26
local viewer = Viewer:new{model=parent,lookup=lookup,font_size=font_size}
UIManager:show(viewer); flush()
viewer.navigation:push(child, viewer:ratio())
viewer:update(); flush()
viewer:onLink("dpd:variants-toggle"); flush()
local id = assert(child.senses[1]).id
viewer:onLink("dpd:sense/" .. id); flush()
local frame = viewer.navigation:current()
assert(frame.expanded[id] and frame.variants_open and #viewer.navigation.stack == 2)
assert(viewer.scroll.htmlbox_widget.page_count > 1, "the real database fixture must paginate")
viewer.scroll:scrollToRatio(.55); flush()
local build, builds = viewer.build, 0
viewer.build = function(self) builds=builds+1; return build(self) end
local ratio = viewer:ratio()
-- Also queue a content reflow before both dimension notifications. It must be
-- combined with resize rather than rebuilding the native HTML tree twice.
viewer:update()
resize(original_height, original_width); flush()
assert(builds == 1, "pending content update and both resize events must coalesce")
checkGeometry(viewer, original_height, original_width)
checkScroll(viewer, ratio)
assert(viewer.navigation:current() == frame and #viewer.navigation.stack == 2)
assert(frame.expanded[id] and frame.variants_open and frame.details[id])
if arg[3] then Device.screen.bb:writePNG(arg[3] .. "/resize-landscape.png") end

ratio = viewer:ratio()
resize(original_width, original_height); flush()
assert(builds == 2, "reverse resize must produce exactly one more reflow")
checkGeometry(viewer, original_width, original_height)
checkScroll(viewer, ratio)
assert(viewer.navigation:current() == frame and frame.expanded[id] and frame.variants_open)
if arg[3] then Device.screen.bb:writePNG(arg[3] .. "/resize-portrait.png") end

-- Back queued before resize must use the parent's saved scroll, not the still-
-- displayed child's position. A close must cancel all pending native rebuilds.
local saved_parent_ratio = viewer.navigation.stack[1].ratio
viewer:back()
resize(original_height, original_width); flush()
assert(viewer.navigation:current().model == parent and #viewer.navigation.stack == 1)
assert(viewer:ratio() == saved_parent_ratio)
local old_box = viewer.scroll.htmlbox_widget
viewer:update()
local pending = viewer._pending_update
viewer:close(); flush()
assert(old_box.document == nil and old_box.bb == nil, "closing must free the old native HTML tree")
local before_close = builds
pending()
resize(original_width, original_height); flush()
assert(builds == before_close, "closed and stale callbacks must not rebuild the viewer")
db:close()
print("PASS: native SDL popup resize in both directions, paired-event coalescing, bounds, gesture geometry, expanded/navigation state, scroll restoration and close cancellation at font " .. font_size)
