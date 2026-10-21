local Popup = require("dpd/popup")
local Navigation = require("dpd/navigation")
local Render = require("ui/dpd_render")

local function model(fields)
    local value = {query="saṃ", found=true, senses={{id=1, lemma_1="saṃ", meaning_combo="together"}},
        roots={}, grammar={}, deconstructions={}, components={}, suggestions={}, references={}, variants={}}
    for key, item in pairs(fields or {}) do value[key] = item end
    return value
end

describe("shared popup preparation", function()
    it("keeps the entry visible with a dictionary read warning, clearing it after recovery", function()
        local lookup = {hasOtherDictionaries=function() return nil,"Dictionary read failed" end}
        local frame = Navigation.new(model()):current()
        local options = {dictionaries={"cpd"}}
        local html = Popup.render(lookup,frame,options)
        assert.is_false(frame.other_dictionaries)
        assert.is_truthy(html:find("Dictionary read failed",1,true))
        assert.is_truthy(html:find("together",1,true))
        lookup.hasOtherDictionaries=function() return true end
        assert.is_falsy(Popup.render(lookup,frame,options):find("Dictionary read failed",1,true))
        assert.is_true(frame.other_dictionaries)
    end)
    it("routes lexical results, misses, prefix neighbours and variant-only records", function()
        assert.is_false(Popup.selection_options.prefix)
        assert.equal("dpd", Popup.route(model()))
        assert.equal("dictionary", Popup.route(model({found=false})))
        assert.equal("dictionary", Popup.route(model({matched_via="prefix"})))
        assert.equal("dictionary", Popup.route(model({senses={}, variants={{note="reading"}}})))
        assert.equal("dpd", Popup.route(model({found=false, senses={}, matched_via="english"})))
    end)

    it("keeps the availability probe cached by its reader and renders the same HTML", function()
        local calls, ready = 0, nil
        local lookup = {hasOtherDictionaries=function()
            if ready == nil then calls = calls + 1; ready = true end
            return ready
        end}
        local value = model()
        local frame = Navigation.new(value):current()
        local options = {dictionaries={"cpd"}, niggahita="ṁ",
            paradigm_columns=2, content_em=40}
        local html = Popup.render(lookup, frame, options)
        assert.equal(Render.niggahita(Render.render(value, frame), "ṁ"), html)
        assert.is_true(frame.other_dictionaries)
        assert.equal(2, frame.paradigm_columns)
        assert.equal(40, frame.content_em)
        Popup.render(lookup, frame, options)
        assert.equal(1, calls)
    end)

    it("skips the probe when sources are disabled or the optional API is absent", function()
        local lookup = {hasOtherDictionaries=function() error("unexpected probe") end}
        local frame = Navigation.new(model()):current()
        Popup.render(lookup, frame, {dictionaries={}})
        assert.is_false(frame.other_dictionaries)
        Popup.render({}, frame, {dictionaries={"cpd"}})
        assert.is_false(frame.other_dictionaries)
    end)
end)
