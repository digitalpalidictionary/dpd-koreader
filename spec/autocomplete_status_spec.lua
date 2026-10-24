describe("autocomplete status and cancellation", function()
    local Input, state, saved
    local names = {"ui/widget/inputdialog","ui/uimanager","ui/widget/buttontable",
        "ui/widget/container/centercontainer","ui/geometry","ui/widget/verticalspan",
        "ui/widget/textboxwidget","ui/font","ui/dpd_input"}
    before_each(function()
        saved, state = {}, {queue={},queries=0}
        for _,name in ipairs(names) do saved[name]=package.loaded[name] end
        local widget={}
        function widget:new(value) return setmetatable(value or {},{__index=self}) end
        function widget:extend(value) return setmetatable(value or {},{__index=self}) end
        function widget:getSize() return self.dimen or {w=self.width,h=80} end
        function widget:free() self.freed=true end
        for _,name in ipairs(names) do package.loaded[name]=widget end
        package.loaded["ui/widget/inputdialog"]=widget:extend{
            width=420,getInputText=function(self) return self.input end,
            onCloseWidget=function() end,onShowKeyboard=function() end,addWidget=function() end}
        package.loaded["ui/uimanager"]={show=function() end,close=function(_,dialog) dialog:onCloseWidget() end,
            setDirty=function() end,scheduleIn=function(_,_,fn) state.queue[#state.queue+1]=fn end,
            unschedule=function(_,fn)
                for i=#state.queue,1,-1 do if state.queue[i]==fn then table.remove(state.queue,i) end end
            end}
        package.loaded["ui/font"]={getFace=function() return {} end}
        package.loaded["ui/dpd_input"]=nil
        Input=require("ui/dpd_input")
    end)
    after_each(function() for _,name in ipairs(names) do package.loaded[name]=saved[name] end end)

    local function dialog(suggest, options)
        options=options or {}
        options.settings=options.settings or {}
        options.input=options.input or "word"
        options.on_lookup=options.on_lookup or function() end
        options.suggest=function(...)
            state.queries=state.queries+1
            return suggest(...)
        end
        return Input.show(options)
    end
    local function pause(value)
        value.edited_callback()
        table.remove(state.queue,1)()
    end

    it("distinguishes completed-empty, unavailable and exceptions without resizing", function()
        for _,case in ipairs({
            {suggest=function() return {} end,text="No suggestions"},
            {suggest=function() return nil,"unavailable" end,text="check Database status"},
            {suggest=function() error("private diagnostic") end,text="Suggestions failed"},
            {suggest=function() return nil,"error" end,text="Suggestions failed"},
        }) do
            local value=dialog(case.suggest)
            local height=value.suggestion_area:getSize().h
            pause(value)
            assert.is_truthy(value.suggestion_area[1].text:find(case.text,1,true))
            assert.is_falsy(value.suggestion_area[1].text:find("private diagnostic",1,true))
            assert.equal(height,value.suggestion_area:getSize().h)
        end
    end)

    it("keeps idle input and numeric IDs blank without suggestion queries", function()
        for _,text in ipairs({"", "   ", "“”", "12345"}) do
            local value=dialog(function() error("must not query") end,{input=text})
            pause(value)
            assert.is_nil(value.suggestion_area[1].text)
        end
        assert.equal(0,state.queries)
    end)

    it("drops stale statuses and lets the newer edit fill the area", function()
        local value
        value=dialog(function()
            if state.queries==1 then value.input="new";value.edited_callback();return nil,"error" end
            return {{text="new"}}
        end)
        pause(value)
        assert.is_nil(value.suggestion_area[1].text)
        table.remove(state.queue,1)()
        assert.equal("new",value.suggestion_area[1].buttons[1][1].text)
    end)

    it("invalidates pending statuses on cancel and close", function()
        for _,close in ipairs({false,true}) do
            local value=dialog(function() return nil,"error" end)
            value.edited_callback()
            local pending=state.queue[1]
            if close then value:onCloseWidget() else value.cancel() end
            assert.equal(0,#state.queue)
            pending()
            assert.equal(0,state.queries)
            assert.is_nil(value.suggestion_area[1].text)
        end
    end)

    it("still submits an ordinary lookup from an empty suggestion state", function()
        local looked_up
        local value=dialog(function() return {} end,{input="  unknown  ",
            on_lookup=function(text) looked_up=text end})
        pause(value)
        value.buttons[1][4].callback()
        assert.equal("unknown",looked_up)
    end)
end)
