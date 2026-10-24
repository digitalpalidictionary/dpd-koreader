-- Run using KOReader's LuaJIT from its extracted desktop directory.
-- SDL_VIDEODRIVER=dummy ./luajit <plugin>/tools/check_channels.lua <plugin> <db> [screenshots]
require("setupkoenv")
local root, path = assert(arg[1]), assert(arg[2])
package.path = root .. "/?.lua;" .. package.path
local DB = require("dpd/db")
local Lookup = require("dpd/lookup")
local Render = require("ui/dpd_render")
local Navigation = require("dpd/navigation")
local Popup = require("dpd/popup")
local db = DB.new(path)
local lookup = Lookup.new(db)
local single = lookup:get("indakhile")
assert(single.single_suggestion and single.query == "indakhile")
assert(single.suggestions[1].query == "indakhīle" and #single.suggestions[1].model.senses == 2)
assert(#single.suggestions[1].attestations == 2)
local single_count = db.query_count
assert(lookup:get("indakhile").single_suggestion and db.query_count == single_count)
assert(lookup:get("avaharissāmā").single_suggestion)
assert(not lookup:get("saṃmantayitvā").single_suggestion)
assert(not lookup:get("indakhile", {approximate=false}).found)
local rescued = lookup:get("vanditva")
assert(rescued.single_suggestion and #rescued.suggestions == 1)
assert(rescued.suggestions[1].query == "vanditvā" and rescued.suggestions[1].model.senses[1].id == 66262)
assert(#rescued.variants == 1 and #rescued.suggestions[1].attestations > 0)
assert(Lookup.directHit(rescued))
local context_only = lookup:get("uyyokhajja")
assert(context_only.found and Lookup.isVariantOnly(context_only) and not Lookup.directHit(context_only))
-- Expectations pinned to official mobile v0.4.20260926, schema 7.
for _, case in ipairs({
    {"Buddha","buddha"}, {"Sace","sace"}, {"Nārada","nārada"}, {"Kaccāyana","kaccāyana"},
    {"saŋ","saṃ"}, {"dhammā","dhammā"}, {"ānanda","ānanda"},
    {"dham­ma","dhamma"},
    {"bhikkhave’ti","bhikkhaveti"}, {"yo’dha","yodha"}, {"tass’eva","tasseva"},
    {"akaṭa-anudhammena","akaṭaanudhammena"}, {"akaṇha-asukkaṃ","akaṇhaasukkaṃ"}, {"DN1-13","DN1-13"},
}) do
    local value = lookup:get(case[1])
    assert(value.found and value.query == case[2],case[1])
    assert(value.original == case[1] and #value.suggestions == 0,case[1])
end
assert(#lookup:get("Sace").senses == 1 and #lookup:get("Sace").abbrev_other == 1)
assert(#lookup:get("Nārada").senses == 2 and #lookup:get("Nārada").abbrev_other > 0)
local spelling = lookup:get("hotī")
assert(spelling.query == "hotī" and spelling.references[1].target == "hotīti")
assert(#spelling.references[1].model.senses > 0 and #spelling.references[1].model.deconstructions > 0)
assert(#lookup:get("sajjasīti").references[1].model.deconstructions > 0)
assert(lookup:get("di").references[1].model.found,"abbreviation-only spelling target must resolve")
assert(lookup:get("loc").abbrev.meaning == "locative case")
assert(#lookup:get("dī").abbrev_other > 0)
local roots = lookup:get("√har")
assert(#roots.roots == 4 and roots.roots[2].root == "√har 2")
assert(roots.roots[2].root_meaning == "take, seize" and lookup:get("akkh").found)
assert(#lookup:get("dhammaṃ").grammar == 9 and #lookup:get("dhammā").grammar == 28)
assert(#lookup:get("kā").grammar == 19 and #lookup:get("kā").variants == 3)
assert(lookup:headword("dhamma").found and lookup:headword("buddha").found)
assert(lookup:headword("buddha 1").senses[1].id == 48511)
assert(lookup:detail(60749).phonetic == "ṃ > m")
assert(lookup:detail(61939).commentary:find("saṃvid'āvahāro",1,true))
assert(lookup:detail(10432).root_base == "√har + a > hara")
local many = lookup:get("nnāṭṭā")
assert(many.matched_via == "fuzzy" and #many.suggestions == 20 and many.suggestion_total == 29)
local all_many = lookup:more(many)
assert(#all_many.suggestions == 29 and #many.suggestions == 20)
assert(#lookup:more(all_many).suggestions == 29)
local dead_reference = lookup:get("middhī",{approximate=false}).references[1]
assert(dead_reference.target == "atthassamiddhī" and dead_reference.status == "missing")
assert(not lookup:get("monk",{approximate=false}).found,"EPD is not an automatic hit")
-- Corrections are content even without target definitions; available targets
-- still add exact navigation (including abbreviation-only di→dī).
local spelling_records = db:query("SELECT lookup_key FROM lookup WHERE spelling != ''")
assert(#spelling_records == 544)
local resolved, unavailable = 0,0
for _, row in ipairs(spelling_records) do
    local value = lookup:get(row.lookup_key,{approximate=false})
    assert(value.found and Lookup.directHit(value), row.lookup_key .. ': correction must be a hit')
    local selection = lookup:get(row.lookup_key, Popup.selection_options)
    assert(Popup.route(selection) == "dpd" and #selection.suggestions == 0, row.lookup_key .. ': correction replaced')
    local html = Render.render(selection, Navigation.new(selection):current())
    assert(html:find("Incorrect spelling of ",1,true), row.lookup_key .. ': correction hidden')
    assert(not html:find("Referenced DPD entry is unavailable",1,true), row.lookup_key .. ': correction marked unavailable')
    for _, reference in ipairs(value.references) do
        if reference.model then assert(reference.model.found);resolved=resolved+1
        else assert(reference.status);unavailable=unavailable+1 end
    end
end
-- Pinned to official mobile v0.4.20260926, schema 7.
assert(resolved == 496 and unavailable == 48, resolved .. " resolved, " .. unavailable .. " unavailable")
print("PASS: official channels, exact aliases, capitalized aggregation, all 544 spelling records ("
    .. resolved .. " resolved, " .. unavailable .. " unavailable), and 29 ranked forms")

G_defaults = require("luadefaults"):open()
G_reader_settings = require("luasettings"):wrap({})
local Device = require("device")
require("document/canvascontext"):init(Device)
require("ui/bidi").setup()
local UIManager = require("ui/uimanager")
local Viewer = require("ui/dpd_viewer")
-- Scripted taps follow rebuilds at once; check_learning covers the rebuild guard.
Viewer.link_guard_s = 0
local font_size = tonumber(os.getenv("DPD_TEST_FONT_SIZE")) or 16
local function flush() UIManager:_checkTasks();UIManager:_repaint() end
local function screenshot(name) if arg[3] then Device.screen.bb:writePNG(arg[3] .. "/" .. name .. ".png") end end
local function popup(value)
    local viewer = Viewer:new{model=value,lookup=lookup,font_size=font_size}
    UIManager:show(viewer);flush();return viewer
end
local function tap(viewer,uri) viewer:onLink(uri);flush() end
for _, word in ipairs({"bhikkhunābhinandati","jālante","appampī","sūdāni","middhī"}) do
    local correction_view = popup(lookup:get(word, Popup.selection_options))
    assert(correction_view.scroll.html_body:find("Incorrect spelling of ",1,true),word)
    assert(not correction_view.scroll.html_body:find("Referenced DPD entry is unavailable",1,true),word)
    assert(not correction_view.scroll.html_body:find("No DPD entry for “",1,true),word)
    if word == "sūdāni" then
        tap(correction_view,"dpd:variants-toggle")
        assert(correction_view.scroll.html_body:find("tisahassāni sūdāni",1,true))
    end
    screenshot("correction-" .. word)
    correction_view:close();flush()
end
local function tapRendered(viewer,uri)
    local box = viewer.scroll.htmlbox_widget
    local page = box.document:openPage(box.page_number)
    local links = page:getPageLinks();page:close()
    local target
    for _, link in ipairs(links) do if link.uri == uri then target=link;break end end
    assert(target,"MuPDF must retain the control: " .. uri)
    local Geom = require("ui/geometry")
    assert(box:onTapText(nil,{pos=Geom:new{x=box.dimen.x+(target.x0+target.x1)/2,
        y=box.dimen.y+(target.y0+target.y1)/2,w=0,h=0}}))
    flush()
end
local rescued_view = popup(rescued)
assert(rescued_view.scroll.html_body:find("vanditva → vanditvā</p>",1,true))
assert(not rescued_view.scroll.html_body:find("dpd:suggestion/",1,true))
tap(rescued_view,"dpd:variants-toggle")
assert(rescued_view.scroll.html_body:find("BJT · VV",1,true))
tap(rescued_view,"dpd:similar/1/sense/66262")
assert(rescued_view.navigation:current().suggestions[1].expanded[66262])
screenshot("variant-only-rescue");rescued_view:close()
local context_view = popup(context_only)
assert(context_view.navigation:current().variants_open)
context_view:close()
for _, word in ipairs({"Buddha","saṁ","dhammā","dham­ma"}) do
    local quiet_view = popup(lookup:get(word))
    assert(not quiet_view.scroll.html_body:find("Selected:",1,true),word)
    quiet_view:close()
end
local grammar_view = popup(lookup:get("saṃvidāvahāro"))
local before = db.query_count
tap(grammar_view,"dpd:grammar-sense/1")
assert(db.query_count == before,"an exact known grammar lemma must use zero queries")
assert(grammar_view.navigation:current().model.query == "saṃvidāvahāra")
grammar_view:back();flush()
assert(grammar_view.navigation:current().model.query == "saṃvidāvahāro")
grammar_view:close()
for _, word in ipairs({"kāṭṭa","nāṭṭa"}) do
    local fresh = Lookup.new(db)
    before = db.query_count
    local value = fresh:get(word)
    assert(#value.suggestions == 20 and db.query_count-before <= 8,"suggestion page batching: " .. word)
end
local single_transferred
local single_view = Viewer:new{model=single,lookup=lookup,font_size=font_size,
    normal_callback=function(word) single_transferred=word end}
UIManager:show(single_view);flush()
assert(single_view.window[1][1].title == "indakhile")
assert(single_view.scroll.html_body:find("indakhile → indakhīle</p>",1,true))
assert(single_view.scroll.html_body:find("variant reading (CST VIN1) · +1 more",1,true))
assert(not single_view.scroll.html_body:find("indakhile (ka.)",1,true))
local attestation_queries = db.query_count
tapRendered(single_view,"dpd:similar/1/attestations-toggle")
assert(single_view.scroll.html_body:find("CST VIN1: “indakhile (ka.)”",1,true))
assert(db.query_count == attestation_queries,"showing fetched source notes needs no query")
screenshot("single-attested-sources")
tapRendered(single_view,"dpd:similar/1/attestations-toggle")
assert(not single_view.scroll.html_body:find('class="similar"',1,true))
assert(not single_view.scroll.html_body:find("dpd:suggestion/1",1,true))
screenshot("single-attested-variant")
-- Tap a real MuPDF control in the flattened body.
local box=single_view.scroll.htmlbox_widget
local page=box.document:openPage(1)
local links=page:getPageLinks();page:close()
local target
for _,link in ipairs(links) do if link.uri == "dpd:similar/1/sense/13724" then target=link;break end end
assert(target,"flattened sense controls must survive MuPDF layout")
local Geom=require("ui/geometry")
assert(box:onTapText(nil,{pos=Geom:new{x=box.dimen.x+(target.x0+target.x1)/2,
    y=box.dimen.y+(target.y0+target.y1)/2,w=0,h=0}}))
flush();assert(single_view.navigation:current().suggestions[1].expanded[13724])
single_view.scroll:scrollToRatio(1)
local single_ratio=single_view:ratio()
tap(single_view,"dpd:similar/1/grammar-sense/1")
assert(single_view.navigation:current().model.found)
single_view:back();flush()
assert(single_view.navigation:current().model.query == "indakhile")
assert(single_view:ratio() == single_ratio)
assert(single_view.navigation:current().suggestions[1].expanded[13724])
screenshot("single-attested-variant-back")
-- The fixed button below the entry, tapped through the viewer as a finger would.
local button = assert(single_view.action_buttons["dpd:normal"].dimen)
assert(single_view:handleEvent(require("ui/event"):new("Gesture",{ges="tap",time=require("ui/time").now(),
    pos=require("ui/geometry"):new{x=button.x+button.w/2,y=button.y+button.h/2}})))
flush();assert(single_transferred == "indakhile")
local plain_view=popup(lookup:get("avaharissāmā"))
assert(plain_view.scroll.html_body:find("avaharissāmā → avaharissāma · similar form",1,true))
assert(not plain_view.scroll.html_body:find("dpd:suggestion/1",1,true))
screenshot("single-similar-form");plain_view:close()
local viewer = popup(spelling)
local parent = viewer.navigation:current()
assert(viewer.scroll.html_body:gsub("<[^>]+>", ""):find("hoti + iti",1,true))
screenshot("spelling-reference")
tap(viewer,"dpd:reference/1/analysis/1")
assert(not parent.references[1].analyses[1])
viewer.scroll:scrollToRatio(1)
local ratio = viewer:ratio()
tap(viewer,"dpd:reference/1")
assert(viewer.navigation:current().model.query == "hotīti")
viewer:back();flush()
assert(viewer:ratio() == ratio and not parent.references[1].analyses[1])
viewer:close()

-- Fit the bundled text, not the eight unbundled parses. At larger fonts a
-- hidden bundle still counts as its four original parses.
local dhammassa = lookup:get("dhammassa")
local bundled = Render.mergeParses(dhammassa.grammar)
assert(#dhammassa.grammar == 8 and #bundled == 2 and bundled[2].count == 4)
viewer = popup(dhammassa)
local grammar_html = viewer.scroll.html_body
assert(grammar_html:find(Render.escape(bundled[1].parse .. " of "),1,true))
if grammar_html:find('dpd:grammar-sense/' .. bundled[2].index .. '"',1,true) then
    assert(not grammar_html:find("dpd:grammar-toggle",1,true))
else
    assert(grammar_html:find("+4 parses",1,true))
    tap(viewer,"dpd:grammar-toggle")
    assert(viewer.scroll.html_body:find('dpd:grammar-sense/' .. bundled[2].index .. '"',1,true))
    tap(viewer,"dpd:grammar-toggle")
    assert(viewer.scroll.html_body == grammar_html)
end
screenshot("bundled-grammar-fit");viewer:close()

local ka = lookup:get("kā")
viewer = popup(ka)
assert(not viewer.scroll.html_body:find("dpd:grammar-sense/17",1,true))
tap(viewer,"dpd:grammar-toggle")
-- Opened, each part of speech and headword is one line linking its first parse:
-- the last of kā's 19 parses (ki) is reachable through parse 17.
local merged = Render.mergeParses(ka.grammar)
assert(#ka.grammar == 19 and #merged == 5 and merged[5].headword == "ki" and merged[5].index == 17)
for _, line in ipairs(merged) do
    assert(viewer.scroll.html_body:find('dpd:grammar-sense/' .. line.index .. '"',1,true), line.headword)
end
assert(viewer.scroll.html_body:find("fem nom sg; fem nom/acc pl of ",1,true))
tap(viewer,"dpd:variants-toggle")
assert(viewer.scroll.html_body:find("CST · PV",1,true))
screenshot("complete-grammar-variants")
tap(viewer,"dpd:grammar-sense/1")
assert(viewer.navigation:current().model.found)
viewer:back();flush()
assert(viewer.navigation:current().grammar_open and viewer.navigation:current().variants_open)
viewer:close()

viewer = popup(many)
parent = viewer.navigation:current()
-- The first two similar forms start open, the rest collapsed.
assert(parent.suggestions[2].open and not parent.suggestions[3].open)
viewer.scroll:scrollToRatio(.5)
local previous_page = viewer.scroll.htmlbox_widget.page_number
tap(viewer,"dpd:more")
assert(#parent.model.suggestions == 29)
assert(parent.suggestions[1].open and not parent.suggestions[21].open)
assert(not viewer.scroll.html_body:find("Show more",1,true))
assert(viewer.scroll.htmlbox_widget.page_number == previous_page)
ratio=viewer:ratio()
tap(viewer,"dpd:suggestion/29")
viewer:back();flush()
assert(#viewer.navigation:current().model.suggestions == 29 and viewer:ratio() == ratio)
viewer:close()

for _, case in ipairs({{"loc","locative case","structured-abbreviation"},
    {"√har","√har 2","numbered-roots"},{"dī","CST","source-abbreviation"}}) do
    viewer=popup(lookup:get(case[1]));assert(viewer.scroll.html_body:find(case[2],1,true))
    screenshot(case[3]);viewer:close()
end
viewer=popup(lookup:get("sammantayitvā"));tap(viewer,"dpd:sense/60749")
assert(viewer.scroll.html_body:find("ṃ &gt; m",1,true));screenshot("phonetic-explanation");viewer:close()
viewer=popup(lookup:get("saṃvidāvahāro"));tap(viewer,"dpd:sense/61939")
assert(viewer.scroll.html_body:find("<b>saṃvid&#39;āvahāro</b>",1,true));screenshot("construction-commentary");viewer:close()
-- Normal-dictionary transfer uses the selected spelling, not a resolved alias.
local transferred
viewer=Viewer:new{model=lookup:get("akaṭa-anudhammena"),lookup=lookup,font_size=font_size,
    normal_callback=function(word)transferred=word end}
UIManager:show(viewer);flush();tap(viewer,"dpd:normal")
assert(transferred == "akaṭa-anudhammena")
db:close()
print("PASS: native single-candidate view, attestation, grammar/variants, references, pagination and Back/scroll at font "..font_size)
