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
local Event = require("ui/event")
local Geom = require("ui/geometry")
local time = require("ui/time")
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

local function tapFooter(viewer, uri)
    local d = assert(viewer.action_buttons[uri], uri).dimen
    assert(viewer:handleEvent(Event:new("Gesture", {ges="tap",
        pos=Geom:new{x=d.x+d.w/2,y=d.y+d.h/2},time=time.now()})), uri)
    flush()
end
local function tapArticle(viewer, uri)
    local box = viewer.scroll.htmlbox_widget
    for number = 1, box.page_count do
        local page = box.document:openPage(number)
        local links = page:getPageLinks(); page:close()
        for _, link in ipairs(links) do
            if link.uri == uri then
                viewer.scroll:scrollToRatio((number-.9)/box.page_count); flush()
                assert(box:onTapText(nil, {pos=Geom:new{
                    x=box.dimen.x+(link.x0+link.x1)/2,y=box.dimen.y+(link.y0+link.y1)/2}}))
                flush(); return
            end
        end
    end
    error("missing article control: " .. uri)
end
local function atHeading(viewer, uri)
    local box = viewer.scroll.htmlbox_widget
    assert(box.page_number == viewer:sectionPage(uri), "article action returns to its heading")
end
local function atReadingPage(viewer, key)
    local box, part = viewer.scroll.htmlbox_widget, viewer.navigation:current().dictionary_pages[key]
    local last_uri = part.has_more and ("dpd:dict-next/" .. key) or ("dpd:dict-prev/" .. key)
    local last = viewer:findAnchor(box,{uri=last_uri,direction=-1,pages=math.huge},box.page_count) or box.page_count
    local wanted = viewer:sectionPage("dpd:dict-entry/" .. key) + (part.reading_pages[part.offset] or 0)
    assert(box.page_number == math.min(wanted,last), "article resumes its saved reading page")
end
local function midPart(viewer)
    local box = viewer.scroll.htmlbox_widget
    assert(box.page_count > 2, "long article spans several screens")
    viewer.scroll:scrollToRatio((math.ceil(box.page_count/2)-.9)/box.page_count); flush()
