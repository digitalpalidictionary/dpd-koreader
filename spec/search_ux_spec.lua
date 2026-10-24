
local function miss(query, english)
    return {query=query,found=false,matched_via=english and "english" or nil,
        senses={},grammar={},deconstructions={},roots={},suggestions={},
        english=english and {query=query,total=0,items={}} or nil}
end

describe("manual search recovery and history controls", function()
    local plugin, state, saved
    local names = {"datastorage","dpd/db","ui/widget/infomessage","ui/widget/pathchooser","ui/uimanager",
        "ui/dpd_viewer","ui/widget/container/widgetcontainer","libs/libkoreader-lfs","logger","ui/time",
        "util","device","ui/dpd_input","ui/widget/confirmbox","ui/widget/buttondialog","ui/widget/textviewer","ui/event","main"}
    before_each(function()
        saved, state = {}, {messages={},logs={},saves=0}
        for _, name in ipairs(names) do saved[name]=package.loaded[name]; package.loaded[name]={} end
        package.loaded["ui/widget/container/widgetcontainer"]={extend=function(_, value) return value end}
        package.loaded["dpd/db"]={read_only_message="read-only folder: "}
        package.loaded["ui/widget/confirmbox"]={new=function(_, value)
            value.cancel_callback=value.cancel_callback or function() end
            return value
        end}
        package.loaded["ui/widget/buttondialog"]={new=function(_, value) return value end}
        package.loaded["ui/widget/pathchooser"]={new=function(_, value) return value end}
        package.loaded["ui/widget/textviewer"]={new=function(_, value) return value end}
        package.loaded.device={home_dir="/tmp"}
        package.loaded["ui/uimanager"]={show=function(_, value) state.confirm=value end,
            close=function() state.closes=(state.closes or 0)+1 end}
        package.loaded.logger={warn=function(_, err) state.logs[#state.logs+1]=err end}
        package.loaded["ui/dpd_input"]={show=function(options) state.input=options; return options end}
        package.loaded.main=nil
        local DPD=require("main")
        plugin=setmetatable({settings={},ui={},lookup={english=function(_, query) return miss(query,true) end}}, {__index=DPD})
        function plugin:ensureLookup() return self.lookup end
        function plugin:getModel(query)
            if state.error then error(state.error, 0) end
            return miss(query)
        end
        function plugin:showModel(model, options) state.model,state.options=model,options; return true end
        function plugin:saveSettings() state.saves=state.saves+1 end
        function plugin:message(text) state.messages[#state.messages+1]=text end
    end)
    after_each(function() for _, name in ipairs(names) do package.loaded[name]=saved[name] end end)

    it("restores the original draft and mode after a manual Pāḷi miss", function()
        plugin:inputLookup()
        state.input.on_lookup("ñāṇax", "pali", "~naa.nax")
        assert.is_false(state.model.found)
        assert.is_nil(plugin.settings.history)
        state.options.edit_callback()
        assert.equal("~naa.nax",state.input.input)
        assert.equal("pali",plugin.settings.lookup_mode)
    end)

    it("keeps a successful ID's typed draft for tap and its lemma for hold", function()
        plugin.lookup.byId=function(_, id)
            assert.equal(34626,id)
            local value=miss("dhamma 1.01")
            value.found=true
            return value
        end
        plugin:lookupInput("34626","pali","  34626  ")
        assert.equal("34626",state.model.original_clean)
        local edit=state.options.edit_callback
        edit(nil,"pali")
        assert.equal("  34626  ",state.input.input)
        edit(state.model.query,"pali")
        assert.equal("dhamma 1.01",state.input.input)
        assert.equal("pali",plugin.settings.lookup_mode)
    end)

    it("reports a failed ID read once and doesn't retry it as a word", function()
        plugin.lookup.byId=function() error("database disk image is malformed", 0) end
        local looked_up=0
        function plugin:getModel(query) looked_up=looked_up+1; return miss(query) end
        plugin:lookupInput("34626","pali","34626")
        assert.equal(1,#state.messages)
        assert.equal(0,looked_up)
        assert.is_nil(state.model)
    end)

    it("shows a recoverable English miss without recording it", function()
        plugin:inputLookup()
        state.input.on_lookup("missing", "english", "  missing  ")
        assert.is_false(state.model.found)
        assert.is_table(state.model.english)
        assert.equal(0,#state.messages)
        assert.is_nil(plugin.settings.history)
        state.options.edit_callback()
        assert.equal("  missing  ",state.input.input)
        assert.equal("english",plugin.settings.lookup_mode)
        -- Damaged English data must not be presented as an ordinary no-match.
        state.model.english.error="Unreadable English data. Replace the database."
        local html=require("ui/dpd_render").render(state.model,{expanded={}},nil,true)
        assert.is_truthy(html:find("Unreadable English data",1,true))
        assert.is_falsy(html:find("No English→Pāḷi entries",1,true))
    end)

    it("keeps a did-you-mean miss out of Recent but records a real hit", function()
        function plugin:getModel(query)
            local value=miss(query)
            value.found,value.spelling_suggestions=true,{{text="kamma"}}
            return value
        end
        plugin:lookupInput("kamna","pali","kamna")
        assert.is_true(state.model.found)
        assert.is_nil(plugin.settings.history)
        function plugin:getModel(query)
            local value=miss(query)
            value.found,value.senses=true,{{id=1}}
            return value
        end
        plugin:lookupInput("kamma","pali","kamma")
        assert.equal("kamma",plugin.settings.history[1].query)
    end)

    it("forgets the input dialog once it closes, but not a newer one", function()
        plugin:inputLookup()
        local first=plugin.input_dialog
        first.on_reopen("second")
        first.on_close(first)
        assert.equal("second",plugin.input_dialog)
        first.on_close("second")
        assert.is_nil(plugin.input_dialog)
    end)

    it("requires confirmation before turning off and clearing nonempty history", function()
        plugin:getHistory():add("dhamma")
        plugin:toggleHistory()
        assert.is_true(plugin:getHistory():enabled())
        assert.equal(1,#plugin:getHistory():list())
        assert.equal(0,state.saves)
        state.confirm.cancel_callback()
        assert.equal(1,#plugin:getHistory():list())
        state.confirm.ok_callback()
        assert.is_false(plugin:getHistory():enabled())
        assert.equal(0,#plugin:getHistory():list())
        assert.equal(1,state.saves)
        state.confirm=nil
        plugin:toggleHistory()
        assert.is_true(plugin:getHistory():enabled())
        assert.is_nil(state.confirm)
    end)

    it("cancels or confirms Clear without changing recording", function()
        plugin:getHistory():add("dhamma")
        plugin:clearHistory()
        state.confirm.cancel_callback()
        assert.equal(1,#plugin:getHistory():list())
        assert.equal(0,state.saves)
        state.confirm.ok_callback()
        assert.equal(0,#plugin:getHistory():list())
        assert.is_true(plugin:getHistory():enabled())
        assert.equal(1,state.saves)
    end)

    it("keeps technical lookup errors in logs and gives readable recovery guidance", function()
        state.error="private/runtime/path: SQLite diagnostic"
        assert.is_false(plugin:showLookup("word"))
        assert.is_truthy(state.messages[1]:find("Check Database status",1,true))
        assert.is_falsy(state.messages[1]:find(state.error,1,true))
        assert.is_truthy(state.logs[#state.logs]:find(state.error,1,true))
    end)

    it("names a read-only folder in the recovery dialog, which the reader can fix", function()
        function plugin:ensureLookup() error("read-only folder: /books/dpd-mobile.db", 0) end
        plugin:inputLookup(false,"dhamma","pali")
        assert.equal("read-only folder: /books/dpd-mobile.db",state.confirm.title)
    end)

    it("offers recovery before typing and resumes the original draft after a valid selection", function()
        local broken=true
        function plugin:ensureLookup() if broken then error("SQLite detail") end; return self.lookup end
        plugin:getHistory():add("saved")
        plugin:inputLookup(false,"  ~naa.na  ","english")
        assert.is_nil(state.input)
        local recovery=state.confirm
        assert.equal("DPD database unavailable",recovery.title)
        assert.is_falsy(recovery.title:find("SQLite",1,true))
        recovery.buttons[3][1].callback()
        recovery.buttons[1][1].callback() -- stale button after Cancel does nothing
        assert.equal(recovery,state.confirm)
        assert.equal(1,#plugin:getHistory():list())
        plugin:inputLookup(false,"  ~naa.na  ","english")
        state.confirm.buttons[1][1].callback()
        local chooser=state.confirm
        assert.is_function(chooser.onConfirm)
        package.loaded["dpd/db"].new=function() error("invalid DB") end
        local dismiss
        function plugin:message(text, callback) state.messages[#state.messages+1]=text; dismiss=callback end
        chooser.onConfirm("/tmp/invalid.db")
        assert.is_nil(plugin.settings.db_path)
        assert.is_nil(state.input)
        -- Dismissing the error offers recovery again, still holding the draft.
        assert.is_function(dismiss)
        dismiss()
        assert.are_not.equal(chooser,state.confirm)
        assert.equal("DPD database unavailable",state.confirm.title)
        state.confirm.buttons[1][1].callback()
        chooser=state.confirm
        assert.is_function(chooser.onConfirm)
        local closed=0
        package.loaded["dpd/db"].new=function() return {close=function() closed=closed+1 end} end
        function plugin:closeDatabase() broken=false end
        chooser.onConfirm("/tmp/valid.db")
        assert.equal(1,closed)
        assert.equal("/tmp/valid.db",plugin.settings.db_path)
        assert.equal("  ~naa.na  ",state.input.input)
        assert.equal("english",plugin.settings.lookup_mode)
        assert.equal(1,#plugin:getHistory():list())
    end)

    it("reopens the database for suggestions after Suspend closed it", function()
        plugin.settings.db_path="/tmp/valid.db"
        local opens=0
        function plugin:ensureLookup() opens=opens+1; self.db={}; return self.lookup end
        package.loaded["dpd/suggest"]={new=function() return {complete=function() return {{text="dhamma"}} end} end}
        local items,status=plugin:suggest("dham","pali")
        package.loaded["dpd/suggest"]=nil
        assert.equal(1,opens)
        assert.equal("ready",status)
        assert.equal("dhamma",items[1].text)
        plugin.db=nil
        function plugin:ensureLookup() error("unavailable") end
        assert.equal("unavailable",select(2,plugin:suggest("dham","pali")))
        plugin.settings.db_path=nil
        assert.equal("unavailable",select(2,plugin:suggest("dham","pali")))
    end)

    it("cancels the open dialog's suggestions on every Suspend until it closes", function()
        plugin:inputLookup()
        local dialog,cancels=plugin.input_dialog,0
        dialog.cancel=function() cancels=cancels+1 end
        plugin:onSuspend()
        assert.equal(dialog,plugin.input_dialog)
        -- Typing after resume schedules new suggestions; the next Suspend cancels them too.
        plugin:onSuspend()
        assert.equal(2,cancels)
        dialog.on_close(dialog)
        plugin:onSuspend()
        assert.equal(2,cancels)
    end)

    it("keeps Recent accessible and retries the chosen lookup after recovery", function()
        package.loaded["ui/dpd_input"].showRecent=function(options) state.recent=options end
        function plugin:ensureLookup() error("unavailable") end
        plugin:getHistory():add("saved")
        plugin:inputLookup(true)
        assert.is_table(state.recent)
        assert.is_nil(state.confirm)
        state.recent.on_lookup("saved","pali")
        state.confirm.buttons[1][1].callback()
        local chooser=state.confirm
        package.loaded["dpd/db"].new=function() return {close=function() end} end
        function plugin:closeDatabase() self.ensureLookup=function() return self.lookup end end
        chooser.onConfirm("/tmp/valid.db")
        assert.equal("saved",state.model.query)
        assert.is_nil(state.input)
    end)

    it("returns to recovery after Database status and resumes once the database opens", function()
        local broken=true
        function plugin:ensureLookup() if broken then error("unavailable") end; return self.lookup end
        package.loaded["ui/uimanager"].nextTick=function(_, action) action() end
        package.loaded["libs/libkoreader-lfs"].attributes=function() return 0 end
        function plugin:message(text, dismiss) state.messages[#state.messages+1]=text; state.dismiss=dismiss end
        plugin:inputLookup(false,"~naa.na","english")
        local recovery=state.confirm
        recovery.buttons[2][1].callback()
        assert.is_truthy(state.messages[#state.messages]:find("could not open the database",1,true))
        state.dismiss()
        assert.is_nil(state.input)
        assert.equal("DPD database unavailable",state.confirm.title)
        assert.are_not.equal(recovery,state.confirm)
        broken=false
        plugin.settings.db_path="/tmp/valid.db"
        plugin.db={info={},journal_mode="delete"}
        state.confirm.buttons[2][1].callback()
        assert.is_truthy(state.messages[#state.messages]:find("Core columns: OK",1,true))
        state.dismiss()
        assert.equal("~naa.na",state.input.input)
        assert.equal("english",plugin.settings.lookup_mode)
    end)

    it("returns to recovery with the draft when the chooser closes without a file", function()
        package.loaded["ui/uimanager"].nextTick=function(_, action) action() end
        function plugin:ensureLookup() error("unavailable") end
        plugin:inputLookup(false,"  meditation  ","english")
        local recovery=state.confirm
        recovery.buttons[1][1].callback()
        local chooser=state.confirm
        chooser:onCloseWidget()
        assert.are_not.equal(chooser,state.confirm)
        assert.equal(recovery.title,state.confirm.title)
        function plugin:ensureLookup() return self.lookup end
        package.loaded["dpd/db"].new=function() return {close=function() end} end
        function plugin:closeDatabase() end
        state.confirm.buttons[1][1].callback()
        state.confirm.onConfirm("/tmp/valid.db")
        assert.equal("  meditation  ",state.input.input)
        assert.equal("english",state.input.mode)
    end)

    it("does not reopen recovery after a chosen file or a stop", function()
        package.loaded["ui/uimanager"].nextTick=function(_, action) action() end
        function plugin:ensureLookup() error("unavailable") end
        plugin:inputLookup(false,"dhamma","pali")
        state.confirm.buttons[1][1].callback()
        local chooser=state.confirm
        package.loaded["dpd/db"].new=function() return {close=function() end} end
        function plugin:closeDatabase() self.ensureLookup=function() return self.lookup end end
        chooser.onConfirm("/tmp/valid.db")
        local after=state.confirm
        chooser:onCloseWidget()
        assert.equal(after,state.confirm)
        function plugin:ensureLookup() error("unavailable") end
        plugin:inputLookup(false,"dhamma","pali")
        state.confirm.buttons[1][1].callback()
        chooser=state.confirm
        plugin.stopped=true
        chooser:onCloseWidget()
        assert.equal(chooser,state.confirm)
    end)

    it("says DPD is disabled from a Database status item left open at stop", function()
        function plugin:ensureLookup() error("must not reopen the database") end
        plugin.stopped=true
        plugin:databaseStatus()
        assert.equal("Digital Pāḷi Dictionary is disabled until KOReader restarts.",state.messages[#state.messages])
        assert.equal(0,#state.logs)
    end)

    it("keeps an edited popup until its search is submitted", function()
        local closes=0
        local edited={close=function(self) self.closed=true; closes=closes+1 end}
        plugin:inputLookup(false,"dhammaṃ","pali",nil,edited)
        assert.equal(0,closes)
        state.input.on_lookup("dhammo","pali","dhammo")
        assert.equal(1,closes)
        assert.equal("dhammo",state.model.query)
        assert.is_nil(state.options.parent)
        plugin:inputLookup(false,"dhammaṃ","pali",nil,edited)
        state.input.on_lookup("dhammo","pali","dhammo")
        assert.equal(1,closes)
    end)

    it("invalidates recovery actions on Back and keeps stopped plugins out of recovery", function()
        function plugin:ensureLookup() error("unavailable") end
        plugin:inputLookup()
        local recovery=state.confirm
        recovery:onCloseWidget()
        recovery.buttons[1][1].callback()
        assert.equal(recovery,state.confirm)
        plugin.stopped=true
        plugin:inputLookup()
        assert.is_truthy(state.messages[#state.messages]:find("disabled",1,true))
        assert.equal(recovery,state.confirm)
    end)

    it("says DPD is disabled, not a database error, from entry points left open at stop", function()
        function plugin:ensureLookup() error("must not reopen the database") end
        plugin.stopped=true
        assert.is_false(plugin:showLookup("dhamma"))
        assert.is_false(plugin:showId("34626"))
        assert.is_false(plugin:showEnglish("good"))
        assert.equal(3,#state.messages)
        for _,text in ipairs(state.messages) do assert.is_truthy(text:find("disabled until KOReader restarts",1,true)) end
        assert.equal(0,#state.logs)
    end)

    it("opens concise help from the menu without database access", function()
        local items={};plugin:addToMainMenu(items)
        local help
        for _,item in ipairs(items.dpd.sub_item_table) do
            if item.text=="Help" then help=item end
        end
        for _,item in ipairs(help.sub_item_table) do
            if item.text=="DPD help" then item.callback() end
        end
        assert.equal("DPD help",state.confirm.title)
        for _,text in ipairs({"▸","Back","English","≈","ID number","Recent","KOReader dictionary","Joined forms"}) do
            assert.is_truthy(state.confirm.text:find(text,1,true))
        end
    end)

    it("says that diagnostics record looked-up words when enabled", function()
        local items={};plugin:addToMainMenu(items)
        local help
        for _,item in ipairs(items.dpd.sub_item_table) do
            if item.text=="Help" then help=item end
        end
        for _,item in ipairs(help.sub_item_table) do
            if item.text=="Diagnostics" then
                local Diag=require("dpd/diag")
                local enabled,setEnabled,diag_path=Diag.enabled,Diag.setEnabled,Diag.path
                Diag.setEnabled=function(on) Diag.enabled=on end
                Diag.path=function() return "/tmp/dpd.log" end
                Diag.enabled=false
                item.sub_item_table[1].callback()
                Diag.enabled,Diag.setEnabled,Diag.path=enabled,setEnabled,diag_path
            end
        end
        assert.is_truthy(state.messages[#state.messages]:find("words you look up",1,true))
    end)

    it("names the database's own reason in recovery, status and the chooser", function()
        package.loaded["ui/uimanager"].nextTick=function(_, action) action() end
        local reason="This file is not a SQLite database. Choose the extracted dpd-mobile.db file. If it is damaged, download and extract a fresh copy."
        function plugin:ensureLookup() error("/plugins/dpd.koplugin/dpd/db.lua:29: "..reason, 0) end
        plugin:inputLookup(false,"dhamma","pali")
        assert.equal(reason,state.confirm.title)
        plugin:databaseStatus()
        assert.equal(1,state.messages[#state.messages]:find(reason,1,true))
        function plugin:ensureLookup() error("dpd/db.lua:24: Choose the DPD database in the DPD menu.", 0) end
        plugin:inputLookup(false,"dhamma","pali")
        assert.is_truthy(state.confirm.title:find("koreader/data/dpd/",1,true))
        state.confirm.buttons[1][1].callback()
        package.loaded["dpd/db"].new=function() error("read-only folder: /books/dpd-mobile.db", 0) end
        state.confirm.onConfirm("/books/dpd-mobile.db")
        assert.equal(1,state.messages[#state.messages]:find("read-only folder: /books/dpd-mobile.db",1,true))
        assert.is_nil(plugin.settings.db_path)
        -- A missing column names the fix, not the column or a bug report.
        package.loaded["dpd/db"].new=function() error("dpd/db.lua:43: Incompatible DPD database: missing dpd_headwords.id", 0) end
        state.confirm.onConfirm("/books/other.db")
        local text=state.messages[#state.messages]
        assert.is_truthy(text:find("Choose dpd-mobile.db from a current DPD release",1,true))
        assert.is_nil(text:find("dpd_headwords",1,true))
        assert.is_nil(text:find("bug report",1,true))
        assert.is_nil(plugin.settings.db_path)
    end)

    it("warns once when long-press falls back after damaged data", function()
        package.loaded["ui/uimanager"].nextTick=function(_, action) action() end
        local fallback=0
        plugin.ui.dictionary={onLookupWord=function() fallback=fallback+1; return true end}
        plugin.settings.direct_lookup,plugin.settings.db_path=true,"/books/dpd-mobile.db"
        function plugin:bookDirect() return nil end
        plugin:syncDirectMode()
        for _, err in ipairs({"dpd/lookup.lua:14: Invalid DPD JSON in headwords",
            "dpd/lookup.lua:294: Missing DPD headword for ID 999999",
            "common/lua-ljsqlite3/init.lua:60: ljsqlite3[notadb] file is not a database"}) do
            state.error=err
            assert.is_true(plugin.ui.dictionary:onLookupWord("dhamma",true,nil,{}))
        end
        assert.equal(3,fallback)
        assert.equal(1,#state.messages)
        assert.is_truthy(state.messages[1]:find("fresh DPD mobile download",1,true))
        -- Only the words DPD can't read fall back; the rest still open DPD.
        assert.is_truthy(state.messages[1]:find("normal dictionary for words DPD can't read",1,true))
        assert.is_nil(state.messages[1]:find("Until then",1,true))
        -- A later missing database is its own problem, and says where to fix it.
        state.error="dpd/db.lua:26: DPD database not found or unreadable: /books/dpd-mobile.db"
        assert.is_true(plugin.ui.dictionary:onLookupWord("dhamma",true,nil,{}))
        assert.equal(2,#state.messages)
        assert.equal(1,state.messages[2]:find("DPD database not found or unreadable: /books/dpd-mobile.db",1,true))
        assert.is_truthy(state.messages[2]:find("Choose it under Search → Digital Pāḷi Dictionary → Choose database file.\n\nUntil then, long-press opens your normal dictionary.",1,true))
        plugin.direct:remove()
    end)

    it("gives an incompatible database one instruction naming the file and the menu", function()
        package.loaded["ui/uimanager"].nextTick=function(_, action) action() end
        plugin.ui.dictionary={onLookupWord=function() return true end}
        plugin.settings.direct_lookup,plugin.settings.db_path=true,"/books/other.db"
        function plugin:bookDirect() return nil end
        plugin:syncDirectMode()
        state.error="dpd/db.lua:43: Incompatible DPD database: missing dpd_headwords.id"
        assert.is_true(plugin.ui.dictionary:onLookupWord("dhamma",true,nil,{}))
        assert.equal("This file isn't a DPD database this version can read. Choose dpd-mobile.db from a current DPD release "
            .. "under Search → Digital Pāḷi Dictionary → Choose database file.\n\nUntil then, long-press opens your normal dictionary.",
            state.messages[1])
        plugin.direct:remove()
    end)

    it("warns once when damaged grammar leaves long-press with no usable entry", function()
        package.loaded["ui/uimanager"].nextTick=function(_, action) action() end
        local db={senses=function() return {} end,fuzzy=function() return {} end}
        function db:lookup(key)
            if key=="badgrammar" then
                return {lookup_key=key,headwords="",grammar='[["buddha","noun"]]'}
            end
        end
        local lookup=require("dpd/lookup").new(db)
        function plugin:getModel(word, options) return lookup:get(word,options) end
        local fallback=0
        plugin.ui.dictionary={onLookupWord=function() fallback=fallback+1; return true end}
        plugin.settings.direct_lookup,plugin.settings.db_path=true,"/books/dpd-mobile.db"
        plugin:syncDirectMode()
        assert.is_true(plugin.ui.dictionary:onLookupWord("ordinarymiss",true,nil,{}))
        assert.equal(0,#state.messages)
        for _=1,2 do assert.is_true(plugin.ui.dictionary:onLookupWord("badgrammar",true,nil,{})) end
        assert.equal(3,fallback)
        assert.equal(1,#state.messages)
        assert.is_truthy(state.messages[1]:find("could not look up this word",1,true))
        assert.is_truthy(state.messages[1]:find("normal dictionary for words DPD can't read",1,true))
        assert.is_nil(state.model)
        plugin.direct:remove()
    end)

    it("hands the popup's normal dictionary action through a later plugin once", function()
        local normal, later, intercepted = 0,0,0
        plugin.ui.dictionary={onLookupWord=function(_, word)
            assert.equal("dhamma",word)
            normal=normal+1
            return "normal",nil,"third"
        end}
        plugin.direct=require("dpd/direct").install(plugin.ui.dictionary,function()
            intercepted=intercepted+1
            return true
        end)
        local delegate=plugin.ui.dictionary.onLookupWord
        plugin.ui.dictionary.onLookupWord=function(dict,...)
            later=later+1
            return delegate(dict,...)
        end
        local first,second,third=plugin:normalLookup("dhamma",true)
        assert.equal("normal",first);assert.is_nil(second);assert.equal("third",third)
        assert.equal(1,normal);assert.equal(1,later);assert.equal(0,intercepted)
        plugin.direct:remove()
    end)

    it("says once per session why long-press used the normal dictionary", function()
        package.loaded["ui/uimanager"].nextTick=function(_, action) action() end
        plugin.settings.direct_lookup=true
        assert.is_false(plugin:tryDirect("dhamma",true,nil,{}))
        assert.is_false(plugin:tryDirect("dhamma",true,nil,{}))
        assert.equal(1,#state.messages)
        assert.is_truthy(state.messages[1]:find("No DPD database found",1,true))
        assert.is_truthy(state.messages[1]:find("long-press opens your normal dictionary",1,true))
        -- Its own text already names the fix; it isn't repeated.
        local _, mentions = state.messages[1]:gsub("Choose database file", "")
        assert.equal(1,mentions)
        plugin.settings.direct_lookup=false
        assert.is_false(plugin:tryDirect("dhamma",true,nil,{}))
        assert.equal(1,#state.messages)
    end)

    describe("searching the other dictionaries", function()
        local function result(text, found)
            return {query=text,original=text,found=found,dictionary_search=true,matched_via="dictionaries",
                dictionaries={keys={text},groups=found and {{id="mw"}} or {}}}
        end
        before_each(function()
            plugin.lookup.hasOtherDictionaries=function() return true end
            plugin.lookup.searchDictionaries=function(_, text, enabled)
                state.enabled=enabled
                return result(text, text~="zzzz")
            end
        end)
        it("reports metadata damage instead of claiming the database is an older release", function()
            plugin.lookup.hasOtherDictionaries=function() return nil,"DPD could not read the other dictionaries." end
            plugin:inputLookup(false,nil,"dictionaries")
            assert.is_nil(state.input)
            assert.matches("could not read",state.messages[1],1,true)
            assert.is_falsy(state.messages[1]:find("v0.4.",1,true))
        end)

        it("opens from the menu without changing the remembered lookup mode", function()
            plugin.settings.lookup_mode="english"
            local items={};plugin:addToMainMenu(items)
            local names={}
            for _,item in ipairs(items.dpd.sub_item_table) do names[#names+1]=item.text end
            assert.equal("Look up a word",names[1])
            assert.equal("Search other dictionaries",names[2])
            items.dpd.sub_item_table[2].callback()
            assert.equal("dictionaries",state.input.mode)
            assert.equal("english",plugin.settings.lookup_mode)
        end)

        it("shows a miss and an empty selection instead of closing on nothing", function()
            for _, enabled in ipairs({{"mw"},{}}) do
                state.model=nil
                plugin.settings.dictionaries=enabled
                assert.is_true(plugin:lookupInput("zzzz","dictionaries","zzzz"))
                assert.is_false(state.model.found)
                assert.is_true(state.model.dictionary_search)
                assert.same(enabled,state.enabled)
            end
            assert.equal(0,#plugin:getHistory():list())
        end)

        it("records a found search in this mode and edits it in this mode", function()
            plugin.settings.lookup_mode="pali"
            plugin:lookupInput("dharma","dictionaries","dharma")
            assert.same({query="dharma",mode="dictionaries"},plugin:getHistory():list()[1])
            state.options.edit_callback(nil,"dictionaries")
            assert.equal("dharma",state.input.input)
            assert.equal("dictionaries",state.input.mode)
            assert.equal("pali",plugin.settings.lookup_mode)
        end)

        it("says when the database has no other dictionaries, without a dialog or popup", function()
            plugin.lookup.hasOtherDictionaries=function() return false end
            plugin:inputLookup(false,nil,"dictionaries")
            plugin:lookupInput("dharma","dictionaries","dharma")
            assert.is_nil(state.input)
            assert.is_nil(state.model)
            assert.equal(2,#state.messages)
            assert.is_truthy(state.messages[1]:find("no other dictionaries",1,true))
        end)

        it("gives readable guidance when the search fails", function()
            plugin.lookup.searchDictionaries=function() error("SQLite detail") end
            assert.is_false(plugin:lookupInput("dharma","dictionaries","dharma"))
            local text=state.messages[#state.messages]
            assert.is_truthy(text:find("could not search the other dictionaries",1,true))
            assert.is_falsy(text:find("SQLite",1,true))
        end)

        it("offers recovery and resumes the draft in this mode", function()
            local broken=true
            function plugin:ensureLookup() if broken then error("unavailable") end; return self.lookup end
            plugin:inputLookup(false,"dharma","dictionaries")
            assert.is_nil(state.input)
            state.confirm.buttons[1][1].callback()
            package.loaded["dpd/db"].new=function() return {close=function() end} end
            function plugin:closeDatabase() broken=false end
            state.confirm.onConfirm("/tmp/valid.db")
            assert.equal("dharma",state.input.input)
            assert.equal("dictionaries",state.input.mode)
            assert.is_nil(plugin.settings.lookup_mode)
        end)
    end)

    describe("direct lookup in a book", function()
        local book
        before_each(function()
            book={values={}}
            function book:readSetting(key) return self.values[key] end
            function book:saveSetting(key, value) self.values[key]=value end
            function book:delSetting(key) self.values[key]=nil end
            state.events, state.lookups={}, 0
            package.loaded["ui/event"]={new=function(_, name, ...) return {name=name,args={...}} end}
            plugin.settings.db_path="/books/dpd-mobile.db"
            plugin.settings.direct_lookup=true
            plugin.ui={doc_settings=book,doc_props={display_title="Dīgha Nikāya"},
                handleEvent=function(_, event) state.events[#state.events+1]={event=event,popup=state.model} end}
            function plugin:syncDirectMode() state.synced=(state.synced or 0)+1 end
            function plugin:getModel(query)
                state.lookups=state.lookups+1
                local value=miss(query)
                value.found=query~="xyzzy"
                return value
            end
        end)

        it("lets a book override DPD on word long-press", function()
            assert.is_true(plugin:tryDirect("dhamma",true,nil,{}))
            plugin:toggleBookDirect()
            assert.is_false(book.values.dpd_direct_lookup)
            assert.is_false(plugin:tryDirect("dhamma",true,nil,{}))
            -- The book's choice outlasts a change to the global setting.
            plugin.settings.direct_lookup=false
            assert.is_false(plugin:tryDirect("dhamma",true,nil,{}))
            plugin.settings.direct_lookup=true
            -- Choosing the global value again removes the exception.
            plugin:toggleBookDirect()
            assert.is_nil(book.values.dpd_direct_lookup)
            assert.is_true(plugin:tryDirect("dhamma",true,nil,{}))
            plugin.settings.direct_lookup=false
            assert.is_false(plugin:tryDirect("dhamma",true,nil,{}))
            plugin:toggleBookDirect()
            assert.is_true(book.values.dpd_direct_lookup)
            assert.is_true(plugin:tryDirect("dhamma",true,nil,{}))
            assert.equal(3,state.synced)
        end)

        it("follows the global setting outside a book", function()
            plugin.ui.doc_settings=nil
            assert.is_true(plugin:directEnabled())
            plugin.settings.direct_lookup=false
            assert.is_false(plugin:directEnabled())
        end)

        it("announces a DPD hit once, before its popup, for the Vocabulary builder", function()
            assert.is_true(plugin:tryDirect("dhammaṃ",true,nil,{}))
            assert.equal(1,#state.events)
            local announced=state.events[1]
            assert.equal("WordLookedUp",announced.event.name)
            assert.same({"dhammaṃ","Dīgha Nikāya"},announced.event.args)
            assert.is_nil(announced.popup)
            -- A miss goes to KOReader's dictionary, which announces it itself.
            assert.is_false(plugin:tryDirect("xyzzy",true,nil,{}))
            assert.equal(1,#state.events)
        end)

        it("keeps the DPD popup when a lookup listener fails", function()
            plugin.ui.handleEvent=function() error("listener failed") end
            assert.is_true(plugin:tryDirect("dhamma",true,nil,{}))
            assert.equal("dhamma",state.model.query)
        end)

        it("announces the word as KOReader's dictionary cleans it", function()
            plugin.ui.dictionary={cleanSelection=function(_, text, is_sane)
                state.sane=is_sane
                return (text:gsub("[%p]+$",""))
            end}
            assert.is_true(plugin:tryDirect("pacchima,",false,nil,{}))
            assert.same({"pacchima","Dīgha Nikāya"},state.events[1].event.args)
            assert.is_false(state.sane)
        end)

        it("doesn't announce a word the Vocabulary builder already has, nor hand it over announced", function()
            function plugin:vocabularyHas(word) return word=="pacchima" end
            local looked_up={}
            plugin.ui.vocabbuilder=setmetatable({},{__index={onWordLookedUp=function(_, word) looked_up[#looked_up+1]=word end}})
            plugin.ui.dictionary={onLookupWord=function(_, word) plugin.ui.vocabbuilder:onWordLookedUp(word) end}
            assert.is_true(plugin:tryDirect("pacchima",true,nil,{}))
            assert.equal(0,#state.events)
            state.options.normal_callback("pacchima")
            assert.same({},looked_up)
            assert.is_true(plugin:tryDirect("dhamma",true,nil,{}))
            assert.equal(1,#state.events)
        end)

        it("reads a word as not saved when the Vocabulary builder can't be checked", function()
            assert.is_false(plugin:vocabularyHas("pacchima"))
            plugin.ui.vocabbuilder={}
            assert.is_false(plugin:vocabularyHas("pacchima"))
        end)

            it("closes the Vocabulary builder's database when its query fails", function()
            local closed,saved_settings=0,_G.G_reader_settings
            _G.G_reader_settings={readSetting=function() return {enabled=true} end}
            package.loaded.datastorage.getSettingsDir=function() return "/settings" end
            package.loaded["libs/libkoreader-lfs"].attributes=function() return "file" end
            local saved_sqlite=package.loaded["lua-ljsqlite3/init"]
            package.loaded["lua-ljsqlite3/init"]={open=function() return {
                prepare=function() error("no such table: vocabulary") end,
                close=function() closed=closed+1 end} end}
            plugin.ui.vocabbuilder={}
            local ok,saved=pcall(plugin.vocabularyHas,plugin,"pacchima")
            package.loaded["lua-ljsqlite3/init"],_G.G_reader_settings=saved_sqlite,saved_settings
            assert.is_true(ok)
            assert.is_false(saved)
            assert.equal(1,closed)
        end)

    it("hands over to KOReader's dictionary without announcing the word again", function()
            local heard={}
            -- A method of the plugin's class, as in KOReader.
            local vocabulary=setmetatable({},{__index={onWordLookedUp=function(_, word) heard[#heard+1]=word end}})
            plugin.ui.vocabbuilder=vocabulary
            plugin.ui.dictionary={cleanSelection=function(_, text, is_sane)
                return is_sane and text or (text:gsub("[%p]+$",""))
            end, onLookupWord=function(dictionary, word, is_sane)
                state.handoff={word,is_sane}
                -- KOReader announces as it looks up, and the reader may then look up another word.
                vocabulary:onWordLookedUp(dictionary:cleanSelection(word, is_sane))
                vocabulary:onWordLookedUp("kamma")
            end}
            assert.is_true(plugin:tryDirect("pacchima,",false,nil,{}))
            state.options.normal_callback("pacchima,")
            -- Cleaned there as it would have been, not saved as "pacchima,".
            assert.same({"pacchima,",false},state.handoff)
            assert.same({"kamma"},heard)
            assert.is_nil(rawget(vocabulary,"onWordLookedUp"))
            vocabulary:onWordLookedUp("pacchima")
            assert.same({"kamma","pacchima"},heard)
        end)

        it("opens reviews by the global setting, whatever the open book says", function()
            plugin.ui.vocabbuilder={widget={current_lookup_word="dhamma"}}
            book.values.dpd_direct_lookup=false
            assert.is_true(plugin:tryDirect("dhamma",true))
            -- The book's own selections still use KOReader's dictionary.
            assert.is_false(plugin:tryDirect("dhamma",true,nil,{}))
            plugin.settings.direct_lookup=false
            book.values.dpd_direct_lookup=true
            assert.is_false(plugin:tryDirect("dhamma",true))
            assert.is_true(plugin:tryDirect("dhamma",true,nil,{}))
        end)

        it("opens Vocabulary builder reviews in DPD without announcing or recording them", function()
            plugin.ui.vocabbuilder={widget={current_lookup_word="dhamma"}}
            assert.is_true(plugin:tryDirect("dhamma",true))
            assert.equal(0,#state.events)
            assert.is_nil(plugin.settings.history)
            -- Other lookups without a selection keep KOReader's dictionary.
            assert.is_false(plugin:tryDirect("kamma",true))
            plugin.ui.vocabbuilder=nil
            assert.is_false(plugin:tryDirect("dhamma",true))
            assert.equal(1,state.lookups)
        end)
    end)
end)
