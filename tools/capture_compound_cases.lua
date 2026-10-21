-- Focused compound screenshots using the real desktop KOReader renderer.
-- From a KOReader runtime, with a disposable KO_MULTIUSER/XDG_CONFIG_HOME:
-- SDL_VIDEODRIVER=dummy ./luajit <plugin>/tools/capture_compound_cases.lua <plugin> <db> <out>
require("setupkoenv")
local root, path, out = assert(arg[1]), assert(arg[2]), assert(arg[3])
package.path = root .. "/?.lua;" .. package.path
G_defaults = require("luadefaults"):open()
G_reader_settings = require("luasettings"):wrap({dict_font_size=26})
local Device = require("device")
require("document/canvascontext"):init(Device)
require("ui/bidi").setup()
local UIManager = require("ui/uimanager")
local Viewer = require("ui/dpd_viewer")
local DB = require("dpd/db")
local lookup = require("dpd/lookup").new(DB.new(path))
local Render = require("ui/dpd_render")
local font_size = tonumber(os.getenv("DPD_TEST_FONT_SIZE")) or 20
require("libs/libkoreader-lfs").mkdir(out)
local function flush()
    UIManager:_checkTasks()
    UIManager:_repaint()
end
local cases = {
    {"vajjakammappabhedanti", "kammā", true},
    {"paratthobhayatthesupi", "parattho", true},
    {"chāyāti", "chāyā", true},
    {"kiṃkī", "kī", false},
    {"asītīti", "asītī", true},
    {"rakkhatiyeva", "rakkhatiyā", true},
    {"bhātime", "bhātu", false},
    {"middhīti", "middhī", false},
}
for index, case in ipairs(cases) do
    local model = lookup:get(case[1])
    local viewer = Viewer:new{model=model, lookup=lookup, font_size=font_size}
    local state = viewer.navigation:current()
    -- Open every analysis that adds something; only the first starts open.
    for i, analysis in ipairs(model.deconstructions) do
        if analysis.has_new then state.analyses[i] = true end
    end
    local found = false
    for i, analysis in ipairs(model.deconstructions) do
        for j, part in ipairs(analysis.parts or {}) do
            if part == case[2] and analysis.unique[j] then
                found = true
                assert(((analysis.compact or {})[j] == true) == case[3], case[2])
                local html = Render.render(model, state)
                local sense = model.components[part].senses[1]
                local uri = "dpd:component-sense/" .. i .. "/" .. j .. "/" .. sense.id
                assert((html:find(uri, 1, true) ~= nil) == not case[3], case[2] .. " leading row")
            end
        end
    end
    assert(found, case[2] .. " should remain visible")
    if case[1] == "rakkhatiyeva" then
        assert(model.deconstructions[2].compact[1], "rakkhati should also be compact")
        assert(not model.deconstructions[2].unique[2], "second eva should stay hidden")
        local html = Render.render(model, state)
        assert(html:find("only rakkhati 1, 2, 3", 1, true))
    end
    if index == 1 then assert(model.deconstructions[4].compact[2], "kammaṃ should name its senses too") end
    UIManager:show(viewer)
    flush()
    local pages = viewer.scroll.htmlbox_widget.page_count
    for page = 1, pages do
        if page > 1 then viewer.scroll:scrollToRatio((page - 1 + .1) / pages); flush() end
        local name = out .. "/" .. index .. "-" .. case[1] .. "-" .. page .. ".png"
        Device.screen.bb:writePNG(name)
        print("SHOT " .. name)
    end
    viewer:close()
end
print("PASS: leading previews, inline subsets, later analyses on their own; eight real compound cases")
os.exit(0)