end
local function checkFooter(viewer, expected)
    local buttons = viewer.window[1][3][2]
    assert(#buttons.buttons == 1 and #buttons.buttons[1] == #expected, "one footer row")
    local positions, right, top = {}, nil, nil
    for i, entry in ipairs(buttons.buttons[1]) do
        local button = assert(viewer.action_buttons[entry.uri])
        assert(button.text == expected[i][1] and button.enabled == expected[i][2], "footer state: " .. entry.uri)
        local d, label = button.dimen, button.label_widget
        local minimum = Device.screen:getDPI()*7/25.4
        assert(d.w >= minimum and d.h >= minimum, "footer target smaller than 7mm")
        assert(not label.isTruncated or not label:isTruncated(), "truncated footer label")
        assert(not label.line_with_ellipsis and not label.has_split_inside_word, "clipped or split footer label")
        local ld = label:getSize()
        assert(ld.w <= d.w-2*button.padding_h and ld.h <= d.h,
            string.format("footer label outside its button: %s %dx%d in %dx%d",entry.uri,ld.w,ld.h,d.w,d.h))
        assert(not right or d.x > right, "overlapping footer targets")
        assert(not top or d.y == top, "footer buttons must stay in one row")
        positions[entry.uri], right, top = {d.x,d.y,d.w,d.h}, d.x+d.w, d.y
        print(string.format("FOOTER %s font=%d target=%dx%d label=%dx%d",entry.uri,font,d.w,d.h,ld.w,ld.h))
    end
    return positions
end

for _, direct in ipairs({false,true}) do
    local value = direct and lookup:searchDictionaries("kamma",{"cpd"})
        or lookup:otherDictionaries({query="kamma"},{"cpd"})
    viewer = Viewer:new{model=value,lookup=lookup,font_size=font,dictionaries={"cpd"},normal_callback=function() end}
    UIManager:show(viewer); flush()
    frame = viewer.navigation:current()
    local function expected(article)
        if direct then article[#article+1] = {"DPD",true}
        elseif #article == 0 then article[1] = {"Other dictionaries",false} end
        article[#article+1] = {"KOReader dictionary",true}
        return article
    end
    checkFooter(viewer,expected({}))
    local selected, single
    for i, entry in ipairs(frame.model.dictionaries.groups[1].entries) do
        if lookup:dictionaryPage(entry.id,0).has_more then selected = i else single = i end
    end
    local key = "1/" .. assert(selected)
    local toggle, prev, next_part = "dpd:dict-entry/" .. key, "dpd:dict-prev/" .. key, "dpd:dict-next/" .. key
    tapArticle(viewer,toggle)
    assert(not viewer.scroll.html_body:find("dpd:dict-prev/",1,true))
    local positions = checkFooter(viewer,expected({{"◂ Part",false},{"Part ▸",true},{"Entries",true}}))
    tapFooter(viewer,prev)
    assert(frame.dictionary_pages[key].part == 1, "disabled Previous does nothing")
    checkCells(viewer,"dpd:dict-")
    tapArticle(viewer,next_part)
    local second_offset = frame.dictionary_pages[key].offset
    tapArticle(viewer,prev)
    midPart(viewer); tapFooter(viewer,next_part)
    assert(frame.dictionary_pages[key].part == 2 and frame.dictionary_pages[key].offset == second_offset,
        "footer Next matches article Next")
    atReadingPage(viewer,key)
    local middle = checkFooter(viewer,expected({{"◂ Part",true},{"Part ▸",true},{"Entries",true}}))
    for uri, pos in pairs(positions) do
        for i, n in ipairs(pos) do assert(middle[uri][i] == n, "part buttons keep their positions") end
    end
    midPart(viewer); shot(direct and "article-footer-direct-mid-part" or "article-footer-mid-part")
    cells = checkCells(viewer,"dpd:dict-")
    assert(cells[prev] and cells[next_part])
    midPart(viewer); tapFooter(viewer,prev)
    assert(frame.dictionary_pages[key].part == 1 and frame.dictionary_pages[key].offset == 0,
        "footer Previous matches article Previous")
    atReadingPage(viewer,key)
    tapFooter(viewer,next_part)
    midPart(viewer)
    local reading_page = viewer.scroll.htmlbox_widget.page_number
    tapFooter(viewer,toggle)
    assert(not frame.dictionary_pages[key].open and not frame.dictionary_pages[key].html)
    atHeading(viewer,toggle); checkFooter(viewer,expected({}))
    tapArticle(viewer,toggle)
    assert(frame.dictionary_pages[key].part == 2, "resume remembered part")
    assert(viewer.scroll.htmlbox_widget.page_number == reading_page, "reopening retains the middle reading page")
    shot(direct and "article-footer-direct-resumed" or "article-footer-resumed")
    midPart(viewer)
    -- The same chevron URI must also restore the heading after a deep scroll.
    viewer:onLink(toggle); flush()
    atHeading(viewer,toggle); checkFooter(viewer,expected({}))
    tapArticle(viewer,toggle)
    while frame.dictionary_pages[key].has_more do tapFooter(viewer,next_part) end
    local last = frame.dictionary_pages[key].part
    local ending = checkFooter(viewer,expected({{"◂ Part",true},{"Part ▸",false},{"Entries",true}}))
    for uri, pos in pairs(positions) do
        for i, n in ipairs(pos) do assert(ending[uri][i] == n, "last part keeps button positions") end
    end
    tapFooter(viewer,next_part)
    assert(frame.dictionary_pages[key].part == last, "disabled Next does nothing")
    tapFooter(viewer,toggle); atHeading(viewer,toggle)
    checkFooter(viewer,expected({}))
    local single_toggle = "dpd:dict-entry/1/" .. assert(single, "single-part CPD fixture")
    tapArticle(viewer,single_toggle)
    checkFooter(viewer,expected({{"Entries",true}}))
    tapFooter(viewer,single_toggle); atHeading(viewer,single_toggle)
    checkFooter(viewer,expected({}))
    viewer:close(); flush()
end

-- A construction link changes the displayed entry, while the owning popup
-- still hands its original word to KOReader's dictionary.
local transferred
local value = lookup:get("dhamma")
value.deconstructions = {{parts={"ma"},unique={}}}
viewer = Viewer:new{model=value,lookup=lookup,font_size=font,dictionaries={"cpd"},
    normal_callback=function(word) transferred=word end}
UIManager:show(viewer); flush()
assert(viewer.action_buttons["dpd:normal"].text == "KOReader dictionary")
viewer:onLink("dpd:component/1/1"); flush()
assert(viewer.navigation:current().model.query == "ma")
checkFooter(viewer,{{"Other dictionaries",true},{"KOReader: dhamma",true}})
shot("handoff-original-word")
tapFooter(viewer,"dpd:normal")
assert(transferred == "dhamma" and viewer.closed, "explicit handoff retains the owning word")
db:close()
print("PASS: native definition and article buttons, footer states and fixed positions on both search routes, unclipped labels, 5.5mm definitions and 7mm pagers/footer targets, real taps, reading-page resume, collapse anchors and explicit original-word handoff")
