local function harness(pages, enabled)
    local names = {"ffi/blitbuffer", "ui/widget/container/centercontainer", "device",
        "ui/widget/container/framecontainer", "ui/geometry", "ui/gesturerange", "ui/widget/infomessage",
        "ui/widget/container/inputcontainer", "ui/widget/scrollhtmlwidget", "ui/widget/titlebar",
        "ui/uimanager", "ui/widget/verticalgroup", "logger", "ui/time", "ui/widget/buttontable",
        "ui/widget/horizontalgroup", "ui/widget/horizontalspan", "ui/widget/iconbutton",
        "ui/widget/linewidget", "ui/size", "ui/font", "ui/widget/textwidget", "ui/dpd_viewer"}
    local saved, state = {}, {dirty=0, opened=0, closed=0, followed={}}
    for _, name in ipairs(names) do saved[name] = package.loaded[name]; package.loaded[name] = {} end
    package.loaded["ui/dpd_viewer"] = nil
    package.loaded.device = {hasKeys=function() return enabled ~= false end,
        screen={scaleBySize=function(_, value) return value end}}
    package.loaded["ffi/blitbuffer"] = {COLOR_BLACK=0}
    package.loaded["ui/widget/container/inputcontainer"] = {extend=function(_, value) return value end}
    package.loaded["ui/uimanager"] = {setDirty=function() state.dirty=state.dirty+1 end}
    local Viewer = require("ui/dpd_viewer")
    for _, name in ipairs(names) do package.loaded[name] = saved[name] end
    local box = {page_count=#pages, page_number=1, dimen={w=200,h=300},
        paintTo=function() state.painted=true end,
        document={openPage=function(_, number)
            state.opened=state.opened+1
            return {getPageLinks=function() return pages[number] end,
                close=function() state.closed=state.closed+1 end}
        end}}
    local scroll = {htmlbox_widget=box}
    function scroll:scrollText(direction)
        box.page_number=box.page_number+direction; self.scroll_callback()
    end
    function scroll:scrollToRatio(ratio)
        box.page_number=ratio==0 and 1 or box.page_count; self.scroll_callback()
    end
    local viewer = setmetatable({scroll=scroll,
        onLink=function(_, uri) state.followed[#state.followed+1]=uri end,
        guard=function(_, _, fn, ...) return fn(...) end}, {__index=Viewer})
    viewer:setupKeyboardLinks(scroll)
    return viewer, state, box
end

local function link(uri, x, y)
    return {uri=uri,x0=x or 10,x1=(x or 10)+50,y0=y or 10,y1=(y or 10)+20}
end

local function button(enabled)
    return {enabled=enabled,onFocus=function(self) self.focused=true end,
        onUnfocus=function(self) self.focused=false end}
end

describe("keyboard access to rendered popup links", function()
    it("uses reading order, groups wrapped lines and skips disabled footer buttons", function()
        local viewer, state = harness({{link("b",10,70),link("a",10,30),link("a",10,10)}})
        local disabled, active = button(false), button(true)
        viewer.keyboard_buttons={{uri="disabled",button=disabled},{uri="footer",button=active}}
        viewer:onFocusLink(1)
        assert.equal("a",viewer.keyboard_focus.target.uri)
        assert.equal(2,#viewer.keyboard_focus.target.rects)
        viewer:onFocusLink(1)
        assert.equal("b",viewer.keyboard_focus.target.uri)
        viewer:onFocusLink(1)
        assert.equal("footer",viewer.keyboard_focus.target.uri)
        assert.is_true(active.focused)
        viewer:onActivateLink()
        assert.same({"footer"},state.followed)
        viewer:onFocusLink(-1)
        assert.is_false(active.focused)
        assert.equal("b",viewer.keyboard_focus.target.uri)
        assert.equal(state.opened,state.closed)
    end)

    it("wraps both directions in a one-page popup without dropping focus", function()
        local viewer = harness({{link("a"),link("b",10,60)}})
        viewer:onFocusLink(-1)
        assert.equal("b",viewer.keyboard_focus.target.uri)
        viewer:onFocusLink(1)
        assert.equal("a",viewer.keyboard_focus.target.uri)
        viewer:onFocusLink(-1)
        assert.equal("b",viewer.keyboard_focus.target.uri)
    end)

    it("crosses linkless pages and clears focus when native paging changes the page", function()
        local viewer, _, box = harness({{link("a")},{},{link("b")}})
        viewer:onFocusLink(1); viewer:onFocusLink(1)
        assert.equal(3,box.page_number)
        assert.equal("b",viewer.keyboard_focus.target.uri)
        viewer:onFocusLink(1)
        assert.equal(1,box.page_number)
        assert.equal("a",viewer.keyboard_focus.target.uri)
        viewer.scroll:scrollText(1)
        assert.is_nil(viewer.keyboard_focus)
        viewer:onFocusLink(-1)
        assert.equal(1,box.page_number)
        assert.equal("a",viewer.keyboard_focus.target.uri)
    end)

    it("leaves a document without links on its original page", function()
        local viewer, state, box = harness({{},{},{}})
        viewer:onFocusLink(1)
        assert.is_nil(viewer.keyboard_focus)
        assert.equal(1,box.page_number)
        assert.equal(state.opened,state.closed)
    end)

    it("paints a visible border and never paints or activates an old page's rectangle", function()
        local viewer, state, box = harness({{link("a")},{link("b")}})
        local borders = {}
        local bb = {paintBorder=function(_, ...) borders[#borders+1]={...} end}
        viewer:onFocusLink(1)
        box:paintTo(bb,100,200)
        assert.is_true(state.painted)
        assert.same({108,208,54,24,2,0},borders[1])
        box.page_number=2
        box:paintTo(bb,100,200)
        assert.equal(1,#borders)
        viewer:onActivateLink()
        assert.same({},state.followed)
        assert.equal("b",viewer.keyboard_focus.target.uri)
    end)

    it("consumes keys during rebuild and clears focus on a replacement tree", function()
        local viewer, state, box = harness({{link("a")}})
        viewer:onActivateLink()
        assert.same({},state.followed)
        viewer:onActivateLink()
        assert.same({"a"},state.followed)
        viewer._pending_update=true
        viewer:onActivateLink(); viewer:onFocusLink(1)
        assert.same({"a"},state.followed)
        viewer:setupKeyboardLinks(viewer.scroll)
        assert.is_nil(viewer.keyboard_focus)
        local borders = 0
        box:paintTo({paintBorder=function() borders=borders+1 end},0,0)
        assert.equal(0,borders)
    end)

    it("shares footer focus ownership without requiring a D-pad layout", function()
        local viewer = harness({{link("a")}})
        local active = button(true)
        local buttons = {buttons={{{id="action",uri="footer"}}},getButtonById=function() return active end}
        viewer:setupKeyboardLinks(viewer.scroll,{nil,buttons})
        assert.is_false(buttons.key_events_enabled)
        viewer:onFocusLink(-1)
        assert.equal("footer",viewer.keyboard_focus.target.uri)
        assert.is_true(active.focused)
        viewer.scroll.scroll_callback()
        assert.is_false(active.focused)
        assert.is_nil(viewer.keyboard_focus)
    end)

    it("leaves a touch-only widget's painting and footer controls alone", function()
        local viewer, _, box = harness({{link("a")}},false)
        local paint = box.paintTo
        viewer:setupKeyboardLinks(viewer.scroll,{nil,{}})
        assert.equal(paint,box.paintTo)
        assert.is_nil(viewer.keyboard_buttons)
    end)
end)
