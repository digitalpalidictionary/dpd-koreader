local function tempDataDir()
    local dir = os.tmpname()
    os.remove(dir)
    os.execute("mkdir -p '" .. dir .. "/data/dpd'")
    return dir
end

local function read(path)
    local handle = io.open(path, "r")
    if not handle then return nil end
    local text = handle:read("*a")
    handle:close()
    return text
end

describe("diagnostic log", function()
    local Diag, dir, saved

    before_each(function()
        dir = tempDataDir()
        saved = package.loaded.datastorage
        package.loaded.datastorage = { getDataDir = function() return dir end }
        package.loaded["dpd/diag"] = nil
        Diag = require("dpd/diag")
    end)

    after_each(function()
        Diag.setEnabled(false)
        package.loaded.datastorage = saved
        package.loaded["dpd/diag"] = nil
        os.execute("rm -rf '" .. dir .. "'")
    end)

    it("writes nothing when disabled", function()
        Diag.log("never written")
        assert.is_nil(read(Diag.path()))
    end)

    it("reports production errors with diagnostics off and preserves original values", function()
        local saved_logger = package.loaded.logger
        local warnings = {}
        package.loaded.logger = {warn=function(_, trace) warnings[#warnings + 1] = trace end}
        local value = {code=7}
        local ok, err = Diag.protect("boundary", function() error(value) end)
        local results = {Diag.protect("results", function(a,b,c) return a,b,c end, 1,nil,3)}
        package.loaded.logger = saved_logger
        assert.is_false(ok)
        assert.equal(value, err)
        assert.matches("stack traceback:", warnings[1], 1, true)
        assert.same({true,1,nil,3}, results)
        assert.is_nil(read(Diag.path()))
    end)

    it("contains the original failure even when both loggers fail", function()
        local saved_logger, saved_log = package.loaded.logger, Diag.log
        package.loaded.logger = {warn=function() error("logger failed") end}
        Diag.log = function() error("diagnostics failed") end
        local value = {}
        local ok, err = Diag.protect("boundary", function() error(value) end)
        package.loaded.logger, Diag.log = saved_logger, saved_log
        assert.is_false(ok)
        assert.equal(value, err)
    end)

    it("logs a header, ordered lines and error tracebacks without changing results", function()
        Diag.setEnabled(true)
        Diag.log("Popup open:", "bhante", "depth:", 1, nil)
        local ok, err = Diag.protect("popup rebuild", function() error("rebuild failed") end)
        assert.is_false(ok)
        assert.matches("rebuild failed$", err)
        local text = read(Diag.path())
        assert.matches("#1 ==== DPD ", text, 1, true)
        assert.matches("#2 Popup open: bhante depth: 1 nil", text, 1, true)
        assert.matches("ERROR in popup rebuild: [^\n]*rebuild failed\nstack traceback:", text)
    end)

    it("settles the Lua heap before reporting it on request", function()
        local garbage = {}
        for i = 1, 2000 do garbage[i] = { string.rep("x", 100) } end
        garbage = nil
        local function kb(text) return tonumber(text:match("lua=(%d+)KB")) end
        local unsettled = kb(Diag.memory())
        local settled = kb(Diag.memory(true))
        assert.truthy(settled <= unsettled)
    end)

    it("keeps one previous log once the size limit is passed", function()
        Diag.max_bytes = 200
        Diag.setEnabled(true)
        for i = 1, 20 do Diag.log("line", i, string.rep("x", 20)) end
        local current, previous = read(Diag.path()), read(Diag.path() .. ".old")
        assert.truthy(previous)
        assert.truthy(#current < 300)
        assert.matches("line 20 ", current, 1, true)
        assert.matches("line 20 ", Diag.tail(1), 1, true)
        assert.equal(2, select(2, Diag.tail(2):gsub("\n", "")) + 1)
    end)

    it("creates the data folder when the database lives elsewhere", function()
        os.execute("rm -rf '" .. dir .. "/data'")
        package.loaded["libs/libkoreader-lfs"] = { mkdir = function(path)
            os.execute("mkdir -p '" .. path .. "'")
        end }
        Diag.setEnabled(true)
        package.loaded["libs/libkoreader-lfs"] = nil
        assert.matches("==== DPD", read(Diag.path()), 1, true)
    end)
end)

describe("KOReader feature check", function()
    local saved_defaults, saved_widget

    before_each(function()
        saved_defaults, saved_widget = _G.G_defaults, package.loaded["ui/widget/scrollhtmlwidget"]
    end)

    after_each(function()
        _G.G_defaults = saved_defaults
        package.loaded["ui/widget/scrollhtmlwidget"] = saved_widget
    end)

    local function koreader(delay, ratio)
        _G.G_defaults = { readSetting = function(_, key) return key == "DELAY_CLEAR_HIGHLIGHT_S" and delay or nil end }
        package.loaded["ui/widget/scrollhtmlwidget"] = { getCurrentRatio = ratio and function() end or nil }
    end

    it("accepts a KOReader with every feature", function()
        koreader(0.5, true)
        assert.same({}, require("dpd/compat").missing())
    end)

    it("names each missing feature, as in KOReader v2025.08", function()
        local Compat = require("dpd/compat")
        koreader(nil, false)
        assert.same({ "DELAY_CLEAR_HIGHLIGHT_S", "ScrollHtmlWidget:getCurrentRatio" }, Compat.missing())
        koreader(0.5, false)
        assert.same({ "ScrollHtmlWidget:getCurrentRatio" }, Compat.missing())
        _G.G_defaults = nil
        assert.same({ "DELAY_CLEAR_HIGHLIGHT_S", "ScrollHtmlWidget:getCurrentRatio" }, Compat.missing())
        assert.matches("needs KOReader " .. Compat.minimum .. " or newer", Compat.message({ "x" }), 1, true)
    end)

    it("logs failed checks without classifying them as missing features", function()
        local saved_logger = package.loaded.logger
        local warnings = {}
        package.loaded.logger = {warn=function(label, trace) warnings[#warnings + 1] = label .. trace end}
        _G.G_defaults = { readSetting = function() error("settings unavailable") end }
        package.loaded["ui/widget/scrollhtmlwidget"] = nil
        package.preload["ui/widget/scrollhtmlwidget"] = function() error("widget unavailable") end
        local missing = require("dpd/compat").missing()
        package.loaded.logger = saved_logger
        package.preload["ui/widget/scrollhtmlwidget"] = nil
        assert.same({}, missing)
        assert.equal(2, #warnings)
        assert.matches("DELAY_CLEAR_HIGHLIGHT_S", warnings[1], 1, true)
        assert.matches("ScrollHtmlWidget:getCurrentRatio", warnings[2], 1, true)
    end)
end)

describe("plugin on an unsupported KOReader", function()
    local function load(features)
        local names = { "datastorage", "dpd/db", "ui/widget/infomessage", "ui/widget/inputdialog",
            "ui/widget/pathchooser", "ui/uimanager", "ui/dpd_viewer", "ui/widget/container/widgetcontainer",
            "libs/libkoreader-lfs", "logger", "ui/time", "util", "main", "ui/widget/scrollhtmlwidget",
            "ui/widget/textviewer", "dispatcher" }
        local saved = {}
        for _, name in ipairs(names) do saved[name] = package.loaded[name]; package.loaded[name] = {} end
        local globals = { G_defaults = _G.G_defaults, G_reader_settings = _G.G_reader_settings }
        local state = { messages = {}, registered = 0, actions = {} }
        _G.G_defaults = { readSetting = function() return features.delay end }
        package.loaded["ui/widget/scrollhtmlwidget"] = { getCurrentRatio = features.ratio and function() end or nil }
        _G.G_reader_settings = { readSetting = function() return { direct_lookup = true } end, saveSetting = function() end }
        package.loaded["ui/widget/container/widgetcontainer"] = { extend = function(_, value) return value end }
        package.loaded["ui/uimanager"] = { nextTick = function(_, action) action() end,
            show=function(_, widget) state.shown=widget end }
        package.loaded["ui/widget/textviewer"] = {new=function(_, value) return value end}
        package.loaded.dispatcher = { registerAction = function(_, name) state.actions[name] = true end }
        package.loaded["libs/libkoreader-lfs"] = { attributes = function() return nil end }
        package.loaded.datastorage = { getDataDir = function() return "/nonexistent" end }
        package.loaded.main = nil
        local saved_preload = package.preload["ui/dpd_viewer"]
        if features.unavailable_viewer then
            package.loaded["ui/dpd_viewer"] = nil
            package.preload["ui/dpd_viewer"] = function() error("viewer unavailable") end
        end
        local DPD = require("main")
        local function plugin()
            local dictionary = { onLookupWord = function() return "normal" end,
                addToDictButtons = function() state.dict_button = true end }
            local instance = setmetatable({ ui = {
                menu = { registerToMainMenu = function() state.registered = state.registered + 1 end },
                dictionary = dictionary,
                highlight = { addToHighlightDialog = function() state.highlight_button = true end },
            } }, { __index = DPD })
            function instance:message(text) state.messages[#state.messages + 1] = text end
            instance:init()
            return instance
        end
        local restore = function()
            for _, name in ipairs(names) do package.loaded[name] = saved[name] end
            package.preload["ui/dpd_viewer"] = saved_preload
            _G.G_defaults, _G.G_reader_settings = globals.G_defaults, globals.G_reader_settings
        end
        return plugin, state, restore
    end

    it("keeps lookups with the normal dictionary and explains once per session", function()
        local plugin, state, restore = load({ delay = 0.5, ratio = false })
        local first = plugin()
        local second = plugin()
        restore()
        assert.equal(2, state.registered)
        -- A gesture set up earlier still answers, with the explanation.
        assert.is_true(state.actions.dpd_look_up)
        assert.is_nil(state.dict_button)
        assert.is_nil(state.highlight_button)
        assert.is_nil(first.direct)
        assert.equal("normal", first.ui.dictionary:onLookupWord("bhante"))
        assert.equal(1, #state.messages)
        assert.matches("ScrollHtmlWidget:getCurrentRatio", state.messages[1], 1, true)
        local items = {}
        second:addToMainMenu(items)
        local entries = items.dpd.sub_item_table
        assert.equal("Needs a newer KOReader", entries[1].text)
        assert.equal("Help", entries[2].text_func())
        assert.equal("DPD help", entries[2].sub_item_table[1].text)
        assert.equal("Check for updates", entries[2].sub_item_table[3].text_func())
        assert.equal("Diagnostics", entries[2].sub_item_table[5].text)
        assert.equal(2, #entries)
    end)

    it("loads its explanatory menu without importing an unavailable viewer", function()
        local plugin, state, restore = load({delay=0.5,ratio=false,unavailable_viewer=true})
        local instance = plugin()
        instance.ensureLookup = function() error("About must not open a database") end
        instance:aboutLicenses()
        assert.matches("MIT License", state.shown.text, 1, true)
        assert.matches("not opened / unknown", state.shown.text, 1, true)
        instance.db = {info={dpd_release_version="test-version"}}
        instance:aboutLicenses()
        assert.matches("Database version: test-version", state.shown.text, 1, true)
        assert.matches("Franklin Edgerton", state.shown.text, 1, true)
        -- A database without other dictionaries credits none.
        instance.lookup = { _dictionaries = function() return { list = function() return {} end } end }
        instance:aboutLicenses()
        assert.is_nil(state.shown.text:find("Additional dictionary content", 1, true))
        instance.lookup = { _dictionaries = function() return { list = function()
            return { { id = "new", name = "A New Dictionary", author = "" } } end } end }
        instance:aboutLicenses()
        assert.matches("details:\n• A New Dictionary", state.shown.text, 1, true)
        assert.is_nil(state.shown.text:find("Franklin Edgerton", 1, true))
        restore()
        assert.truthy(instance.unsupported)
        assert.is_nil(instance.direct)
    end)

    it("installs entry points and the full menu on a supported KOReader", function()
        local plugin, state, restore = load({ delay = 0.5, ratio = true })
        local instance = plugin()
        restore()
        assert.is_true(state.dict_button)
        assert.is_true(state.highlight_button)
        assert.truthy(instance.direct)
        assert.same({}, state.messages)
        local items = {}
        instance:addToMainMenu(items)
        local entries = items.dpd.sub_item_table
        assert.equal("Look up a word", entries[1].text)
        assert.equal("Help", entries[#entries].text_func())
        local help = entries[#entries].sub_item_table
        assert.equal("Check for updates", help[3].text_func())
        instance.settings.update_available = "99.0.0"
        assert.equal("Help · 99.0.0 available", entries[#entries].text_func())
        assert.equal("Check for updates (99.0.0 available)", help[3].text_func())
        instance.settings.update_available = require("dpd/version")
        assert.equal("Help", entries[#entries].text_func())
        assert.equal("Check for updates automatically", help[4].text)
        assert.equal("Diagnostics", help[5].text)
        local display, dictionaries
        for _, entry in ipairs(entries) do
            if entry.text == "Display and input" then display = entry end
            if entry.text == "Other dictionaries" then dictionaries = entry end
        end
        assert.equal(3, #display.sub_item_table)
        assert.equal("Popup font size: " .. instance.settings.font_size, display.sub_item_table[1].text_func())
        -- Hold shows the full title and author; Burmese needs a font.
        local details = {}
        for _, item in ipairs(dictionaries.sub_item_table_func()) do details[#details + 1] = item.help_text_func() end
        assert.matches("Edgerton's Buddhist Hybrid Sanskrit Dictionary 1953\nFranklin Edgerton", table.concat(details, "|"), 1, true)
        assert.matches("Myanmar font", table.concat(details, "|"), 1, true)
        -- With a database open, its dict_meta decides the toggles.
        local listed = { { id = "cpd", name = "Critical Pali Dictionary", author = "V. Trenckner et al.", count = 2 },
            { id = "new", name = "A New Dictionary", author = "Someone", count = 5 } }
        instance.saveSettings = function() end
        instance.lookup = { _dictionaries = function() return { list = function() return listed end } end }
        local toggles = dictionaries.sub_item_table_func()
        assert.equal(2, #toggles)
        assert.equal("Critical Pali Dictionary", toggles[1].text)
        assert.equal("A New Dictionary", toggles[2].text)
        assert.equal("A New Dictionary\nSomeone\n5 entries", toggles[2].help_text_func())
        assert.is_true(toggles[2].checked_func())
        assert.same({ "cpd", "new" }, instance:enabledDictionaries())
        toggles[2].callback()
        assert.is_false(toggles[2].checked_func())
        assert.same({ "cpd" }, instance:enabledDictionaries())
        toggles[2].callback()
        assert.same({ "cpd", "new" }, instance:enabledDictionaries())
        listed = {}
        assert.equal("None in this database", dictionaries.sub_item_table_func()[1].text)
        instance.direct:remove()
    end)
end)
