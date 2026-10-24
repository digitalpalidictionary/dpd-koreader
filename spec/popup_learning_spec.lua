local function model(query)
    return {query=query, original=query, found=true, senses={{id=1,lemma_1=query,meaning_combo="meaning"}},
        grammar={},deconstructions={},references={},suggestions={},roots={},variants={}}
end

-- Use the real plugin ownership methods, with isolated UI/database boundaries.
local function harness()
    local names = {"datastorage","dpd/db","ui/widget/infomessage","ui/widget/inputdialog",
        "ui/widget/pathchooser","ui/uimanager","ui/dpd_viewer","ui/widget/container/widgetcontainer",
        "libs/libkoreader-lfs","logger","ui/time","util","main"}
    local saved = {}
    for _, name in ipairs(names) do saved[name]=package.loaded[name]; package.loaded[name]={} end
    local state = {clears=0,book_clears=0,messages={},lookups={},normal={},pending={},events={}}
    local Viewer = {}
    function Viewer:new(value)
        if state.viewer_error then error("render failed") end
        return setmetatable(value,{__index=self})
    end
    function Viewer:clearTextSelection() state.clears=state.clears+1 end
    function Viewer:close(transfer)
        if self.closed or self.closing then return end
        self.closing=true
        if self.before_close_callback then self.before_close_callback() end
        self.closed=true
        state.events[#state.events+1]="close:"..self.model.query
        if self.close_callback then self.close_callback(transfer) end
    end
    package.loaded["ui/dpd_viewer"]=Viewer
    package.loaded["ui/widget/container/widgetcontainer"]={extend=function(_,value) return value end}
    package.loaded["ui/uimanager"]={show=function(_,widget) state.shown=widget end}
    package.loaded.util={cleanupSelectedText=function(word) return word end}
    package.loaded.logger={warn=function() end,dbg=function() end}
    package.loaded["ui/time"]={now=function() return 0 end,since=function() return 0 end,to_ms=function() return 0 end}
    package.loaded.main=nil
    local DPD=require("main")
    for _, name in ipairs(names) do package.loaded[name]=saved[name] end
    local dictionary={}
    function dictionary:showDict(word,_,_,_,callback)
        self.dict_window={word=word,dict_close_callback=callback}
        local window=self.dict_window
        function window:onClose()
            if self.closed then return end
            self.closed=true
            callback()
        end
    end
    function dictionary:showNoResultsDialog()
        state.no_results_prompts=(state.no_results_prompts or 0)+1
        return true
    end
    function dictionary:onLookupWord(word,sane,boxes,highlight,link,callback)
        state.normal[#state.normal+1]={word=word,sane=sane,boxes=boxes,highlight=highlight,link=link,callback=callback}
        if state.normal_error then error("dictionary failed") end
        local show=function()
            if state.no_results and self:showNoResultsDialog(word,{},false,boxes,link,callback) then return end
            self:showDict(word,{},boxes,link,callback)
        end
        if state.async then state.pending[#state.pending+1]=show else show() end
        return true
    end
    local plugin=setmetatable({settings={font_size=16},ui={dictionary=dictionary},lookup={},viewer_class=Viewer,
        db={close=function() state.events[#state.events+1]="database" end}},{__index=DPD})
    function plugin:message(text) state.messages[#state.messages+1]=text end
    function plugin:saveSettings() end
    function plugin:clearSelection(highlight,callback)
        if highlight then state.book_clears=state.book_clears+1 end
        if callback then callback() end
    end
    function plugin:getModel(word,options)
        state.lookups[#state.lookups+1]={word=word,options=options}
        if state.lookup_error then error("lookup failed") end
        if state.missing then return {query=word,found=false,senses={},grammar={},deconstructions={},roots={}} end
        return model(word)
    end
    return plugin,state,dictionary
end

describe("learning popup ownership",function()
    it("hands a typed headword ID's word, not the number, to KOReader dictionary",function()
        local plugin,state=harness()
        function plugin.lookup:byId(id)
            local result=model("dhamma 1.01")
            result.original,result.matched_via=tostring(id),"id"
            return result
        end
        assert.is_true(plugin:showId("34626"))
        plugin.viewer.normal_callback("34626")
        assert.equal("dhamma",state.normal[1].word)
        -- Edit search and Recent keep the typed ID.
        assert.equal("34626",plugin.viewer.model.original_clean)
        assert.same({{query="34626",mode="pali"}},plugin.settings.history)
    end)

    it("records a correction-only long-press like other accepted DPD lookups",function()
        local plugin,state=harness()
        local Lookup=require("dpd/lookup")
        local key="bhikkhunābhinandati"
        local lookup=Lookup.new({lookup=function(_,word)
            if word==key then return {lookup_key=key,spelling='["bhikkhu nābhinandati"]'} end
        end})
        plugin.settings.db_path="fixture.db"
        function plugin:directEnabled() return true end
        function plugin:getModel(word,options) return lookup:get(word,options) end
        local announced={}
        function plugin:announceLookup(word) announced[#announced+1]=word;return true end
        assert.is_true(plugin:tryDirect(key,true,nil,{},nil,function() end))
        assert.same({key},announced)
        assert.equal(0,#state.normal)
        assert.equal(key,plugin.viewer.model.query)
        assert.equal(0,#plugin.viewer.model.senses)
        assert.same({{query=key,mode="pali"}},plugin.settings.history)
    end)

    it("releases a failed handoff's book selection and callback at most once",function()
        local plugin,state=harness()
        local callbacks=0
        plugin:showModel(model("root"),{highlight={},close_callback=function() callbacks=callbacks+1 end})
        local viewer=plugin.viewer
        viewer:close(true)
        assert.equal(0,state.book_clears)
        assert.equal(0,callbacks)
        viewer.release_selection_callback();viewer.release_selection_callback()
        assert.equal(1,state.book_clears)
        assert.equal(1,callbacks)
        assert.equal(0,#plugin.viewers)
        assert.is_nil(plugin.viewer)
    end)
    it("keeps the parent live and restores it when a selected-word child closes",function()
        local plugin,state=harness()
        local clear_calls=0
        plugin:showModel(model("parent"),{highlight={}})
        local parent=plugin.viewer
        parent.scroll_marker=.4;parent.expansion_marker=true
        assert.is_true(plugin:lookupFromPopup(parent,"child",function() clear_calls=clear_calls+1 end))
        local child=plugin.viewer
        assert.equal(parent,child.parent_viewer)
        assert.is_falsy(parent.closed)
        assert.equal(2,#plugin.viewers)
        assert.is_false(state.lookups[1].options.prefix)
        child:close();child:close()
        assert.equal(parent,plugin.viewer)
        assert.equal(.4,parent.scroll_marker)
        assert.is_true(parent.expansion_marker)
        assert.equal(1,clear_calls)
        assert.equal(0,state.book_clears)
        parent:close();parent:close()
        assert.equal(1,state.book_clears)
    end)

    it("replaces only the child when its lookup is edited, and starts fresh once the parent is gone",function()
        local plugin=harness()
        local saved=package.loaded["ui/dpd_input"]
        local input
        package.loaded["ui/dpd_input"]={show=function(options) input=options; return options end}
        function plugin:ensureLookup() return self.lookup end
        plugin:showModel(model("parent"),{highlight={}})
        local parent=plugin.viewer
        parent.expansion_marker=true
        plugin:lookupFromPopup(parent,"child",function() end)
        -- The pencil closes the child, then opens the edit dialog.
        local child=plugin.viewer
        child:close();child.edit_callback()
        assert.equal("child",input.input)
        input.on_lookup("kusala","pali","kusala")
        local edited=plugin.viewer
        assert.equal("kusala",edited.model.query)
        assert.equal(parent,edited.parent_viewer)
        assert.is_falsy(parent.closed)
        assert.is_true(parent.expansion_marker)
        assert.equal(2,#plugin.viewers)
        -- Editing again keeps the same parent, in every search mode.
        edited:close();edited.edit_callback(nil,"english")
        plugin.lookup.english=function(_,query) return model(query) end
        input.on_lookup("wholesome","english","wholesome")
        assert.equal(parent,plugin.viewer.parent_viewer)
        -- A parent closed while the dialog was open makes the edit a fresh search.
        local last=plugin.viewer
        last:close();last.edit_callback()
        parent:close()
        input.on_lookup("kamma","pali","kamma")
        assert.equal("kamma",plugin.viewer.model.query)
        assert.is_nil(plugin.viewer.parent_viewer)
        assert.equal(1,#plugin.viewers)
        package.loaded["ui/dpd_input"]=saved
    end)

    it("opens an edit of a view opened from an entry as its child, so Back returns to it",function()
        local plugin=harness()
        local saved=package.loaded["ui/dpd_input"]
        local input
        package.loaded["ui/dpd_input"]={show=function(options) input=options; return options end}
        function plugin:ensureLookup() return self.lookup end
        plugin:showModel(model("dhamma"),{highlight={}})
        local root=plugin.viewer
        -- The pencil on a linked view passes the popup itself and leaves it open.
        root.edit_callback("dharati","pali",root)
        assert.equal("dharati",input.input)
        input.on_lookup("kusala","pali","kusala")
        local edited=plugin.viewer
        assert.equal("kusala",edited.model.query)
        assert.equal(root,edited.parent_viewer)
        assert.is_falsy(root.closed)
        assert.equal(2,#plugin.viewers)
        -- Editing that result again replaces only it.
        edited:close();edited.edit_callback()
        input.on_lookup("kamma","pali","kamma")
        assert.equal(root,plugin.viewer.parent_viewer)
        assert.equal(2,#plugin.viewers)
        package.loaded["ui/dpd_input"]=saved
    end)

    it("remembers successful in-popup word lookups but not fallbacks",function()
        local plugin,state=harness()
        plugin:showModel(model("parent"),{highlight={}})
        plugin:lookupFromPopup(plugin.viewer,"child",function() end)
        assert.same({{query="child",mode="pali"}},plugin.settings.history)
        state.missing=true
        plugin:lookupFromPopup(plugin.viewer,"unknown",function() end)
        assert.equal(1,#plugin.settings.history)
    end)

    it("closes descendants before the root and the shared database",function()
        local plugin,state=harness()
        plugin:showModel(model("root"),{highlight={}})
        local root=plugin.viewer
        plugin:lookupFromPopup(root,"child",function() end)
        plugin:lookupFromPopup(plugin.viewer,"grandchild",function() end)
        plugin:closeDatabase()
        assert.same({"close:grandchild","close:child","close:root","database"},state.events)
        assert.equal(1,state.book_clears)
        assert.equal(0,#plugin.viewers)
        assert.is_nil(plugin.viewer)
    end)

    it("falls back with no book highlight and clears only the popup selection",function()
        local plugin,state,dictionary=harness()
        local previous={word="unrelated"}
        dictionary.dict_window=previous
        local original=dictionary.showDict
        plugin:showModel(model("parent"),{highlight={}})
        local parent=plugin.viewer
        local clears=0
        state.missing=true
        assert.is_true(plugin:lookupFromPopup(parent,"unknown",function() clears=clears+1 end))
        assert.equal(parent,plugin.viewer)
        assert.is_falsy(parent.closed)
        assert.equal(1,#state.normal)
        assert.is_nil(state.normal[1].highlight)
        assert.is_nil(state.normal[1].boxes)
        assert.equal(0,clears)
        dictionary.dict_window:onClose()
        dictionary.dict_window:onClose()
        assert.equal(1,clears)
        assert.equal(0,state.book_clears)
        assert.equal(original,dictionary.showDict)
        assert.is_falsy(previous.closed)
    end)

    it("transfers a child's HTML selection to an owned normal fallback exactly once",function()
        local plugin,state,dictionary=harness()
        local clears=0
        plugin:showModel(model("parent"),{highlight={}})
        local parent=plugin.viewer
        plugin:lookupFromPopup(parent,"child",function() clears=clears+1 end)
        local child=plugin.viewer
        child:close(true)
        child.normal_callback("child")
        assert.equal(parent,plugin.viewer)
        assert.equal(0,clears)
        dictionary.dict_window:onClose()
        assert.equal(1,clears)
        assert.equal(0,state.book_clears)
    end)

    it("opens DPD from an owned fallback as a child, keeping the parent and fallback",function()
        local plugin,state,dictionary=harness()
        local clears=0
        plugin:showModel(model("parent"),{highlight={}})
        local parent=plugin.viewer
        state.missing=true
        plugin:lookupFromPopup(parent,"unknown",function() clears=clears+1 end)
        local fallback=dictionary.dict_window
        state.missing=false
        assert.is_true(plugin:fromDictionary(fallback))
        local child=plugin.viewer
        assert.equal(parent,child.parent_viewer)
        assert.is_falsy(parent.closed)
        assert.is_falsy(fallback.closed)
        -- KOReader dictionary returns to the fallback still beneath the child.
        child:close(true)
        child.normal_callback("unknown")
        assert.equal(fallback,dictionary.dict_window)
        assert.is_falsy(fallback.closed)
        assert.equal(parent,plugin.viewer)
        assert.equal(0,clears)
        fallback:onClose()
        assert.equal(1,clears)
        assert.equal(0,state.book_clears)
        parent:close()
        assert.equal(1,state.book_clears)
    end)

    it("falls back after DPD errors and cleans up when the normal dictionary also fails",function()
        local plugin,state=harness()
        plugin:showModel(model("parent"))
        local parent=plugin.viewer
        state.lookup_error=true;state.normal_error=true
        local clears=0
        assert.is_false(plugin:lookupFromPopup(parent,"broken",function() clears=clears+1 end))
        assert.equal(1,clears)
        assert.equal(parent,plugin.viewer)
        assert.is_falsy(parent.closed)
        assert.is_nil(next(plugin.popup_fallbacks))
        assert.is_nil(plugin.popup_fallback_hook)
    end)

    it("bounds popup depth without closing the existing stack",function()
        local plugin,state=harness()
        plugin.max_popup_depth=2
        plugin:showModel(model("parent"))
        plugin:lookupFromPopup(plugin.viewer,"child",function() end)
        local child=plugin.viewer
        local cleared=0
        assert.is_false(plugin:lookupFromPopup(child,"grandchild",function() cleared=cleared+1 end))
        assert.equal(child,plugin.viewer)
        assert.equal(2,#plugin.viewers)
        assert.equal(1,cleared)
        assert.equal(1,#state.messages)
    end)

    it("uses normal dictionaries when rendering a child fails",function()
        local plugin,state,dictionary=harness()
        plugin:showModel(model("parent"))
        local parent=plugin.viewer
        state.viewer_error=true
        local clears=0
        assert.is_true(plugin:lookupFromPopup(parent,"child",function() clears=clears+1 end))
        assert.equal(parent,plugin.viewer)
        assert.is_falsy(parent.closed)
        assert.equal(1,#plugin.viewers)
        assert.equal("child",dictionary.dict_window.word)
        dictionary.dict_window:onClose()
        assert.equal(1,clears)
    end)

    it("dismisses only an owned fallback before closing its parent",function()
        local plugin,state,dictionary=harness()
        plugin:showModel(model("parent"),{highlight={}})
        local parent=plugin.viewer
        state.missing=true
        plugin:lookupFromPopup(parent,"unknown",function() end)
        local owned=dictionary.dict_window
        dictionary.dict_window={word="foreign",onClose=function() error("closed unrelated dictionary") end}
        parent:close()
        assert.is_true(owned.closed)
        assert.equal(1,state.book_clears)
        assert.equal("foreign",dictionary.dict_window.word)
    end)

    it("rejects an asynchronous fallback finishing after its parent is closed",function()
        local plugin,state,dictionary=harness()
        local original=dictionary.showDict
        local foreign={word="foreign"}
        dictionary.dict_window=foreign
        plugin:showModel(model("parent"))
        local parent=plugin.viewer
        state.async=true;state.missing=true
        local clears=0
        plugin:lookupFromPopup(parent,"unknown",function() clears=clears+1 end)
        plugin:closeDatabase()
        assert.equal(1,clears)
        state.pending[1]()
        assert.equal(foreign,dictionary.dict_window)
        assert.equal(original,dictionary.showDict)
        assert.is_nil(next(plugin.popup_fallbacks))
        assert.equal(1,clears)
    end)

    it("uses an owned empty-result window instead of an untracked no-results prompt",function()
        local plugin,state,dictionary=harness()
        local original=dictionary.showNoResultsDialog
        plugin:showModel(model("parent"))
        state.no_results=true;state.missing=true
        plugin:lookupFromPopup(plugin.viewer,"unknown",function() end)
        assert.is_nil(state.no_results_prompts)
        assert.equal("unknown",dictionary.dict_window.word)
        dictionary.dict_window:onClose()
        assert.equal(original,dictionary.showNoResultsDialog)
        dictionary:showNoResultsDialog()
        assert.equal(1,state.no_results_prompts)
    end)

    it("prevents a delayed no-results prompt after owner teardown",function()
        local plugin,state,dictionary=harness()
        local original=dictionary.showNoResultsDialog
        plugin:showModel(model("parent"))
        state.no_results=true;state.missing=true;state.async=true
        plugin:lookupFromPopup(plugin.viewer,"unknown",function() end)
        plugin:closeDatabase()
        state.pending[1]()
        assert.is_nil(state.no_results_prompts)
        assert.is_nil(dictionary.dict_window)
        assert.equal(original,dictionary.showNoResultsDialog)
        assert.is_nil(next(plugin.popup_fallbacks))
    end)

    it("retires foreign-retained fallback wrappers without reactivating old hooks",function()
        local plugin,state,dictionary=harness()
        plugin:showModel(model("parent"))
        state.missing=true
        plugin:lookupFromPopup(plugin.viewer,"first",function() end)
        local retired=dictionary.showDict
        local outer=function(dict,...) return retired(dict,...) end
        dictionary.showDict=outer
        dictionary.dict_window:onClose()
        assert.equal(outer,dictionary.showDict)
        plugin:lookupFromPopup(plugin.viewer,"second",function() end)
        dictionary.dict_window:onClose()
        assert.equal(outer,dictionary.showDict)
        local callback=function() end
        retired(dictionary,"foreign",{},nil,nil,callback)
        assert.equal("foreign",dictionary.dict_window.word)
        assert.equal(callback,dictionary.dict_window.dict_close_callback)
    end)
    it("keeps a long-word miss opened in a popup out of Recent but records a hit",function()
        local plugin=harness()
        plugin:showModel(model("parent"),{highlight={}})
        local found=plugin.getModel
        function plugin:getModel(word,options)
            local value=found(self,word,options)
            if word=="long" then value.found,value.long_miss,value.senses=false,true,{} end
            return value
        end
        assert.is_true(plugin:lookupFromPopup(plugin.viewer,"long",function() end))
        assert.equal("long",plugin.viewer.model.query)
        assert.is_nil(plugin.settings.history)
        assert.is_true(plugin:lookupFromPopup(plugin.viewer,"child",function() end))
        assert.equal("child",plugin.settings.history[1].query)
        assert.equal(1,#plugin.settings.history)
    end)
end)
