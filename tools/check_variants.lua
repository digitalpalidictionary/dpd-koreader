-- Walk all ca reading windows through native tap dispatch, without DB reads.
-- ./luajit <plugin>/tools/check_variants.lua <plugin> <db> [screenshots]
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
local Geom = require("ui/geometry")
local time = require("ui/time")
local DB = require("dpd/db")
local Lookup = require("dpd/lookup")
local Viewer = require("ui/dpd_viewer")
Viewer.link_guard_s = 0
local db = DB.new(path)
local lookup = Lookup.new(db)
local model = lookup:get("ca")
assert(#model.variants == 1679, "full ca readings retained")
local viewer = Viewer:new{model=model,lookup=lookup,font_size=tonumber(os.getenv("DPD_TEST_FONT_SIZE")) or 16}
local function flush() UIManager:_checkTasks(); UIManager:_repaint() end
UIManager:show(viewer); flush()
local frame = viewer.navigation:current()
local function tap(uri, bottom)
    local box = viewer.scroll.htmlbox_widget
    for i = 1, box.page_count do
        local number = bottom and (box.page_count + 1 - i) or i
        local page = box.document:openPage(number)
        local links = page:getPageLinks() or {}
        page:close()
        for _, link in ipairs(links) do
            if link.uri == uri then
                viewer.scroll:scrollToRatio((number - .9) / box.page_count); flush()
                local pos = Geom:new{x=box.dimen.x+(link.x0+link.x1)/2,y=box.dimen.y+(link.y0+link.y1)/2}
                assert(viewer:handleEvent(Event:new("Gesture",{ges="tap",pos=pos,time=time.now()})), uri)
                flush(); return
            end
        end
    end
    error("Missing native control: " .. uri)
end
local function shot(name)
    if arg[3] then Device.screen.bb:writePNG(arg[3] .. "/" .. name .. ".png") end
end
tap("dpd:variants-toggle")
local queries, rows, payload = db.query_count, db.row_count, db.payload_bytes
local max_pages, max_bytes = 0, 0
for window = 1, 34 do
    assert(frame.variants_page == window)
    local first, last = (window - 1) * 50 + 1, math.min(1679, window * 50)
    local html = viewer.scroll.html_body
    assert(html:find("Readings " .. first .. "–" .. last .. "&nbsp;of&nbsp;1679",1,true))
    local _, rendered = html:gsub('<p><b>[^<]* · [^<]*:</b> ', "")
    assert(rendered == last - first + 1, "window contains exactly its readings")
    assert((html:find("dpd:variants-prev",1,true) ~= nil) == (window > 1))
    assert((html:find("dpd:variants-next",1,true) ~= nil) == (window < 34))
    max_pages = math.max(max_pages, viewer.scroll.htmlbox_widget.page_count)
    max_bytes = math.max(max_bytes, #html)
    -- The bottom pager must return to the section's start after replacement.
    assert(viewer.scroll.htmlbox_widget.page_number == viewer:sectionPage("dpd:variants-toggle"))
    if window == 1 or window == 2 or window == 34 then shot("readings-window-" .. window) end
    if window < 34 then tap("dpd:variants-next", true) end
end
viewer:onLink("dpd:variants-next"); flush()
assert(frame.variants_page == 34, "last-window bound")
for window = 33, 1, -1 do
    tap("dpd:variants-prev", true)
    assert(frame.variants_page == window)
end
viewer:onLink("dpd:variants-prev"); flush()
assert(frame.variants_page == 1, "first-window bound")
assert(db.query_count == queries and db.row_count == rows and db.payload_bytes == payload,
    "reading pagination must not read or modify the database")

-- Open a real detail view from window 2 and return to its exact screen page.
tap("dpd:variants-next", true)
local id = model.senses[1].id
tap("dpd:sense/" .. id)
tap("dpd:detail-frequency/" .. id)
assert(viewer.navigation:current().model.frequency)
local saved_ratio = frame.ratio
viewer:back(); flush()
assert(viewer.navigation:current() == frame and frame.variants_page == 2 and frame.variants_open)
assert(viewer:ratio() == saved_ratio, "Back restores the original rendered page")
tap("dpd:variants-toggle")
tap("dpd:variants-toggle")
assert(frame.variants_page == 2, "collapse/reopen retains the window")
viewer:close(); flush(); db:close()
print(string.format("PASS: all 1679 readings visited in 34 bounded windows, forward/backward native bottom-pager taps, no paging DB reads, and Back/collapse state; max %d pages and %d HTML bytes", max_pages, max_bytes))
