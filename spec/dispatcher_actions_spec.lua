describe("Dispatcher actions", function()
    local saved, DPD, updater, state, plugin
    local names = { "datastorage", "dpd/db", "dpd/updater", "ui/widget/infomessage",
        "ui/widget/pathchooser", "ui/uimanager", "ui/widget/container/widgetcontainer",
        "libs/libkoreader-lfs", "logger", "ui/time", "util", "ui/widget/notification", "dispatcher", "main" }
    before_each(function()
        saved, state = {}, { actions = {}, order = {}, lookups = {}, notes = {}, messages = {}, restarts = 0 }
        for _, name in ipairs(names) do saved[name] = package.loaded[name]; package.loaded[name] = {} end
        package.loaded["ui/widget/container/widgetcontainer"] = { extend = function(_, value) return value end }
        package.loaded.dispatcher = { registerAction = function(_, name, value)
            state.actions[name] = value
            state.order[#state.order + 1] = name
        end }
        package.loaded["ui/widget/notification"] = { SOURCE_DISPATCHER = 0x20,
            notify = function(_, text, source) state.notes[#state.notes + 1] = { text, source } end }
        updater = {}
        package.loaded["dpd/updater"] = updater
        package.loaded.main = nil
        DPD = require("main")
        plugin = setmetatable({ settings = { direct_lookup = true }, ui = {} }, { __index = DPD })
        function plugin:inputLookup(...) state.lookups[#state.lookups + 1] = { n = select("#", ...), ... } end
        function plugin:askUpdateRestart() state.restarts = state.restarts + 1 end
        function plugin:message(text) state.messages[#state.messages + 1] = text end
        function plugin:syncDirectMode() state.synced = (state.synced or 0) + 1 end
    end)
    after_each(function()
        for _, name in ipairs(names) do package.loaded[name] = saved[name] end
    end)
    local function fire(name)
        local action = assert(state.actions[name], name)
        return plugin["on" .. action.event](plugin)
    end
    local function book(own)
        local values = { dpd_direct_lookup = own }
        plugin.ui.doc_settings = {
            readSetting = function(_, key) return values[key] end,
            saveSetting = function(_, key, value) values[key] = value end,
            delSetting = function(_, key) values[key] = nil end,
        }
        return values
    end

    it("registers the lookup actions everywhere and the long-press toggle in books only", function()
        plugin:onDispatcherRegisterActions()
        assert.same({ "dpd_look_up", "dpd_search_dictionaries", "dpd_recent", "dpd_toggle_book_long_press" },
            state.order)
        for _, name in ipairs(state.order) do
            local action = state.actions[name]
            assert.equal("none", action.category)
            assert.matches("^DPD: ", action.title)
            assert.is_function(plugin["on" .. action.event], name)
        end
        assert.is_true(state.actions.dpd_look_up.general)
        assert.is_true(state.actions.dpd_search_dictionaries.general)
        assert.is_true(state.actions.dpd_recent.general)
        assert.is_nil(state.actions.dpd_toggle_book_long_press.general)
        assert.is_true(state.actions.dpd_toggle_book_long_press.reader)
    end)

    it("opens the same screens as the menu items", function()
        plugin:onDispatcherRegisterActions()
        assert.is_true(fire("dpd_look_up"))
        assert.is_true(fire("dpd_search_dictionaries"))
        assert.is_true(fire("dpd_recent"))
        assert.same({ { n = 0 }, { n = 3, false, nil, "dictionaries" }, { n = 1, true } }, state.lookups)
    end)

    it("toggles this book's long-press choice and says which dictionary it opens", function()
        local values = book(nil)
        plugin:onDispatcherRegisterActions()
        assert.is_true(fire("dpd_toggle_book_long_press"))
        assert.is_false(values.dpd_direct_lookup)
        assert.same({ "Long-press opens your normal dictionary in this book.", 0x20 }, state.notes[1])
        fire("dpd_toggle_book_long_press")
        -- Back to the global setting: the book follows it again.
        assert.is_nil(values.dpd_direct_lookup)
        assert.same({ "Long-press opens DPD in this book.", 0x20 }, state.notes[2])
        assert.equal(2, state.synced)
    end)

    it("does nothing for the book toggle outside a book", function()
        plugin:onDispatcherRegisterActions()
        assert.is_true(fire("dpd_toggle_book_long_press"))
        assert.is_nil(state.synced)
        assert.same({}, state.notes)
    end)

    it("leaves a stopped plugin and its book settings alone", function()
        local values = book(nil)
        plugin:onDispatcherRegisterActions()
        plugin.stopped = true
        for _, name in ipairs(state.order) do assert.is_true(fire(name)) end
        assert.equal(4, #state.messages)
        assert.equal("Digital Pāḷi Dictionary is disabled until KOReader restarts.", state.messages[1])
        assert.same({}, state.lookups)
        assert.is_nil(values.dpd_direct_lookup)
        assert.is_nil(state.synced)
        assert.same({}, state.notes)
    end)

    it("shows the restart or the warning the menu would show instead", function()
        local values = book(nil)
        plugin:onDispatcherRegisterActions()
        updater.restart_pending = true
        for _, name in ipairs(state.order) do assert.is_true(fire(name)) end
        assert.equal(4, state.restarts)
        updater.restart_pending = nil
        plugin.unsupported = "Needs a newer KOReader."
        for _, name in ipairs(state.order) do fire(name) end
        assert.equal(4, #state.messages)
        assert.same({}, state.lookups)
        assert.is_nil(values.dpd_direct_lookup)
        assert.same({}, state.notes)
    end)
end)
