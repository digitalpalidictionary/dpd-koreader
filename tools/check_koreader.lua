-- Run from a desktop KOReader directory with its own luajit:
-- SDL_VIDEODRIVER=dummy ./luajit <plugin>/tools/check_koreader.lua <plugin> <dpd-mobile.db> [screenshot-dir]
require("setupkoenv")
local root, path = assert(arg[1], "plugin directory required"), assert(arg[2], "DPD database required")
package.path = root .. "/?.lua;" .. package.path
local DB = require("dpd/db")
local Lookup = require("dpd/lookup")
local db = DB.new(path)
local lookup = Lookup.new(db)
local pacchima = lookup:get("pacchima")
assert(pacchima.found and #pacchima.senses == 8)
for i, sense in ipairs(pacchima.senses) do assert(sense.lemma_1 == "pacchima " .. i) end
local count = db.query_count
assert(lookup:get("“pacchima,”").original == "“pacchima,”")
assert(db.query_count == count, "cached lookup should use no queries")
assert(lookup:get("PACCHIMA").query == "pacchima")
assert(#lookup:get("pacchimassa").grammar == 8)
assert(lookup:get("saṁ").query == "saṃ")
assert(not lookup:get("not_a_pali_word_123").found)
assert(not lookup:get("pacchima' OR 1=1").found)
local detail = lookup:detail(pacchima.senses[1].id)
assert(detail.grammar_line ~= "" and detail.construction ~= "")
local compound_count = db.query_count
local compound = lookup:get("vajjakammappabhedanti")
assert(compound.found and #compound.deconstructions == 5)
assert(db.query_count - compound_count == 3, "compound should use three batched queries")
assert(compound.components.kammi.total == 1)
assert(compound.deconstructions[2].parts[2] == "kammi" and compound.deconstructions[2].unique[2])
assert(compound.deconstructions[3].parts[2] == "kammā" and compound.deconstructions[3].unique[2])
assert(compound.deconstructions[5].unique[1] and compound.deconstructions[5].unique[2])
assert(#lookup:get("pacchimakattikapuṇṇamā").deconstructions == 1)
local inflected = lookup:get("saṃvidāvahāro")
assert(inflected.found and inflected.senses[1].lemma_1 == "saṃvidāvahāra")
assert(#inflected.deconstructions == 0)
assert(lookup:detail(inflected.senses[1].id).construction == "saṃvida + avahāra")
local future = lookup:get("avaharissāmā")
assert(future.found and future.query == "avaharissāmā" and future.matched_via == "fuzzy")
assert(future.suggestions[1].query == "avaharissāma")
assert(lookup:get(future.suggestions[1].query).senses[1].lemma_1 == "avaharati")
local consulted = lookup:get("saṃmantayitvā")
assert(consulted.found and #consulted.suggestions == 2)
local deconstructor_suggestion
for i, suggestion in ipairs(consulted.suggestions) do
    if suggestion.query == "samantayitvā" then deconstructor_suggestion = i end
end
assert(deconstructor_suggestion and lookup:get("samantayitvā").deconstructions[1].raw == "sa + mantayitvā")
for _, word in ipairs({"avaharissāmāti", "sammantayitvāti"}) do
    local both = lookup:get(word)
    assert(#both.senses > 0 and #both.deconstructions == 1)
end
local Normalize = require("dpd/normalize")
local fuzzy_samples = db:query([[SELECT lookup_key,fuzzy_key FROM lookup
WHERE lookup_key NOT GLOB '*[^a-zāīūṅñṭḍṇḷṃṁ]*' ORDER BY lookup_key LIMIT 500]])
assert(#fuzzy_samples == 500)
for _, sample in ipairs(fuzzy_samples) do
    assert(Normalize.fuzzy(sample.lookup_key) == sample.fuzzy_key, sample.lookup_key)
end

-- Check failure behavior, optional columns, bound queries and read-only access
-- against a tiny database created only for this test.
local SQ3 = require("lua-ljsqlite3/init")
local fixture_path = os.tmpname()
os.remove(fixture_path)
local fixture = SQ3.open(fixture_path)
fixture:exec([[CREATE TABLE lookup(lookup_key TEXT PRIMARY KEY,headwords TEXT,deconstructor TEXT);
CREATE TABLE dpd_headwords(id INTEGER PRIMARY KEY,lemma_1 TEXT,pos TEXT,meaning_1 TEXT,meaning_2 TEXT);
INSERT INTO lookup VALUES('test','[1]','');
INSERT INTO lookup VALUES('bad','not json','');
INSERT INTO lookup VALUES('sn.','[1]','');
INSERT INTO dpd_headwords VALUES(1,'test','adj','checked','');]])
fixture:close()
local minimal = DB.new(fixture_path)
local minimal_lookup = Lookup.new(minimal)
assert(minimal_lookup:get("test").senses[1].meaning_combo == "checked")
assert(minimal_lookup:get("SN.").matched_via == "dot")
assert(minimal_lookup:detail(1).grammar_line == "")
assert(not minimal_lookup:get("absent").found, "missing optional fuzzy column must remain supported")
assert(not pcall(minimal_lookup.get, minimal_lookup, "bad"))
assert(not pcall(minimal.query, minimal, "DELETE FROM lookup"), "connection must reject writes")
assert(minimal_lookup:get("test").found, "a failed query must leave the connection usable")
minimal:close()
fixture = SQ3.open(fixture_path)
fixture:exec("ALTER TABLE lookup ADD COLUMN fuzzy_key TEXT")
for i = 1, 25 do
    fixture:exec("INSERT INTO lookup VALUES('aaa" .. i .. "','[]','[]','z')")
end
fixture:exec([[INSERT INTO lookup VALUES('zz','[1]','','z');
INSERT INTO lookup VALUES('zzz','[1]','','z');
INSERT INTO lookup VALUES('zzzz','','["zz + zzz"]','z');]])
fixture:close()
local fuzzy_fixture = DB.new(fixture_path)
local ranked = fuzzy_fixture:fuzzy("z", "zzzx")
assert(#ranked == 3, "unusable rows must not consume the candidate limit")
assert(ranked[1].lookup_key == "zzzz" and ranked[1].deconstructor ~= "")
assert(ranked[2].lookup_key == "zzz" and ranked[3].lookup_key == "zz")
fuzzy_fixture:close()
fixture = SQ3.open(fixture_path)
fixture:exec("DROP TABLE dpd_headwords")
fixture:close()
assert(not pcall(DB.new, fixture_path), "missing core schema must fail clearly")
os.remove(fixture_path)
assert(not pcall(DB.new, "/tmp/dpd-does-not-exist.db"))
local corrupt_path = os.tmpname()
local corrupt = assert(io.open(corrupt_path,"wb")); corrupt:write("not SQLite"); corrupt:close()
assert(not pcall(DB.new, corrupt_path)); os.remove(corrupt_path)
print("PASS: real DPD lookups, batching, normalization, lazy details, schema checks and read-only access")

G_defaults = require("luadefaults"):open()
local font_size = tonumber(os.getenv("DPD_TEST_FONT_SIZE")) or 16
G_reader_settings = require("luasettings"):wrap({dict_font_size=26})
local Device = require("device")
require("document/canvascontext"):init(Device)
require("ui/bidi").setup()
local UIManager = require("ui/uimanager")
local Viewer = require("ui/dpd_viewer")
-- Scripted taps follow rebuilds immediately. check_learning.lua separately
-- exercises the production repeat-tap guard with explicit event timestamps.
Viewer.link_guard_s = 0
local function flush()
    UIManager:_checkTasks()
    UIManager:_repaint()
end
local function screenshot(name)
    if arg[3] then Device.screen.bb:writePNG(arg[3] .. "/" .. name .. ".png") end
end
local closed = false
local viewer = Viewer:new{model=pacchima, lookup=lookup, font_size=font_size, close_callback=function() closed=true end}
UIManager:show(viewer); flush(); screenshot("pacchima")
viewer:onLink("dpd:sense/" .. pacchima.senses[2].id); flush(); screenshot("pacchima-detail")
assert(viewer.navigation:current().expanded[pacchima.senses[2].id])
viewer:close(); assert(closed and viewer.closed)

viewer = Viewer:new{model=compound, lookup=lookup, font_size=font_size}
UIManager:show(viewer); flush()
-- Only analysis 1 starts open, and each later one compares with it alone.
-- kammā and kammaṃ both have six of kamma's eight senses, starting with the
-- two analysis 1 shows: each names them instead of repeating their rows.
local open = viewer.navigation:current().analyses
assert(open[1] and not (open[2] or open[3] or open[4] or open[5]))
for i = 3, 4 do
    assert(compound.deconstructions[i].compact[2] and not compound.deconstructions[i].unique[1])
end
screenshot("compound-deltas")
viewer:onLink("dpd:analysis/5"); flush()
assert(viewer.navigation:current().analyses[5])
viewer:onLink("dpd:analysis/5"); flush()
assert(not viewer.navigation:current().analyses[5])
for i = 2, 5 do viewer:onLink("dpd:analysis/" .. i); flush() end
viewer.scroll:scrollToRatio(1)
local ratio = viewer:ratio()
if viewer.scroll.htmlbox_widget.page_count > 1 then
    assert(ratio > 0, "scroll-restoration check must reach a later page")
else
    assert(ratio == 0, "a single-page parent must stay at the beginning")
end
if os.getenv("DPD_TEST_REQUIRE_SCROLL") then
    assert(ratio > 0, "this viewport must exercise nonzero scroll restoration")
end
viewer:onLink("dpd:component/2/2"); flush(); screenshot("kammi")
assert(viewer.navigation:current().model.query == "kammi")
local back_button = assert(viewer.window[1][1].left_button)
assert(back_button.image.file:match("chevron%.left%.svg$"), "Back must resolve to a real KOReader icon")
assert(back_button:onTapIconButton())
flush()
assert(viewer.navigation:current().model.query == compound.query)
assert(viewer:ratio() == ratio, "Back must restore the exact scroll position")
local html = viewer.scroll.html_body
assert(html:find("dpd:component/2/2",1,true) and html:find("dpd:component/2/1",1,true))
assert(not html:find('<div class="component"><p><a href="dpd:component/2/1"',1,true),
    "a repeated header component is linked without duplicating its brief summary")
-- Exercise actual MuPDF link coordinates and the tap callback, including when
-- KOReader's tap-to-follow-book-links setting is disabled.
viewer.scroll:scrollToRatio(0); flush()
local box = viewer.scroll.htmlbox_widget
local page = box.document:openPage(1)
local links = page:getPageLinks(); page:close()
local target
for _, link in ipairs(links) do if link.uri=="dpd:analysis/1" then target=link; break end end
assert(target, "MuPDF must preserve the internal control URI")
G_reader_settings:saveSetting("tap_to_follow_links",false)
local Geom = require("ui/geometry")
assert(box:onTapText(nil, {pos=Geom:new{x=box.dimen.x+(target.x0+target.x1)/2,
    y=box.dimen.y+(target.y0+target.y1)/2,w=0,h=0}}))
flush(); assert(not viewer.navigation:current().analyses[1])
viewer:close()

viewer = Viewer:new{model=consulted, lookup=lookup, font_size=font_size}
UIManager:show(viewer); flush(); screenshot("similar-forms")
local similar_frame = viewer.navigation:current()
for _, candidate in ipairs(similar_frame.suggestions) do assert(candidate.open) end
assert(similar_frame.suggestions[deconstructor_suggestion].analyses[1])
assert(viewer.scroll.html_body:find("having consulted",1,true))
assert(viewer.scroll.html_body:gsub("<[^>]+>", ""):find("sa + mantayitvā",1,true))
viewer:onLink("dpd:similar/" .. deconstructor_suggestion .. "/analysis/1"); flush()
assert(not similar_frame.suggestions[deconstructor_suggestion].analyses[1])
viewer:onLink("dpd:similar/" .. deconstructor_suggestion .. "/analysis/1"); flush()
local headword_suggestion = 3 - deconstructor_suggestion
viewer:onLink("dpd:similar/" .. headword_suggestion .. "/sense/60749"); flush()
assert(similar_frame.suggestions[headword_suggestion].expanded[60749])
assert(not similar_frame.expanded[60749])
viewer:onLink("dpd:similar/" .. deconstructor_suggestion); flush()
assert(not similar_frame.suggestions[deconstructor_suggestion].open)
viewer:onLink("dpd:similar/" .. deconstructor_suggestion); flush()
assert(similar_frame.suggestions[deconstructor_suggestion].analyses[1])
local similar_ratio = viewer:ratio()
viewer:onLink("dpd:similar/" .. deconstructor_suggestion .. "/component/1/2"); flush()
assert(viewer.navigation:current().model.query == "mantayitvā")
viewer:back(); flush()
assert(viewer:ratio() == similar_ratio)
assert(viewer.navigation:current().suggestions[headword_suggestion].expanded[60749])
viewer:onLink("dpd:suggestion/" .. deconstructor_suggestion); flush()
assert(viewer.navigation:current().model.query == "samantayitvā")
assert(viewer.navigation:current().analyses[1])
viewer:back(); flush()
assert(viewer.navigation:current().model.query == "saṃmantayitvā")
viewer:close()

local formatted = lookup:get("acceka")
local formatted_id = formatted.senses[1].id
viewer = Viewer:new{model=formatted, lookup=lookup, font_size=font_size}
UIManager:show(viewer); flush()
viewer:onLink("dpd:sense/" .. formatted_id); flush(); screenshot("formatted-construction")
assert(viewer.scroll.html_body:find("acc<b>āyi</b>ka",1,true))
assert(not viewer.scroll.html_body:find("&lt;b&gt;",1,true))
local box = viewer.scroll.htmlbox_widget
local page = box.document:openPage(1)
local text = page:getPageText(); page:close()
local visible = {}
for _, line in ipairs(text) do
    for _, word in ipairs(line) do if type(word) == "table" and word.word then visible[#visible+1] = word.word end end
end
local visible_text = table.concat(visible," ")
assert(visible_text:find("accāyika",1,true), "MuPDF text must include the formatted construction")
assert(not visible_text:find("<b>",1,true), "MuPDF must render formatting rather than literal tags")
viewer:close()

-- Real plugin initialization with a dictionary stub: exercise wrapper, ownership,
-- suspend/resume, fallback transfer and restoration through real UIManager widgets.
local normal_calls, clear_calls, callback_calls = 0, 0, 0
local pending_clears = {}
local schedule = UIManager.scheduleIn
local clear_delay = G_defaults:readSetting("DELAY_CLEAR_HIGHLIGHT_S")
UIManager.scheduleIn = function(self, seconds, action, ...)
    if seconds == clear_delay then
        local args = {...}
        pending_clears[#pending_clears + 1] = function() action(unpack(args)) end
        return action
    end
    return schedule(self, seconds, action, ...)
end
local original = function(_, word) normal_calls=normal_calls+1; return true end
local dictionary = {onLookupWord=original, addToDictButtons=function(self,spec) self.spec=spec end}
local selected = { getClearId=function() return 7 end, clear=function(_, id) assert(id==7); clear_calls=clear_calls+1 end }
local menu = {registerToMainMenu=function() end}
G_reader_settings:saveSetting("dpd", {db_path=path,direct_lookup=true,font_size=font_size})
local plugin = require("main"):new{ui={menu=menu,dictionary=dictionary}}
assert(dictionary.spec and dictionary.spec.id == "dpd")
local prefix_model = plugin:getModel("bhikkhux")
assert(prefix_model.matched_via == "prefix" and prefix_model.single_suggestion)
assert(not plugin:getModel("bhikkhux", {prefix=false}).found,
    "direct lookup must not reuse an explicit prefix result from cache")
plugin:showModel(prefix_model); flush(); screenshot("shortened-prefix")
assert(plugin.viewer.scroll.html_body:find("approximate · shortened prefix",1,true))
local prefix_id = prefix_model.suggestions[1].model.senses[1].id
plugin.viewer:onLink("dpd:similar/1/sense/" .. prefix_id); flush()
assert(plugin.viewer.navigation:current().suggestions[1].expanded[prefix_id])
plugin.viewer:close()
-- The real wrapper must preserve normal-dictionary fallback, without doing a
-- prefix range query, even after the explicit DPD lookup populated its cache.
dictionary:onLookupWord("bhikkhux", false, {}, selected)
assert(not plugin.viewer and normal_calls == 1)
normal_calls = 0
local function callback() callback_calls=callback_calls+1 end
dictionary:onLookupWord("pacchima", false, {}, selected, nil, callback); flush()
assert(plugin.viewer and normal_calls==0)
plugin.viewer:onLink("dpd:normal"); flush()
assert(not plugin.viewer and normal_calls==1 and callback_calls==0, "fallback transfers selection ownership")
assert(#pending_clears==0 and clear_calls==0, "transfer must not clear the dictionary's selection")
dictionary:onLookupWord("not_a_pali_word_123", false, {}, selected); assert(normal_calls==2)
dictionary:onLookupWord("pacchima", false, {}, selected, nil, callback); flush()
plugin.viewer:close(); assert(callback_calls==1)
assert(#pending_clears==1 and clear_calls==0, "selection cleanup must be delayed")
pending_clears[1](); assert(clear_calls==1)
local wrapped = dictionary.onLookupWord
plugin:onSuspend(); assert(not plugin.db and not plugin.lookup)
dictionary:onLookupWord("pacchima", false, {}, selected); flush()
assert(plugin.viewer and plugin.db and dictionary.onLookupWord==wrapped)
plugin:closeDatabase()
plugin.settings.db_path="/tmp/dpd-does-not-exist.db"
dictionary:onLookupWord("pacchima", false, {}, selected); assert(normal_calls==3 and not plugin.db)
plugin.settings.db_path=path
dictionary:onLookupWord("pacchima", false, {}, selected); flush(); assert(plugin.viewer)
plugin:onCloseDocument(); assert(dictionary.onLookupWord==original and not plugin.db)
assert(not pcall(plugin.ensureLookup, plugin) and not plugin.db, "a stopped plugin must not reopen the database")
plugin.settings.direct_lookup=false; plugin:syncDirectMode()
dictionary:onLookupWord("pacchima", false, {}, selected); assert(normal_calls==4)
UIManager.scheduleIn = schedule
db:close()
print("PASS: real KOReader popup rendering, delta links, detail expansion, Back icon/button/scroll, direct mode and lifecycle at font " .. font_size)
