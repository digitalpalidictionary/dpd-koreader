-- Native responsive controls, full-cell taps and article pager boundaries.
-- ./luajit <plugin>/tools/check_controls.lua <plugin> <db> [screenshots]
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
local DB = require("dpd/db")
local Lookup = require("dpd/lookup")
local Viewer = require("ui/dpd_viewer")
Viewer.link_guard_s = 0
local db = DB.new(path)
local lookup = Lookup.new(db)
local font = tonumber(os.getenv("DPD_TEST_FONT_SIZE")) or 16
local function flush() UIManager:_checkTasks(); UIManager:_repaint() end
local function show(model)
    local viewer = Viewer:new{model=model,lookup=lookup,font_size=font}
    UIManager:show(viewer); flush(); return viewer
end
local function shot(name)
    if arg[3] then Device.screen.bb:writePNG(arg[3] .. "/" .. name .. ".png") end
end
local function checkCells(viewer, prefix)
    local box, checked = viewer.scroll.htmlbox_widget, {}
    for number = 1, box.page_count do
        local page = box.document:openPage(number)
        local links = page:getPageLinks()
        page:close()
        for _, link in ipairs(links) do
            local cell = viewer.control_layout.buttons[link.uri]
            if cell and link.uri:find(prefix, 1, true) then
                assert(link.x0 >= -1 and link.x1 <= box.dimen.w + 1, "clipped button label")
                local bounds = viewer:buttonBounds(link, links)
                local w, h = bounds.x1-bounds.x0, bounds.y1-bounds.y0
                local x, y = (bounds.x0+bounds.x1)/2, (bounds.y0+bounds.y1)/2
                local definition = link.uri:find("/detail-", 1, true) or link.uri:find("dpd:detail-", 1, true)
                local minimum = Device.screen:getDPI() * (definition and 5.5 or 7) / 25.4
                assert(h >= minimum, "button target too short")
                if definition and font <= 16 then
                    assert(h < Device.screen:getDPI() * 7 / 25.4, "definition button still has pager padding")
                end
                assert(link.x1 - link.x0 < w, "wrapped or overflowing button label")
                assert(x - w / 2 >= -1 and x + w / 2 <= box.dimen.w + 1, "cell outside popup")
                viewer.scroll:scrollToRatio((number - .9) / box.page_count); flush()
                -- Tap actual native text and all four cell corners. Dispatch
                -- through the widget without navigating away during this probe.
                local followed
                local original = viewer.onLink
                viewer.onLink = function(_, uri) followed = uri end
                for _, delta in ipairs({{0,0},{-w/2+3,-h/2+3},{w/2-3,-h/2+3},
                    {-w/2+3,h/2-3},{w/2-3,h/2-3}}) do
                    local pos = Geom:new{x=box.dimen.x+x+delta[1],y=box.dimen.y+y+delta[2]}
                    assert(viewer:linkAt(box, pos) and viewer:linkAt(box, pos).uri == link.uri, "cell hit: " .. link.uri)
                    followed = nil
                    assert(box:onTapText(nil, {pos=pos}))
                    assert(followed == link.uri, "cell dispatch: " .. link.uri)
                end
                viewer.onLink = original
                checked[link.uri] = true
                print(string.format("CELL %s page=%d x=%.1f..%.1f y=%.1f..%.1f size=%.1fx%.1f",
                    link.uri, number, x-w/2, x+w/2, y-h/2, y+h/2, w, h))
                local nearest, next_left
                for _, other in ipairs(links) do
                    local next_cell = viewer.control_layout.buttons[other.uri]
                    if next_cell and other.uri ~= link.uri and math.abs(other.y0-link.y0) < 1 then
                        local ox = (other.x0 + other.x1) / 2
                        if ox > x and (not nearest or ox < nearest) then
                            nearest, next_left = ox, ox-next_cell.width_em*viewer.font_px/2
                        end
                    end
                end
                if nearest then
                    local right = x+w/2
                    assert(next_left > right, "overlapping adjacent targets")
                    local pos = Geom:new{x=box.dimen.x+(right+next_left)/2,y=box.dimen.y+y}
                    assert(not viewer:linkAt(box, pos), "button gap dispatches a link")
                end
            end
        end
    end
    return checked
end
local viewer = show(lookup:get("brahmajālasutta"))
local frame = viewer.navigation:current()
local id = frame.model.senses[1].id
viewer:onLink("dpd:sense/" .. id); flush()
local box = viewer.scroll.htmlbox_widget
local page = box.document:openPage(1)
local links = page:getPageLinks(); page:close()
local top, bottom
for _, link in ipairs(links) do
    if link.uri == "dpd:sense/" .. id then
        top, bottom = math.min(top or link.y0,link.y0), math.max(bottom or link.y1,link.y1)
    end
end
assert(top, "sense row on the first page")
local margin = viewer.font_px*.15
local followed, original = nil, viewer.onLink
viewer.onLink = function(_, uri) followed = uri end
for _, y in ipairs({top-margin+3,bottom+margin-3}) do
    local pos = Geom:new{x=box.dimen.x+box.dimen.w-3,y=box.dimen.y+y}
    assert(box:onTapText(nil,{pos=pos}) and followed == "dpd:sense/" .. id, "compact sense-row target")
    followed = nil
end
viewer.onLink = original
viewer.scroll:scrollToRatio(0); flush(); shot("definition-buttons")
local cells = checkCells(viewer, "dpd:detail-")
assert(cells["dpd:detail-paradigm/" .. id] and cells["dpd:detail-frequency/" .. id]
    and cells["dpd:detail-sutta/" .. id], "all available definition controls")
viewer:close(); flush()

-- Nested related forms leave less width for the longest category label.
local nested = lookup:get("brahmajālasutta")
id = nested.senses[1].id
for _ = 1, 3 do
    nested = {query="related form",found=true,senses={},grammar={},deconstructions={},roots={},
        suggestions={{query=nested.query,model=nested}}}
end
viewer = show(nested)
frame = viewer.navigation:current()
for _ = 1, 3 do frame = frame.suggestions[1]; frame.open = true end
frame.expanded[id] = true
frame.details[id] = lookup:detail(id)
frame.details[id].sutta_kind = "paṇṇāsaka" -- controlled label fixture
viewer:update(); flush()
local prefix = "dpd:similar/1/similar/1/similar/1/detail-"
checkCells(viewer, prefix)
local number = assert(viewer:sectionPage(prefix .. "sutta/" .. id))
viewer.scroll:scrollToRatio((number-.9)/viewer.scroll.htmlbox_widget.page_count); flush()
shot("definition-long-label")
viewer:close(); flush()

viewer = show(lookup:otherDictionaries({query="kamma"},{"cpd"}))
frame = viewer.navigation:current()
local selected
for i, entry in ipairs(frame.model.dictionaries.groups[1].entries) do
    if lookup:dictionaryPage(entry.id,0).has_more then selected = i; break end
end
local key = "1/" .. assert(selected)
viewer:onLink("dpd:dict-entry/" .. key); flush()
assert(not viewer.scroll.html_body:find("dpd:dict-prev/",1,true))
checkCells(viewer, "dpd:dict-")
viewer:onLink("dpd:dict-next/" .. key); flush()
viewer.scroll:scrollToRatio(0); flush(); shot("article-buttons")
cells = checkCells(viewer, "dpd:dict-")
assert(cells["dpd:dict-prev/" .. key] and cells["dpd:dict-next/" .. key])
viewer:close(); flush()
db:close()
print("PASS: native responsive definition and article buttons, unclipped labels, compact 5.5mm definitions and 7mm pagers, full-cell taps and separated adjacent targets")
