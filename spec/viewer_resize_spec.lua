local function model(query)
    return {query=query, found=true, senses={}, grammar={}, deconstructions={},
        suggestions={}, references={}, variants={}}
end

-- Keep device/UI stubs local to this viewer class, leaving the pure logic suite's
-- package bindings unchanged. Use the real build and navigation implementations.
local function harness(options)
    options = options or {}
    -- links[page] lists the link URIs a rendered page exposes to the anchor search.
    local state = {queue={}, scrolls={}, builds=0, errors=0, dirty=0, width=600, height=900, links={}, opened=0}
    local names = {"ffi/blitbuffer", "ui/widget/container/centercontainer", "device",
        "ui/widget/container/framecontainer", "ui/geometry", "ui/gesturerange", "ui/widget/infomessage",
        "ui/widget/container/inputcontainer", "ui/widget/scrollhtmlwidget", "ui/widget/titlebar",
        "ui/uimanager", "ui/widget/verticalgroup", "logger", "ui/time", "ui/dpd_viewer",
        "ui/widget/buttontable", "ui/widget/horizontalgroup", "ui/widget/horizontalspan",
        "ui/widget/iconbutton", "ui/widget/linewidget", "ui/size", "ui/font", "ui/widget/textwidget"}
    local saved = {}
    for _, name in ipairs(names) do saved[name] = package.loaded[name]; package.loaded[name] = nil end
    local widget = {}
    function widget:new(value)
        value = value or {}
        return setmetatable(value, {__index=self})
    end
    function widget:free()
        self.freed = true
        for _, child in ipairs(self) do if child.free then child:free() end end
    end
    function widget:getSize() return {w=self.width or 100,h=self.height or 40} end
    local screen = {
        getWidth=function() return state.width end, getHeight=function() return state.height end,
        getSize=function() return {w=state.width,h=state.height} end,
        scaleBySize=function(_, value) return value end,
        getDPI=function() return 160 end,
    }
    local manager = {
        nextTick=function(_, action) state.queue[#state.queue+1] = action end,
        unschedule=function(_, action)
            for i = #state.queue, 1, -1 do
                if state.queue[i] == action then table.remove(state.queue, i) end
            end
        end,
        setDirty=function() state.dirty = state.dirty + 1 end,
        show=function() state.errors = state.errors + 1 end,
        close=function(_, viewer) viewer:onCloseWidget(); viewer[1]:free() end,
    }
    local scroll = {scroll_bar_width=6, text_scroll_span=12}
    function scroll:new(value)
        state.builds = state.builds + 1
        value.htmlbox_widget = {page_count=state.page_count or (state.width < state.height and 10 or 20), page_number=1,
            document={openPage=function(_, page)
                state.opened = state.opened + 1
                local links = {}
                for _, uri in ipairs(state.links[page] or {}) do links[#links+1] = {uri=uri} end
                return {getPageLinks=function() return links end, close=function() end}
            end}}
        state.scrolls[#state.scrolls+1] = value
        return setmetatable(value, {__index=self})
    end
    function scroll:scrollToRatio(ratio)
        if state.fail_restore then error("restore failed") end
        local box = self.htmlbox_widget
        box.page_number = math.min(box.page_count, 1 + math.floor(ratio * box.page_count))
    end
    function scroll:getCurrentRatio()
        local box = self.htmlbox_widget
        return (box.page_number - 1) / box.page_count
    end
    scroll.free = widget.free
    package.loaded["ffi/blitbuffer"] = {COLOR_WHITE=0}
    package.loaded.device = {screen=screen,isTouchDevice=function() return true end,hasKeys=function() return false end}
    package.loaded["ui/widget/container/inputcontainer"] = {extend=function(_, value) return value end}
    for _, name in ipairs({"ui/widget/container/centercontainer", "ui/widget/container/framecontainer",
        "ui/geometry", "ui/gesturerange", "ui/widget/infomessage", "ui/widget/titlebar", "ui/widget/verticalgroup",
        "ui/widget/horizontalgroup", "ui/widget/horizontalspan", "ui/widget/iconbutton", "ui/widget/linewidget"}) do
        package.loaded[name] = widget
    end
    local buttons = setmetatable({}, {__index=widget})
    function buttons:getButtonById(id)
        for _, row in ipairs(self.buttons) do
            for _, button in ipairs(row) do if button.id == id then return button end end
        end
    end
    package.loaded["ui/widget/buttontable"] = buttons
    package.loaded["ui/size"] = {line={medium=1}}
    package.loaded["ui/font"] = {getFace=function() return {} end}
    package.loaded["ui/widget/textwidget"] = widget
    package.loaded["ui/widget/scrollhtmlwidget"] = scroll
    package.loaded["ui/uimanager"] = manager
    package.loaded.logger = {dbg=function() end,warn=function() end}
    package.loaded["ui/time"] = {now=function() return 0 end,to_ms=function() return 0 end,
        since=function() return 0 end,s=function(seconds) return seconds end}
    local Viewer = require("ui/dpd_viewer")
    for _, name in ipairs(names) do package.loaded[name] = saved[name] end
    local viewer = setmetatable({model=options.model or model("root"), font_size=16,
        lookup=options.lookup, parent_viewer=options.parent_viewer, edit_callback=options.edit_callback,
        normal_callback=options.normal_callback, normal_word=options.normal_word,
        release_selection_callback=options.release_selection_callback}, {__index=Viewer})
    local saved_settings = _G.G_reader_settings
    _G.G_reader_settings = {readSetting=function(_, key) return (options.settings or {})[key] end}
    screen.low_pan_rate = options.low_pan_rate
    viewer:init()
    _G.G_reader_settings = saved_settings
    function state:resize(width, height)
        self.width, self.height = width, height
        local size = {w=width,h=height}
        viewer:onSetDimensions(size)
        viewer:onScreenResize(size)
    end
    function state:flush()
        local queue = self.queue
        self.queue = {}
        for _, action in ipairs(queue) do action() end
    end
    return viewer, state
end

describe("popup failure containment", function()
    local Diag = require("dpd/diag")
    local saved_enabled, saved_logger, warnings
    before_each(function()
        saved_enabled, saved_logger = Diag.enabled, package.loaded.logger
        warnings = {}
        package.loaded.logger = {warn=function(_, trace) warnings[#warnings + 1] = trace end}
    end)
    after_each(function()
        Diag.enabled, package.loaded.logger = saved_enabled, saved_logger
    end)

    for _, diagnostics in ipairs({false, true}) do
        it("dismisses only the failed child and logs its traceback, diagnostics=" .. tostring(diagnostics), function()
            Diag.enabled = diagnostics
            local parent = harness()
            local value = model("child")
            value.senses = {{id=7,lemma_1="child"}}
            local viewer, state = harness({model=value,parent_viewer=parent,lookup={detail=function() return {} end}})
            local closed = 0
            viewer.close_callback = function() closed = closed + 1 end
            viewer.navigation.toggleSense = function() error("navigation failed") end
            viewer:onLink("dpd:sense/7")
            viewer:onLink("dpd:sense/7")
            assert.is_true(viewer.closed)
            assert.is_falsy(parent.closed)
            assert.is_true(viewer[1].freed)
            assert.equal(1, closed)
            assert.equal(1, state.errors)
            assert.matches("navigation failed", warnings[1], 1, true)
            assert.matches("stack traceback:", warnings[1], 1, true)
        end)

        it("contains a queued handoff failure and releases selection once, diagnostics=" .. tostring(diagnostics), function()
            Diag.enabled = diagnostics
            local releases, handoffs, closes = 0, 0, 0
            local viewer, state = harness({normal_callback=function()
                handoffs = handoffs + 1
                error("handoff failed")
            end, release_selection_callback=function() releases = releases + 1 end})
            viewer.close_callback = function(transfer)
                assert.is_true(transfer)
                closes = closes + 1
            end
            viewer:onLink("dpd:normal"); viewer:onLink("dpd:normal")
            assert.is_falsy(viewer.closed)
            assert.equal(0, releases)
            state:flush()
            assert.is_true(viewer.closed)
            assert.equal(1, releases)
            assert.equal(1, handoffs)
            assert.equal(1, closes)
            assert.equal(1, state.errors)
        end)

        it("completes cleanup after two failing callbacks, diagnostics=" .. tostring(diagnostics), function()
            Diag.enabled = diagnostics
            local viewer, state = harness()
            local children, owner = 0, 0
            viewer.before_close_callback = function() children = children + 1; error("children failed") end
            viewer.close_callback = function() owner = owner + 1; error("owner failed") end
            viewer:update()
            local stale = state.queue[1]
            viewer:close(); viewer:close()
            assert.is_nil(viewer:onCloseWidget())
            stale()
            assert.is_true(viewer.closed)
            assert.is_true(viewer[1].freed)
            assert.equal(0, #state.queue)
            assert.equal(1, children)
            assert.equal(1, owner)
            assert.equal(1, state.errors)
            assert.equal(2, #warnings)
        end)
    end

    it("keeps successful handoff selection ownership with the dictionary", function()
        local releases, handoffs = 0, 0
        local viewer, state = harness({normal_callback=function() handoffs = handoffs + 1 end,
            release_selection_callback=function() releases = releases + 1 end})
        viewer:onLink("dpd:normal"); state:flush()
        assert.is_true(viewer.closed)
        assert.equal(1, handoffs)
        assert.equal(0, releases)
        assert.equal(0, state.errors)
    end)

    it("hands the popup's selection to the dictionary from a view opened inside it", function()
        local words = {}
        local value = model("dhamma")
        value.original, value.original_clean = "“dhammassa,”", "dhammassa"
        local viewer, state = harness({model=value, normal_callback=function(word) words[#words + 1] = word end})
        local family = model("dhamma")
        family.original = "Word family: dhamma"
        viewer.navigation:push(family)
        viewer:update(); state:flush()
        assert.equal("KOReader: dhammassa", viewer.action_buttons["dpd:normal"].text)
        viewer:onLink("dpd:normal"); state:flush()
        assert.same({"dhammassa"}, words)
    end)

    it("labels the retained dictionary word after a construction link and restores the root label on Back", function()
        local words = {}
        local value = model("dhamma")
        value.deconstructions = {{parts={"ma"}, unique={}}}
        local viewer, state = harness({model=value, lookup={get=function() return model("ma") end},
            normal_callback=function(word) words[#words+1] = word end})
        assert.equal("KOReader dictionary", viewer.action_buttons["dpd:normal"].text)
        viewer:onLink("dpd:component/1/1"); state:flush()
        assert.equal("ma", viewer.navigation:current().model.query)
        assert.equal("KOReader: dhamma", viewer.action_buttons["dpd:normal"].text)
        viewer:back(); state:flush()
        assert.equal("KOReader dictionary", viewer.action_buttons["dpd:normal"].text)
        viewer:onLink("dpd:component/1/1"); state:flush()
        viewer:onLink("dpd:normal"); state:flush()
        assert.same({"dhamma"}, words)
    end)

    it("labels an ID lookup with its effective handoff word at root and deeper views", function()
        local words, value = {}, model("dhamma 1.01")
        value.original, value.original_clean = "34626", "34626"
        local viewer, state = harness({model=value,normal_word="dhamma",
            normal_callback=function(word) words[#words+1]=word end})
        assert.equal("KOReader: dhamma",viewer.action_buttons["dpd:normal"].text)
        viewer.navigation:push(model("ma")); viewer:update(); state:flush()
        assert.equal("KOReader: dhamma",viewer.action_buttons["dpd:normal"].text)
        viewer:onLink("dpd:normal"); state:flush()
        assert.same({"dhamma"},words)
        assert.equal("34626",value.original_clean)
    end)

    it("contains hit-testing failure before onLink and consumes that tap", function()
        local viewer, state = harness()
        viewer.linkAt = function() error("native links failed") end
        assert.is_true(viewer.scroll.htmlbox_widget:onTapText(nil, {pos={x=1,y=1},time=1}))
        assert.is_true(viewer.closed)
        assert.equal(1, state.errors)
        assert.matches("native links failed", warnings[1], 1, true)
    end)

    it("contains deferred edit-search and error-display failures", function()
        local viewer, state = harness({edit_callback=function() error("edit failed") end})
        viewer.showError = function() error("message failed") end
        viewer:onLink("dpd:edit-search")
        state:flush()
        assert.is_true(viewer.closed)
        assert.equal(2, #warnings)
        assert.matches("edit failed", warnings[1], 1, true)
        assert.matches("message failed", warnings[2], 1, true)
    end)
end)

describe("manual miss recovery", function()
    it("reopens search over the miss popup, once for repeated taps", function()
        local value = model("missing")
        value.found = false
        local viewer, state, edits
        edits = 0
        viewer, state = harness({model=value,edit_callback=function(_, _, _, replaced)
            assert.equal(viewer, replaced)
            assert.is_falsy(viewer.closed)
            edits = edits + 1
        end})
        assert.is_truthy(viewer.scroll.html_body:find('dpd:edit-search',1,true))
        local child = model("missing child")
        child.found = false
        viewer.navigation:push(child)
        viewer:update(); state:flush()
        assert.is_falsy(viewer.scroll.html_body:find('dpd:edit-search',1,true))
        viewer:back(); state:flush()
        viewer:onLink("dpd:edit-search"); viewer:onLink("dpd:edit-search")
        assert.equal(0,edits)
        state:flush()
        assert.equal(1,edits)
    end)
end)

describe("edit and action buttons", function()
    it("edits the given text and mode with the popup left open for Cancel", function()
        local viewer, state, edits = nil, nil, {}
        viewer, state = harness({edit_callback=function(text, mode, parent, replaced)
            edits[#edits + 1] = {text, mode, parent, replaced}
        end})
        viewer:editSearch("dhammo", "pali"); viewer:editSearch("dhammo", "pali")
        state:flush()
        assert.equal(1, #edits)
        assert.same({"dhammo", "pali"}, {edits[1][1], edits[1][2]})
        assert.is_nil(edits[1][3])
        assert.equal(viewer, edits[1][4])
        assert.is_falsy(viewer.closed)
    end)

    it("keeps a view opened from an entry open and edits it as a child, once for repeated taps", function()
        local viewer, state, edits = nil, nil, {}
        viewer, state = harness({edit_callback=function(text, mode, parent)
            edits[#edits + 1] = {text, mode, parent}
        end})
        viewer.navigation:push(model("dharati"))
        viewer:update(); state:flush()
        viewer:editSearch("dharati", "pali", true); viewer:editSearch("dharati", "pali", true)
        state:flush()
        assert.equal(1, #edits)
        assert.same({"dharati", "pali"}, {edits[1][1], edits[1][2]})
        assert.equal(viewer, edits[1][3])
        assert.is_falsy(viewer.closed)
        assert.equal(2, #viewer.navigation.stack)
    end)

    it("draws only the buttons this popup has, and ignores a bounce right after a rebuild", function()
        local handoffs = 0
        local viewer, state = harness({normal_callback=function() handoffs = handoffs + 1 end})
        assert.truthy(viewer.action_buttons["dpd:normal"])
        assert.is_nil(viewer.action_buttons["dpd:dictionaries"])
        viewer:tapButton("dpd:normal"); state:flush()
        assert.equal(0, handoffs)
        viewer.link_guard_s = -1
        viewer:tapButton("dpd:normal"); state:flush()
        assert.equal(1, handoffs)
        assert.is_true(viewer.closed)
        local plain = harness()
        assert.same({}, plain.action_buttons)
    end)
end)

describe("searching the other dictionaries", function()
    local function search(query)
        return {query=query, found=false, dictionary_search=true, matched_via="dictionaries",
            dictionaries={keys={query}, groups={}}, senses={}, grammar={}, deconstructions={},
            suggestions={}, references={}, variants={}}
    end
    local function row(viewer)
        local out = {}
        for _, button in ipairs(viewer.window[1][3][2].buttons[1]) do out[#out+1] = {button.text, button.enabled} end
        return out
    end

    it("offers DPD for the typed word, over the search, until Back returns to it", function()
        local looked_up
        local lookup = {get=function(_, query, options)
            looked_up = {query, options.spelling}
            return model("dharma in DPD")
        end}
        local viewer, state = harness({model=search("dharma"), lookup=lookup, normal_callback=function() end})
        assert.same({{"DPD", true}, {"KOReader dictionary", true}}, row(viewer))
        viewer:onLink("dpd:dpd-lookup"); state:flush()
        assert.same({"dharma", true}, looked_up)
        assert.equal("dharma in DPD", viewer.navigation:current().model.query)
        assert.same({{"DPD", false}, {"KOReader: dharma", true}}, row(viewer))
        viewer:onLink("dpd:dpd-lookup"); state:flush()
        assert.equal(2, #viewer.navigation.stack)
        viewer:back(); state:flush()
        assert.equal("dharma", viewer.navigation:current().model.query)
        assert.same({{"DPD", true}, {"KOReader dictionary", true}}, row(viewer))
    end)
end)

describe("article footer", function()
    local function article(direct, normal)
        local value = model("kamma")
        value.dictionary_search = direct
        value.dictionaries = {groups={{id="cpd", entries={{id=1, word="kamma"}}}}}
        return harness({model=value, normal_callback=normal and function() end or nil,
            lookup={hasOtherDictionaries=function() return true end, dictionaryPage=function(_, _, offset)
                return {html="<p>article</p>", offset=offset, next_offset=offset+10,
                    total=30, has_more=offset < 20}
            end}})
    end
    local function row(viewer)
        local actions = viewer.window[1][3][2].buttons
        assert.equal(1, #actions)
        local out = {}
        for _, button in ipairs(actions[1]) do out[#out+1] = {button.text, button.enabled} end
        return out
    end

    for _, direct in ipairs({false, true}) do
        for _, normal in ipairs({false, true}) do
            it("keeps one row in each article state, direct=" .. tostring(direct) .. ", normal=" .. tostring(normal), function()
                local viewer, state = article(direct, normal)
                local frame = viewer.navigation:current()
                viewer.dictionaries = {"cpd"}
                local function expected(buttons, open)
                    if direct then buttons[#buttons+1] = {"DPD", true}
                    elseif not open then buttons[#buttons+1] = {"Other dictionaries", false} end
                    if normal then buttons[#buttons+1] = {"KOReader dictionary", true} end
                    return buttons
                end
                viewer:update(); state:flush()
                assert.same(expected({}, false), row(viewer))
                for _, case in ipairs({
                    {part=1, more=true, prev=false, next=true},
                    {part=2, more=true, prev=true, next=true},
                    {part=3, more=false, prev=true, next=false},
                    {part=1, more=false},
                }) do
                    frame.dictionary_pages = {["1/1"]={open=true, html="<p>article</p>", part=case.part,
                        has_more=case.more}}
                    viewer:update(); state:flush()
                    local buttons = {}
                    if case.prev ~= nil then buttons = {{"◂ Part", case.prev}, {"Part ▸", case.next}} end
                    buttons[#buttons+1] = {"Entries", true}
                    assert.same(expected(buttons, true), row(viewer))
                end
                frame.dictionary_pages["1/1"].open = false
                viewer:update(); state:flush()
                assert.same(expected({}, false), row(viewer))
            end)
        end
    end

    it("routes article callbacks through the rebuild guard and restores the collapsed heading from mid-part", function()
        local viewer, state = article(false, true)
        local key = "1/1"
        viewer:onLink("dpd:dict-entry/" .. key); state:flush()
        local frame = viewer.navigation:current()
        local next_button = viewer.action_buttons["dpd:dict-next/" .. key]
        next_button.callback()
        assert.equal(1, frame.dictionary_pages[key].part)
        viewer.link_guard_s = -1
        next_button.callback(); next_button.callback(); state:flush()
        assert.equal(2, frame.dictionary_pages[key].part)
        viewer.action_buttons["dpd:dict-prev/" .. key].callback(); state:flush()
        assert.equal(1, frame.dictionary_pages[key].part)
        for _, footer in ipairs({true, false}) do
            viewer.scroll.htmlbox_widget.page_number = 8
            state.page_count, state.links = 20, {[14]={"dpd:dict-entry/" .. key}}
            if footer then viewer.action_buttons["dpd:dict-entry/" .. key].callback()
            else viewer:onLink("dpd:dict-entry/" .. key) end
            state:flush()
            assert.is_false(frame.dictionary_pages[key].open)
            assert.is_nil(frame.dictionary_pages[key].html)
            assert.equal(14, viewer.scroll.htmlbox_widget.page_number)
            assert.is_nil(viewer.action_buttons["dpd:dict-entry/" .. key])
            viewer:onLink("dpd:dict-entry/" .. key); state:flush()
        end
    end)
end)

describe("dictionary pager hit regions", function()
    it("keeps compact neighboring senses independently tappable", function()
        local viewer = harness()
        viewer.font_px = 16
        local links = {
            {uri="dpd:sense/1",x0=20,x1=100,y0=40,y1=56},
            {uri="dpd:sense/2",x0=20,x1=100,y0=60,y1=76},
        }
        local box = {page_number=1,getPosFromAbsPos=function(_,p) return p end,
            document={openPage=function() return {getPageLinks=function() return links end,close=function() end} end}}
        assert.equal(links[1],viewer:linkAt(box,{x=500,y=57.5}))
        assert.equal(links[2],viewer:linkAt(box,{x=500,y=58.5}))
        assert.is_nil(viewer:linkAt(box,{x=500,y=30}))
        assert.is_nil(viewer:linkAt(box,{x=500,y=90}))
    end)

    it("keeps legacy full-width footer targets separated", function()
        local viewer = harness()
        local links = {
            {uri="dpd:dict-prev/1/1",x0=80,x1=180,y0=40,y1=60},
            {uri="dpd:dict-next/1/1",x0=80,x1=180,y0=95,y1=115},
            {uri="dpd:dict-entries/1",x0=80,x1=180,y0=150,y1=170},
            {uri="dpd:dict-entry/1/1",x0=80,x1=180,y0=205,y1=225},
        }
        local box = {page_number=1,getPosFromAbsPos=function(_,p) return p end,
            document={openPage=function() return {getPageLinks=function() return links end,close=function() end} end}}
        viewer.font_px = 16
        assert.equal(links[1],viewer:linkAt(box,{x=500,y=50}))
        assert.equal(links[2],viewer:linkAt(box,{x=500,y=105}))
        assert.equal(links[3],viewer:linkAt(box,{x=500,y=160}))
        assert.equal(links[4],viewer:linkAt(box,{x=500,y=215}))
        assert.is_nil(viewer:linkAt(box,{x=500,y=78}))
    end)

    it("routes padded cell corners independently of a neighboring button", function()
        local viewer = harness()
        viewer.font_px = 16
        viewer.control_layout.buttons = {
            ["dpd:dict-prev/1/1"]={width_em=10,height_em=4},
            ["dpd:dict-next/1/1"]={width_em=10,height_em=4},
        }
        local links = {
            {uri="dpd:dict-prev/1/1",x0=50,x1=110,y0=40,y1=60},
            {uri="dpd:dict-next/1/1",x0=230,x1=290,y0=40,y1=60},
        }
        local box = {page_number=1,getPosFromAbsPos=function(_,p) return p end,
            document={openPage=function() return {getPageLinks=function() return links end,close=function() end} end}}
        assert.equal(links[1],viewer:linkAt(box,{x=3,y=21}))
        assert.equal(links[2],viewer:linkAt(box,{x=337,y=79}))
        assert.is_nil(viewer:linkAt(box,{x=170,y=50}))
    end)

    it("includes every wrapped label line without merging a repeated pager", function()
        local viewer = harness()
        viewer.font_px = 16
        viewer.control_layout.buttons = { ["dpd:variants-next"]={width_em=10,height_em=4} }
        local links = {
            {uri="dpd:variants-next",x0=30,x1=130,y0=40,y1=56},
            {uri="dpd:variants-next",x0=52,x1=112,y0=60,y1=76},
            {uri="dpd:variants-next",x0=30,x1=130,y0=160,y1=176},
        }
        assert.same({x0=2,x1=162,y0=16,y1=100}, viewer:buttonBounds(links[1],links))
        assert.same({x0=0,x1=160,y0=136,y1=200}, viewer:buttonBounds(links[3],links))
    end)
end)

describe("viewer screen resize", function()
    it("follows KOReader's text selection rate", function()
        assert.equal(30, harness().ges_events.HoldPanText[1].rate)
        assert.equal(5, harness({low_pan_rate=true}).ges_events.HoldPanText[1].rate)
        assert.equal(12, harness({low_pan_rate=true, settings={hold_pan_rate=12}}).ges_events.HoldPanText[1].rate)
    end)

    it("reflows once for both device events and updates the entire gesture rectangle", function()
        local viewer, state = harness()
        local frame = viewer.navigation:current()
        frame.expanded[12], frame.details[12], frame.grammar_open = true, {meaning="detail"}, true
        viewer.scroll:scrollToRatio(.4)
        state:resize(900, 600)
        assert.same({w=900,h=600}, viewer.dimen)
        assert.equal(viewer.dimen, viewer.ges_events.TapOutside[1].range())
        assert.equal(1, #state.queue)
        state:flush()
        assert.equal(2, state.builds)
        assert.equal(viewer.dimen, viewer[1].dimen)
        assert.equal(.4, viewer:ratio())
        assert.equal(frame, viewer.navigation:current())
        assert.is_true(frame.expanded[12])
        assert.is_true(frame.grammar_open)
        assert.same({meaning="detail"}, frame.details[12])
        state:resize(600, 900); state:flush()
        assert.equal(3, state.builds)
        assert.equal(.4, viewer:ratio())
    end)

    it("coalesces content updates and successive resizes into the latest dimensions", function()
        local viewer, state = harness()
        viewer:update()
        state:resize(900, 600)
        state:resize(800, 600)
        assert.equal(1, #state.queue)
        state:flush()
        assert.equal(2, state.builds)
        assert.same({w=800,h=600}, viewer[1].dimen)
        viewer:onScreenResize({w=800,h=600})
        assert.equal(0, #state.queue)
    end)

    it("keeps a pending Back target's saved scroll instead of copying the visible child's", function()
        local viewer, state = harness()
        viewer.navigation:push(model("child"), .3)
        viewer:update(); state:flush()
        viewer.scroll:scrollToRatio(.6)
        viewer:back()
        state:resize(900, 600); state:flush()
        assert.equal("root", viewer.navigation:current().model.query)
        assert.equal(.3, viewer:ratio())
        assert.equal(1, #viewer.navigation.stack)
    end)

    it("preserves a pending append operation's current page", function()
        local viewer, state = harness()
        local frame = viewer.navigation:current()
        viewer.scroll:scrollToRatio(.3)
        frame.restore_page = viewer.scroll.htmlbox_widget.page_number
        viewer:update()
        state:resize(900, 600); state:flush()
        assert.equal(4, viewer.scroll.htmlbox_widget.page_number)
        assert.is_nil(frame.restore_page)
    end)

    it("retains the old tree and page when scrolling the replacement fails", function()
        local viewer, state = harness()
        local old_tree, old_scroll = viewer[1], viewer.scroll
        local frame = viewer.navigation:current()
        frame.restore_page = 4
        state.fail_restore = true
        state:resize(900, 600); state:flush()
        assert.equal(old_tree, viewer[1])
        assert.equal(old_scroll, viewer.scroll)
        assert.is_falsy(old_tree.freed)
        assert.is_true(state.scrolls[2].freed)
        assert.equal(4, frame.restore_page)
        assert.equal(1, state.errors)
        state.fail_restore = false
        viewer:update(); state:flush()
        assert.is_true(old_tree.freed)
        assert.equal(4, viewer.scroll.htmlbox_widget.page_number)
    end)

    it("closes rather than keep stale links when building a new entry fails", function()
        local viewer, state = harness()
        viewer.navigation:push(model("war"), 0)
        state.fail_restore = true
        viewer:update(); state:flush()
        assert.is_true(viewer.closed)
        assert.equal(1, state.errors)
    end)

    it("closes rather than keep stale paging controls when Next part fails to build", function()
        local value = model("tissa")
        value.dictionaries = {keys={"tissa"}, groups={{id="dppn", name="DPPN", total=1, entries={{id=9, word="Tissa"}}}}}
        local viewer, state = harness({model=value, lookup={dictionaryPage=function(_, _, offset)
            return {html="<p>" .. offset .. "</p>", offset=offset, next_offset=offset + 10, total=30, has_more=true}
        end}})
        viewer.navigation:current().dictionary_pages = {["1/1"]={open=true, html="<p>0</p>", offset=0,
            next_offset=10, total=30, has_more=true, starts={}, part=1}}
        state.fail_restore = true
        viewer:onLink("dpd:dict-next/1/1"); state:flush()
        assert.is_true(viewer.closed)
        assert.equal(1, state.errors)
    end)

    it("keeps the selected article visible when a long preceding article closes", function()
        local value = model("tissa")
        value.dictionaries = {keys={"tissa"}, groups={{id="dppn", name="DPPN", total=2,
            entries={{id=1, word="Tissa"}, {id=2, word="Tissa"}}}}}
        local viewer, state = harness({model=value, lookup={dictionaryPage=function()
            return {html="<p>article</p>", offset=0, next_offset=10, total=10, has_more=false}
        end}})
        state.page_count, state.links = 30, {[1]={"dpd:dict-entry/1/1"}}
        viewer:onLink("dpd:dict-entry/1/1"); state:flush()
        viewer.scroll.htmlbox_widget.page_number = 25
        -- Collapsing the first article moves the second title back many pages.
        -- Its new position can still be beyond the ordinary eight-page anchor search.
        state.page_count, state.links = 20, {[14]={"dpd:dict-entry/1/2"}}
        viewer:onLink("dpd:dict-entry/1/2"); state:flush()
        assert.equal(14, viewer.scroll.htmlbox_widget.page_number)
        local pages = viewer.navigation:current().dictionary_pages
        assert.is_true(pages["1/2"].open)
        assert.is_false(pages["1/1"].open)
        assert.is_nil(pages["1/1"].html)
        -- Collapsing the selected article keeps its title in place too.
        viewer:onLink("dpd:dict-entry/1/2"); state:flush()
        assert.equal(14, viewer.scroll.htmlbox_widget.page_number)
        assert.is_false(pages["1/2"].open)
    end)

    it("retains reading pages per article and part relative to a moving heading", function()
        local value = model("kamma")
        value.dictionaries = {groups={{id="cpd", entries={{id=1, word="kamma"}, {id=2, word="kamma"}}}}}
        local total = 30
        local viewer, state = harness({model=value, lookup={dictionaryPage=function(_, _, offset)
            return {html="<p>article</p>", offset=offset, next_offset=offset+10,
                total=total, has_more=offset+10 < total}
        end}})
        state.page_count, state.links = 20, {[2]={"dpd:dict-entry/1/1"}, [16]={"dpd:dict-entry/1/2"}}
        local function tap(uri) viewer:onLink("dpd:" .. uri); state:flush() end
        tap("dict-entry/1/1")
        viewer.scroll.htmlbox_widget.page_number = 7
        tap("dict-next/1/1")
        assert.equal(2, viewer.scroll.htmlbox_widget.page_number, "unread part starts at heading")
        viewer.scroll.htmlbox_widget.page_number = 5
        tap("dict-prev/1/1")
        assert.equal(7, viewer.scroll.htmlbox_widget.page_number, "previous part retains reading page")
        tap("dict-entry/1/1"); tap("dict-entry/1/1")
        assert.equal(7, viewer.scroll.htmlbox_widget.page_number, "first part also retains reading page")
        tap("dict-next/1/1")
        assert.equal(5, viewer.scroll.htmlbox_widget.page_number)
        tap("dict-entry/1/1")
        assert.equal(2, viewer.scroll.htmlbox_widget.page_number, "Entries returns to heading")
        -- Another article can move the saved heading without changing its reading position.
        state.links = {[4]={"dpd:dict-entry/1/1"}, [16]={"dpd:dict-entry/1/2"}}
        tap("dict-entry/1/1")
        assert.equal(7, viewer.scroll.htmlbox_widget.page_number, "reopen uses heading-relative page")
        tap("dict-entry/1/2")
        viewer.scroll.htmlbox_widget.page_number = 18
        tap("dict-entry/1/1")
        assert.equal(7, viewer.scroll.htmlbox_widget.page_number)
        tap("dict-entry/1/2")
        assert.equal(18, viewer.scroll.htmlbox_widget.page_number, "articles retain separate pages")
        tap("dict-entry/1/1"); tap("dict-entry/1/1")
        state.page_count = 5
        tap("dict-entry/1/1")
        assert.equal(5, viewer.scroll.htmlbox_widget.page_number, "shorter layout clamps saved page")
        tap("dict-entry/1/1")
        total = 40
        tap("dict-entry/1/1")
        assert.equal(4, viewer.scroll.htmlbox_widget.page_number, "changed article discards old reading pages")
        assert.same({}, viewer.navigation:current().dictionary_pages["1/1"].reading_pages)
    end)

    it("bounds a saved article page by its last Part control rather than later entries", function()
        local value = model("kamma")
        value.dictionaries = {groups={{id="cpd", entries={{id=1, word="kamma"}, {id=2, word="kamma"}}}}}
        local viewer, state = harness({model=value, lookup={dictionaryPage=function(_, _, offset)
            return {html="<p>article</p>", offset=offset, next_offset=10, total=20, has_more=true}
        end}})
        state.page_count, state.links = 20, {[2]={"dpd:dict-entry/1/1"},
            [8]={"dpd:dict-next/1/1"}, [14]={"dpd:dict-entry/1/2"}}
        local function tap() viewer:onLink("dpd:dict-entry/1/1"); state:flush() end
        tap()
        viewer.scroll.htmlbox_widget.page_number = 14
        tap(); tap()
        assert.equal(8, viewer.scroll.htmlbox_widget.page_number)
    end)

    it("resumes an article's part when it is reopened in the same view", function()
        local value = model("tissa")
        value.dictionaries = {keys={"tissa"}, groups={{id="dppn", name="DPPN", total=2,
            entries={{id=1, word="Tissa"}, {id=2, word="Tissa"}}}}}
        local totals, loads = {[1]=30, [2]=30}, {}
        local viewer, state = harness({model=value, lookup={dictionaryPage=function(_, id, offset)
            loads[#loads + 1] = id .. "@" .. offset
            local total = totals[id]
            return {html=offset < total and ("<p>" .. id .. "@" .. offset .. "</p>") or "", offset=offset,
                next_offset=offset + 10, total=total, has_more=offset + 10 < total}
        end}})
        local pages = function() return viewer.navigation:current().dictionary_pages end
        local tap = function(uri) viewer:onLink(uri); state:flush() end
        tap("dpd:dict-entry/1/1"); tap("dpd:dict-next/1/1")
        assert.equal(2, pages()["1/1"].part)
        -- Collapsing frees the part's HTML but keeps where it was.
        tap("dpd:dict-entry/1/1")
        assert.is_false(pages()["1/1"].open)
        assert.is_nil(pages()["1/1"].html)
        tap("dpd:dict-entry/1/1")
        assert.same({open=true, part=2, offset=10}, {open=pages()["1/1"].open, part=pages()["1/1"].part,
            offset=pages()["1/1"].offset})
        -- Another entry closes this one; coming back resumes both.
        tap("dpd:dict-entry/1/2"); tap("dpd:dict-next/1/2"); tap("dpd:dict-next/1/2")
        assert.is_nil(pages()["1/1"].html)
        tap("dpd:dict-entry/1/1")
        assert.equal(2, pages()["1/1"].part)
        assert.is_nil(pages()["1/2"].html)
        tap("dpd:dict-entry/1/2")
        assert.equal(3, pages()["1/2"].part)
        assert.equal(20, pages()["1/2"].offset)
        -- Previous part steps back from a resumed part, not from the saved one.
        tap("dpd:dict-prev/1/2")
        assert.same({2, 10}, {pages()["1/2"].part, pages()["1/2"].offset})
        tap("dpd:dict-prev/1/2")
        assert.same({1, 0}, {pages()["1/2"].part, pages()["1/2"].offset})
        -- An article whose length changed starts again from the top.
        tap("dpd:dict-entry/1/1")
        assert.equal(2, pages()["1/1"].part)
        tap("dpd:dict-entry/1/1")
        totals[1] = 50
        tap("dpd:dict-entry/1/1")
        assert.same({1, 0}, {pages()["1/1"].part, pages()["1/1"].offset})
        assert.same({"1@10", "1@0"}, {loads[#loads - 1], loads[#loads]})
        -- So does one that is now shorter than the saved offset.
        tap("dpd:dict-next/1/1"); tap("dpd:dict-entry/1/1")
        totals[1], pages()["1/1"].total = 5, 5
        tap("dpd:dict-entry/1/1")
        assert.same({1, 0}, {pages()["1/1"].part, pages()["1/1"].offset})
        assert.equal("<p>1@0</p>", pages()["1/1"].html)
    end)

    it("shows Back in a child popup and closes only that popup from its root", function()
        local root = harness()
        assert.is_nil(root.window[1][1].left_icon)
        local child = harness({parent_viewer=root})
        assert.equal("chevron.left", child.window[1][1].left_icon)
        child.window[1][1].left_icon_tap_callback()
        assert.is_true(child.closed)
        assert.is_falsy(root.closed)
    end)

    it("cancels queued reflows on close and rejects stale callbacks", function()
        local viewer, state = harness()
        state:resize(900, 600)
        local stale = state.queue[1]
        viewer:close()
        assert.equal(0, #state.queue)
        local dirty = state.dirty
        stale()
        viewer:update()
        state:resize(600, 900)
        assert.equal(1, state.builds)
        assert.equal(dirty, state.dirty)
        assert.equal(0, #state.queue)
    end)
end)

local function senses()
    local value = model("pacchima")
    value.senses = {{id=1, lemma_1="pacchima 1", pos="adj", meaning_combo="last"},
        {id=2, lemma_1="pacchima 2", pos="adj", meaning_combo="western"}}
    value.grammar = {{pos="adj", parse="nom", headword="pacchima 1"}, {pos="adj", parse="acc", headword="pacchima 1"},
        {pos="adj", parse="voc", headword="pacchima 1"}}
    return value
end

describe("viewer expansion keeps its place", function()
    local lookup = {detail=function() return {construction="x"} end}

    it("measures the HTML area after reserving the scrollbar and its gap", function()
        local viewer, state = harness()
        local function check()
            assert.equal((viewer.scroll.width - 6 - 12) / viewer.font_px, viewer.control_layout.content_em)
            assert.equal(viewer.control_layout.content_em, viewer.navigation:current().content_em)
        end
        check()
        state:resize(900, 600); state:flush()
        check()
    end)

    it("ignores a second tap on the old links while a rebuild is queued", function()
        local viewer, state = harness({model=senses(), lookup=lookup})
        viewer.built_at = -2 -- the initial post-build guard has expired
        viewer.linkAt = function() return {uri="dpd:sense/1"} end
        local box = viewer.scroll.htmlbox_widget
        box:onTapText(nil, {pos={},time=0})
        box:onTapText(nil, {pos={},time=.1})
        assert.is_true(viewer.navigation:current().expanded[1])
        assert.equal(1, #state.queue)
        state:flush()
        assert.equal(2, state.builds)
        assert.is_true(viewer.navigation:current().expanded[1])
        -- Once rebuilt and visible, an intentional later tap can collapse it.
        viewer.scroll.htmlbox_widget:onTapText(nil, {pos={},time=1})
        assert.is_nil(viewer.navigation:current().expanded[1])
    end)

    it("keeps the tapped page when expansion repaginates, without searching", function()
        local viewer, state = harness({model=senses(), lookup=lookup})
        viewer.scroll:scrollToRatio(.2)
        assert.equal(3, viewer.scroll.htmlbox_widget.page_number)
        state.page_count = 20 -- the old ratio would land on page 5
        viewer:onLink("dpd:sense/2"); state:flush()
        assert.equal(3, viewer.scroll.htmlbox_widget.page_number)
        assert.equal(0, state.opened)
        assert.is_true(viewer.navigation:current().expanded[2])
    end)

    it("follows a sense upward when opening it closes an expanded sense above", function()
        local viewer, state = harness({model=senses(), lookup=lookup})
        viewer:onLink("dpd:sense/1"); state:flush()
        viewer.scroll:scrollToRatio(.1)
        assert.equal(2, viewer.scroll.htmlbox_widget.page_number)
        state.page_count, state.links[1] = 6, {"dpd:sense/2"}
        viewer:onLink("dpd:sense/2"); state:flush()
        assert.equal(1, viewer.scroll.htmlbox_widget.page_number)
        assert.is_nil(viewer.navigation:current().expanded[1])
    end)

    it("follows the grammar toggle down when parses are inserted above it", function()
        local viewer, state = harness({model=senses(), lookup=lookup})
        state.links[2] = {"dpd:grammar-toggle"}
        viewer:onLink("dpd:grammar-toggle"); state:flush()
        assert.equal(2, viewer.scroll.htmlbox_widget.page_number)
        assert.is_true(viewer.navigation:current().grammar_open)
    end)

    it("bounds the search and keeps the old page when the control is not found", function()
        local viewer, state = harness({model=senses(), lookup=lookup})
        viewer.anchor_search_pages = 3
        viewer:onLink("dpd:sense/1"); state:flush()
        viewer.scroll:scrollToRatio(.5)
        local page = viewer.scroll.htmlbox_widget.page_number
        state.opened = 0
        viewer:onLink("dpd:sense/2"); state:flush()
        assert.equal(page, viewer.scroll.htmlbox_widget.page_number)
        assert.equal(4, state.opened) -- the kept page plus three earlier pages
    end)

    it("moves a row cut by a page break whole to the next page", function()
        local viewer = harness()
        local pages = {
            {{uri="dpd:sense/1", y0=10}, {uri="dpd:sense/2", y0=900}},
            {{uri="dpd:sense/2", y0=4}, {uri="dpd:sense/3", y0=60}},
        }
        local box = {page_count=2, dimen={h=960}, document={openPage=function(_, n)
            return {getPageLinks=function() return pages[n] end, close=function() end}
        end}}
        local html = '<div class="entry"><p class="row"><a href="dpd:sense/1" class="toggle">a</a></p></div>'
            .. '<div class="entry"><p class="row"><a href="dpd:sense/2" class="toggle">b</a></p></div>'
        local moved = viewer:moveSplitRow(box, html)
        assert.equal('<div class="entry"><p class="row"><a href="dpd:sense/1" class="toggle">a</a></p></div>'
            .. '<div class="entry" style="margin-top:60.0px"><p class="row"><a href="dpd:sense/2" class="toggle">b</a></p></div>',
            moved)
        -- A row from the top two thirds of a page would leave that page nearly empty.
        pages[1][2].y0 = 500
        assert.is_nil(viewer:moveSplitRow(box, html))
        -- Nothing continues across the break.
        pages[1][2].y0, pages[2][1].uri = 900, "dpd:sense/9"
        assert.is_nil(viewer:moveSplitRow(box, html))
    end)

    it("merges a field row's label and taller value into one line for holds", function()
        local viewer = harness()
        local function word(text, x0, x1) return {word=text, x0=x0, x1=x1} end
        local lines = viewer.mergeRowLines({
            {y0=192, y1=234, x0=50, x1=223, word("Construction", 50, 223)},
            {y0=192, y1=238, x0=362, x1=627, word("buddha", 362, 470), word("anussati", 500, 627)},
            {y0=236, y1=278, x0=50, x1=900, word("Sanskrit", 50, 160)},
        })
        assert.equal(2, #lines)
        assert.same({192, 238, 50, 627}, {lines[1].y0, lines[1].y1, lines[1].x0, lines[1].x1})
        assert.same({"Construction", "buddha", "anussati"},
            {lines[1][1].word, lines[1][2].word, lines[1][3].word})
        assert.equal("Sanskrit", lines[2][1].word)
    end)
end)
