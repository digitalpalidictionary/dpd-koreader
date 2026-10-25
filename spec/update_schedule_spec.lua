describe("automatic update scheduling", function()
    local saved, previous_settings, previous_time, DPD, updater, tasks, state, plugin
    local names = { "datastorage", "dpd/db", "dpd/updater", "ui/widget/infomessage",
        "ui/widget/pathchooser", "ui/uimanager", "ui/widget/container/widgetcontainer",
        "libs/libkoreader-lfs", "logger", "ui/time", "util", "ui/network/manager",
        "ui/widget/notification", "main" }
    before_each(function()
        saved, tasks, state = {}, {}, { connected = true, launched = 0, notifications = 0, saves = 0,
            now = 1000000, uptime = 1000000 }
        previous_time = os.time
        os.time = function() return state.now end
        for _, name in ipairs(names) do saved[name] = package.loaded[name]; package.loaded[name] = {} end
        package.loaded["ui/widget/container/widgetcontainer"] = { extend = function(_, value) return value end }
        package.loaded["ui/uimanager"] = {
            scheduleIn = function(_, delay, callback) assert.equal(15, delay); tasks[callback] = true end,
            unschedule = function(_, callback) tasks[callback] = nil end,
        }
        package.loaded["ui/network/manager"] = { isConnected = function() return state.connected end }
        package.loaded["ui/time"] = { now = function() return state.uptime end, s = function(seconds) return seconds end }
        package.loaded["ui/widget/notification"] = { notify = function() state.notifications = state.notifications + 1 end }
        updater = { check_interval = 604800, retry_interval = 3600, isNewer = function() return true end,
            checkInBackground = function(callback)
                state.launched = state.launched + 1
                state.complete = callback
                return not state.launch_failed
            end }
        package.loaded["dpd/updater"] = updater
        previous_settings = _G.G_reader_settings
        _G.G_reader_settings = { saveSetting = function() state.saves = state.saves + 1 end }
        package.loaded.main = nil
        DPD = require("main")
        plugin = setmetatable({ settings = { update_auto = true }, ui = {} }, { __index = DPD })
    end)
    after_each(function()
        for _, name in ipairs(names) do package.loaded[name] = saved[name] end
        _G.G_reader_settings = previous_settings
        os.time = previous_time
    end)
    local function delayed()
        local callback = assert(next(tasks))
        tasks[callback] = nil
        callback()
    end
    local function toggle()
        for _, item in ipairs(plugin:helpMenu().sub_item_table) do
            if item.text == "Check for updates automatically" then item.callback(); return end
        end
        error("missing automatic update setting")
    end

    it("schedules immediately when enabled, and ignores repeated connection events", function()
        plugin.settings.update_auto = nil
        toggle()
        local pending = assert(updater.auto_pending)
        plugin:onNetworkConnected()
        plugin:onResume()
        assert.equal(pending, updater.auto_pending)
        assert.is_nil(updater.auto_checking)
        delayed()
        plugin:onNetworkConnected()
        assert.equal(1, state.launched)
        assert.is_nil(next(tasks))
    end)

    it("retries after losing the connection during the delay", function()
        plugin:scheduleUpdateCheck()
        state.connected = false
        delayed()
        assert.equal(0, state.launched)
        assert.is_nil(updater.auto_checking)
        state.connected = true
        plugin:onNetworkConnected()
        delayed()
        assert.equal(1, state.launched)
    end)

    it("cancels the timer on disconnect and rearms on reconnect", function()
        plugin:scheduleUpdateCheck()
        local stale = updater.auto_pending.callback
        plugin:onNetworkDisconnected()
        plugin:onNetworkConnected()
        stale()
        assert.equal(0, state.launched)
        delayed()
        assert.equal(1, state.launched)
    end)

    it("cancels a disabled timer and schedules again when enabled", function()
        plugin:scheduleUpdateCheck()
        local stale = updater.auto_pending.callback
        toggle()
        assert.is_nil(next(tasks))
        stale()
        assert.equal(0, state.launched)
        toggle()
        delayed()
        assert.equal(1, state.launched)
    end)

    it("does not announce or save an in-flight result after disabling", function()
        plugin:scheduleUpdateCheck()
        delayed()
        toggle()
        local saves = state.saves
        state.complete("99.0.0")
        assert.equal(saves, state.saves)
        assert.equal(0, state.notifications)
        assert.is_nil(plugin.settings.update_checked)
        toggle()
        delayed()
        assert.equal(2, state.launched)
    end)

    it("rearms on resume and hands the pending timer to the next book", function()
        function plugin:closeDatabase() end
        plugin:scheduleUpdateCheck()
        plugin:onSuspend()
        assert.is_nil(next(tasks))
        plugin:onResume()
        assert.is_not_nil(next(tasks))
        plugin:onCloseDocument()
        assert.is_nil(next(tasks))
        local next_book = setmetatable({ settings = plugin.settings }, { __index = DPD })
        next_book:scheduleUpdateCheck()
        plugin:onResume()
        delayed()
        assert.equal(1, state.launched)
    end)

    it("keeps the weekly interval and rechecks it when the timer fires", function()
        plugin.settings.update_checked = os.time()
        plugin:scheduleUpdateCheck()
        assert.is_nil(next(tasks))
        plugin.settings.update_checked = nil
        plugin:scheduleUpdateCheck()
        plugin.settings.update_checked = os.time()
        delayed()
        assert.equal(0, state.launched)
        assert.is_nil(updater.auto_checking)
    end)

    it("preserves another owner's timer except when the setting is disabled globally", function()
        local owner = setmetatable({ settings = plugin.settings }, { __index = DPD })
        owner:scheduleUpdateCheck()
        local pending = updater.auto_pending
        function plugin:closeDatabase() end
        plugin:onCloseDocument()
        assert.equal(pending, updater.auto_pending)
        toggle()
        assert.is_nil(updater.auto_pending)
        assert.is_nil(next(tasks))
        pending.callback()
        assert.equal(0, state.launched)
    end)

    it("allows another attempt when the child process cannot start", function()
        state.launch_failed = true
        plugin:scheduleUpdateCheck()
        delayed()
        assert.is_nil(updater.auto_checking)
        state.launch_failed = nil
        plugin:onNetworkConnected()
        delayed()
        assert.equal(2, state.launched)
        state.complete("99.0.0")
        assert.is_number(plugin.settings.update_checked)
        assert.equal(1, state.notifications)
    end)

    it("retries a failed started request after a cooldown across owners", function()
        plugin:scheduleUpdateCheck()
        delayed()
        assert.is_true(updater.auto_checking)
        state.complete(nil)
        assert.is_nil(updater.auto_checking)
        assert.is_nil(plugin.settings.update_checked)
        assert.equal(0, state.saves)
        plugin:onNetworkConnected()
        plugin:onResume()
        assert.is_nil(next(tasks))
        state.now = state.now + 2 * updater.check_interval
        state.uptime = state.uptime + updater.retry_interval - 1
        plugin:onResume()
        assert.is_nil(next(tasks))
        state.uptime = state.uptime + 1
        local next_book = setmetatable({ settings = plugin.settings }, { __index = DPD })
        next_book:onNetworkConnected()
        plugin:onResume()
        delayed()
        assert.equal(2, state.launched)
        state.complete("99.0.0")
        assert.is_nil(updater.auto_retry_at)
        assert.equal(state.now, plugin.settings.update_checked)
    end)

    it("checks again a week after success without restarting the updater", function()
        plugin:scheduleUpdateCheck()
        delayed()
        state.complete("99.0.0")
        assert.is_nil(updater.auto_checking)
        assert.equal(1, state.notifications)
        state.now = state.now + updater.check_interval - 1
        plugin:onResume()
        assert.is_nil(next(tasks))
        state.now = state.now + 1
        plugin:onResume()
        delayed()
        assert.equal(2, state.launched)
        state.complete("99.0.0")
        assert.equal(1, state.notifications)
        assert.equal(state.now, plugin.settings.update_checked)
    end)
end)
