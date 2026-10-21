-- Run from a desktop KOReader directory with its bundled luajit:
-- SDL_VIDEODRIVER=dummy DPD_TEST_FONT_SIZE=26 ./luajit <plugin>/tools/check_expansion.lua <plugin> <dpd-mobile.db> [screenshot-dir]
-- Taps in-place toggles on later pages of real entries and checks that the
-- tapped control is still on the visible page after MuPDF repaginates.
require("setupkoenv")
local root = assert(arg[1], "plugin directory required")
local path = assert(arg[2], "DPD database required")
package.path = root .. "/?.lua;" .. package.path
G_defaults = require("luadefaults"):open()
G_reader_settings = require("luasettings"):wrap({})
local Device = require("device")
require("document/canvascontext"):init(Device)
require("ui/bidi").setup()
local UIManager = require("ui/uimanager")
local Viewer = require("ui/dpd_viewer")
local DB = require("dpd/db")
local Lookup = require("dpd/lookup")
local db = DB.new(path)
local lookup = Lookup.new(db)
local font_size = tonumber(os.getenv("DPD_TEST_FONT_SIZE")) or 26

local function flush() UIManager:_checkTasks(); UIManager:_repaint() end
local function screenshot(name)
    if arg[3] then Device.screen.bb:writePNG(arg[3] .. "/" .. name .. "-" .. font_size .. ".png") end
end
local function onPage(viewer, page, uri)
    local opened = viewer.scroll.htmlbox_widget.document:openPage(page)
    local links = opened:getPageLinks()
    opened:close()
    for _, link in ipairs(links) do if link.uri == uri then return true end end
    return false
end
local function pageOf(viewer, uri)
    for page = 1, viewer.scroll.htmlbox_widget.page_count do
        if onPage(viewer, page, uri) then return page end
    end
end
local function show(word)
    local viewer = Viewer:new{model = lookup:get(word), lookup = lookup, font_size = font_size}
    UIManager:show(viewer); flush()
    return viewer
end
-- Scroll to the control's page, tap it, and require it to remain visible.
local function tap(viewer, uri, label)
    local page = assert(pageOf(viewer, uri), label .. ": control not rendered")
    local box = viewer.scroll.htmlbox_widget
    viewer.scroll:scrollToRatio((page - 1 + .1) / box.page_count); flush()
    local before = box.page_count
    viewer:onLink(uri); flush()
    box = viewer.scroll.htmlbox_widget
    assert(onPage(viewer, box.page_number, uri), string.format(
        "%s: tapped on page %d/%d, now showing %d/%d without the control",
        label, page, before, box.page_number, box.page_count))
    return page, before, box.page_number, box.page_count
end
local results, failures = {}, {}
-- Run every case, so one regression does not hide the others.
local function case(label, run)
    local ok, err = pcall(run)
    if not ok then failures[#failures + 1] = tostring(err) end
end
local function record(label, ...) results[#results + 1] = string.format("%s %d/%d -> %d/%d", label, ...) end

-- A compound case: expanding a component sense below the first page.
local compound = show("vajjakammappabhedanti")
local frame = compound.navigation:current()
-- Only analysis 1 starts open; open the rest to reach a later page.
for index, analysis in ipairs(frame.model.deconstructions) do
    if analysis.has_new and not frame.analyses[index] then
        compound:onLink("dpd:analysis/" .. index); flush()
    end
end
local target
for index, analysis in ipairs(compound.navigation:current().model.deconstructions) do
    if frame.analyses[index] then
        for part_index, part in ipairs(analysis.parts or {}) do
            local component = analysis.unique[part_index] and frame.model.components[part]
            for j, sense in ipairs(component and component.senses or {}) do
                if j > 2 then break end
                local uri = "dpd:component-sense/" .. index .. "/" .. part_index .. "/" .. sense.id
                if (pageOf(compound, uri) or 0) > 1 then target = uri end
            end
        end
    end
end
-- A known regression (the akamma sense of analysis 5) when it is on a later page.
if (pageOf(compound, "dpd:component-sense/5/2/102") or 0) > 1 then target = "dpd:component-sense/5/2/102" end
target = assert(target, "compound needs a component sense below the first page")
case("compound", function()
    record("compound expand " .. target, tap(compound, target, "compound expand")); screenshot("compound-expanded")
    record("compound collapse", tap(compound, target, "compound collapse"))
end)
compound:close(); flush()

-- Opening a later sense closes an expanded sense above it, moving the control up.
local pacchima = show("pacchima")
local senses = pacchima.navigation:current().model.senses
tap(pacchima, "dpd:sense/" .. senses[1].id, "first sense")
local later
for i = 2, #senses do
    local uri = "dpd:sense/" .. senses[i].id
    if pageOf(pacchima, uri) > 1 then later = uri; break end
end
later = assert(later, "pacchima needs a sense below the first page")
case("sense switch", function()
    record("sense switch", tap(pacchima, later, "sense switch")); screenshot("pacchima-switched")
    assert(not pacchima.navigation:current().expanded[senses[1].id], "single-sense expansion must remain")
end)
pacchima:close(); flush()

-- Grammar parses are inserted above the toggle and removed again.
local inflected = show("dutiyā")
case("grammar", function()
    record("grammar expand", tap(inflected, "dpd:grammar-toggle", "grammar expand"))
    record("grammar collapse", tap(inflected, "dpd:grammar-toggle", "grammar collapse"))
end)
inflected:close(); flush()
db:close()

assert(#failures == 0, "\n" .. table.concat(failures, "\n"))
print("PASS: expansion keeps the tapped control visible at font " .. font_size .. ": " .. table.concat(results, "; "))
