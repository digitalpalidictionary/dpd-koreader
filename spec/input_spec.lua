local Velthuis = require("dpd/velthuis")

describe("Velthuis input", function()
    it("converts the webapp's sequences in its order", function()
        assert.equal("dhammaṃ", Velthuis.toUnicode("dhamma.m"))
        assert.equal("ñāṇa", Velthuis.toUnicode("~naa.na"))
        assert.equal("ṅ ṭ ḍ ḷ ḥ ī ū", Velthuis.toUnicode('"n .t .d .l .h ii uu'))
        -- Sequential replacement, as upstream: three a's become ā then a.
        assert.equal("āa", Velthuis.toUnicode("aaa"))
    end)

    it("leaves plain and already-converted text unchanged", function()
        assert.equal("dhamma", Velthuis.toUnicode("dhamma"))
        assert.equal("ñāṇa", Velthuis.toUnicode("ñāṇa"))
        assert.equal("", Velthuis.toUnicode(nil))
    end)
end)

describe("lookup dialog", function()
    local saved, shown, closed
    before_each(function()
        saved = { package.loaded["ui/widget/inputdialog"], package.loaded["ui/uimanager"], package.loaded["ui/dpd_input"],
            package.loaded["ui/widget/infomessage"], package.loaded["ui/widget/menu"] }
        shown, closed = nil, 0
        package.loaded["ui/widget/inputdialog"] = { new = function(_, o)
            o.getInputText = function() return o.typed or o.input end
            o.onShowKeyboard = function() end
            o.onCloseWidget = function() end
            return o
        end }
        package.loaded["ui/uimanager"] = { show = function(_, w) shown = w end, close = function(_, w)
            closed = closed + 1
            if w.onCloseWidget then w:onCloseWidget() end
        end }
        package.loaded["ui/widget/infomessage"] = { new = function(_, o) return o end }
        package.loaded["ui/widget/menu"] = { new = function(_, o) return o end }
        package.loaded["ui/dpd_input"] = nil
    end)
    after_each(function()
        package.loaded["ui/widget/inputdialog"], package.loaded["ui/uimanager"], package.loaded["ui/dpd_input"] =
            saved[1], saved[2], saved[3]
        package.loaded["ui/widget/infomessage"], package.loaded["ui/widget/menu"] = saved[4], saved[5]
    end)

    local function submit(settings, typed)
        local Input = require("ui/dpd_input")
        local got
        local dialog = Input.show{ settings = settings, on_lookup = function(text) got = text end }
        dialog.typed = typed
        for _, b in ipairs(dialog.buttons[#dialog.buttons]) do
            if b.text == "Look up" then b.callback() end
        end
        return got
    end

    it("converts Velthuis only when turned on, and trims", function()
        assert.equal("dhammaṃ", submit({ velthuis = true }, "  dhamma.m "))
        assert.equal("dhamma.m", submit({}, "dhamma.m"))
        assert.equal(2, closed)
    end)

    it("never converts Velthuis in English mode", function()
        assert.equal("aardvark", submit({ velthuis = true, lookup_mode = "english" }, "aardvark"))
    end)

    it("keeps empty input open and explains what to enter", function()
        assert.is_nil(submit({}, "   "))
        assert.equal(0, closed)
        assert.is_truthy(shown.text:find("word or ID number", 1, true))
        assert.is_nil(submit({lookup_mode="english"}, ""))
        assert.equal(0, closed)
        assert.equal("Type an English word first.", shown.text)
        assert.is_nil(submit({}, " "))
        assert.is_nil(submit({lookup_mode="english"}, " \t  "))
        assert.equal(0, closed)
    end)

    local function action(dialog, name)
        for _, button in ipairs(dialog.buttons[1]) do if button.text == name then return button.callback() end end
        error("Missing action " .. name)
    end

    it("restores an unconverted draft and mode when Recent is dismissed, once", function()
        local settings = {velthuis=true}
        local history = require("dpd/history").new({history={{query="dhamma",mode="pali"}}})
        local reopened, count = nil, 0
        local dialog = require("ui/dpd_input").show{settings=settings,history=history,
            on_lookup=function() error("dismissal must not run a lookup") end,
            on_reopen=function(new) reopened=new; count=count+1 end}
        dialog.typed="~naa.na"
        action(dialog,"Recent")
        local menu = shown
        assert.equal(1, closed)
        menu.close_callback(); menu.close_callback()
        assert.equal("~naa.na", reopened.input)
        assert.equal("pali", reopened.mode)
        assert.equal(1, count)
    end)

    it("does not restore the draft after choosing a recent lookup", function()
        local history = require("dpd/history").new({history={{query="meditation",mode="english"}}})
        local query, mode, reopened
        local dialog = require("ui/dpd_input").show{settings={},history=history,
            on_lookup=function(q,m) query,mode=q,m end,
            on_reopen=function() reopened=true end}
        dialog.typed="unfinished"
        action(dialog,"Recent")
        local menu = shown
        menu.item_table[1].callback(); menu.close_callback()
        assert.equal("meditation", query)
        assert.equal("english", mode)
        assert.is_nil(reopened)
    end)

    it("replays complete queries and dictionary drafts regardless of current Velthuis", function()
        local long = "muttakarīsacammaaṭṭhinhārukhaṇḍakheḷasiṅghāṇikālohitappabhutinānākuṇapajātaṃ"
        assert.is_true(#long > 100)
        for _, velthuis in ipairs({ false, true }) do
            for _, item in ipairs({
                { query = "vacūm", mode = "dictionaries", draft = "vacuum" },
                { query = long, mode = "pali" },
            }) do
                local history = require("dpd/history").new({})
                history:add(item.query, item.mode, item.draft)
                local got
                local dialog = require("ui/dpd_input").show{settings={velthuis=velthuis},history=history,
                    on_lookup=function(q,m,d) got={query=q,mode=m,draft=d} end}
                action(dialog,"Recent")
                shown.item_table[1].callback()
                assert.same(item,got)
            end
        end
    end)

    it("releases the Recent owner once on dismissal or selection, without clearing a newer dialog", function()
        local Input = require("ui/dpd_input")
        local history = require("dpd/history").new({history={{query="dhamma",mode="pali"}}})
        for _, route in ipairs({"dismiss", "select", "external"}) do
            local current, menu, notified, looked_up = nil, nil, 0, false
            menu = Input.showRecent{history=history,
                on_close=function(widget)
                    assert.equal(menu, widget)
                    notified=notified+1
                    if current==widget then current=nil end
                end,
                on_lookup=function()
                    assert.is_nil(current,"release the menu before running the lookup")
                    looked_up=true
                    current="new dialog"
                end}
            current=menu
            if route=="dismiss" then menu.close_callback()
            elseif route=="select" then menu.item_table[1].callback()
            else require("ui/uimanager"):close(menu) end
            assert.equal(1,notified)
            assert.equal(route=="select",looked_up)
            if route=="select" then assert.equal("new dialog",current)
            else assert.is_nil(current);current="new dialog" end
            menu:onCloseWidget()
            assert.equal(1,notified)
            assert.equal("new dialog",current)
        end
    end)

    it("keeps the draft open when recent lookups are empty or off", function()
        for _, off in ipairs({false,true}) do
            local history = require("dpd/history").new({history_off=off})
            local dialog = require("ui/dpd_input").show{settings={},history=history,on_lookup=function() end}
            dialog.typed="unfinished"
            action(dialog,"Recent")
            assert.equal("unfinished", dialog:getInputText())
            assert.equal(0, closed)
            assert.is_truthy(shown.text:find(off and "Turn on Recent lookups → Record recent lookups" or "yet", 1, true))
        end
    end)

    describe("searching the other dictionaries", function()
        local function open(options)
            options.settings = options.settings or {}
            options.mode = options.mode or "dictionaries"
            options.on_lookup = options.on_lookup or function() end
            return require("ui/dpd_input").show(options)
        end
        local function labels(dialog)
            local out = {}
            for _, button in ipairs(dialog.buttons[1]) do out[#out + 1] = button.text end
            return out
        end

        it("names its mode and offers DPD in the mode button's place", function()
            local dialog = open{}
            assert.equal("Other dictionaries", dialog.title)
            assert.equal("word or name", dialog.input_hint)
            assert.same({ "Cancel", "Recent", "DPD", "Look up" }, labels(dialog))
            assert.equal("Other dictionaries · Velthuis", open{settings={velthuis=true}}.title)
        end)

        it("shows no suggestions and makes no suggestion queries while typing", function()
            local calls = 0
            local uimanager = package.loaded["ui/uimanager"]
            uimanager.scheduleIn = function(_, _, fn) fn() end
            uimanager.unschedule = function() end
            local dialog = open{suggest=function() calls = calls + 1; return {}, "empty" end}
            assert.is_nil(dialog.suggestion_area)
            dialog.typed = "dharma"
            dialog.edited_callback()
            assert.equal(0, calls)
        end)

        it("converts Sanskrit Velthuis here, never in Pāḷi mode", function()
            local got
            local dialog = open{settings={velthuis=true}, on_lookup=function(text, mode) got = { text, mode } end}
            dialog.typed = '"saariputra .r.si k.r.s.na'
            action(dialog, "Look up")
            assert.same({ "śāriputra ṛṣi kṛṣṇa", "dictionaries" }, got)
            assert.equal('"sāriputra .r.si', submit({ velthuis = true }, '"saariputra .r.si'))
        end)

        it("asks for a word on an empty submit", function()
            local dialog = open{}
            dialog.typed = "  "
            action(dialog, "Look up")
            assert.equal(0, closed)
            assert.equal("Type a word first.", shown.text)
        end)

        it("switches modes to what each button names, remembering only Pāḷi and English", function()
            local settings, reopened = {}, nil
            local function switch(mode, button)
                local dialog = open{settings=settings, mode=mode, on_reopen=function(new) reopened = new end}
                dialog.typed = "dharma"
                action(dialog, button)
                return reopened
            end
            local new = switch("dictionaries", "DPD")
            assert.equal("pali", new.mode)
            assert.equal("dharma", new.input)
            assert.equal("pali", settings.lookup_mode)
            assert.equal("english", switch("pali", "English").mode)
            assert.equal("english", settings.lookup_mode)
            assert.equal("pali", switch("english", "Pāḷi").mode)
            assert.equal("pali", settings.lookup_mode)
        end)

        it("returns from Recent to the same mode and draft", function()
            local history = require("dpd/history").new({history={{query="dhamma",mode="pali"}}})
            local reopened
            local dialog = open{history=history, on_reopen=function(new) reopened = new end}
            dialog.typed = "Mahā Bodhi"
            action(dialog, "Recent")
            shown.close_callback()
            assert.equal("dictionaries", reopened.mode)
            assert.equal("Mahā Bodhi", reopened.input)
        end)

        it("labels these searches in Recent and replays them in this mode", function()
            local history = require("dpd/history").new({history={{query="dharma",mode="dictionaries"}}})
            local query, mode
            local menu = require("ui/dpd_input").showRecent{history=history,
                on_lookup=function(q, m) query, mode = q, m end}
            assert.equal("Dictionaries", menu.item_table[1].mandatory)
            menu.item_table[1].callback()
            assert.same({ "dharma", "dictionaries" }, { query, mode })
        end)
    end)
end)

describe("ṁ display", function()
    local Render = require("ui/dpd_render")
    it("changes displayed text only, never tags or hrefs", function()
        local html = '<p><a href="dpd:headword/saṃgha">saṃgha</a> Ṃ</p>'
        assert.equal('<p><a href="dpd:headword/saṃgha">saṁgha</a> Ṁ</p>', Render.niggahita(html, "ṁ"))
        assert.equal(html, Render.niggahita(html, nil))
        assert.equal("dhammaṁ", Render.niggahita("dhammaṃ", "ṁ"))
    end)
end)
