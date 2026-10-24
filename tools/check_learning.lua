-- Run from the extracted desktop KOReader directory with a disposable config:
-- KO_MULTIUSER=1 XDG_CONFIG_HOME=<temporary directory> SDL_VIDEODRIVER=dummy \
-- ./luajit <plugin>/tools/check_learning.lua <plugin> <dpd-mobile.db> "$DPD_BOOK" [screenshots]
-- Use a fresh temporary EPUB copy with no .sdr for each run; see
-- docs/KOREADER_RUNBOOK.md for the DPD_BOOK setup.
-- Exercises real MuPDF link rectangles and hold/release gesture dispatch.
require("setupkoenv")
local root, path = assert(arg[1]), assert(arg[2])
package.path = root .. "/?.lua;" .. package.path
G_defaults = require("luadefaults"):open()
G_reader_settings = require("luasettings"):wrap({dpd={db_path=path,direct_lookup=false,font_size=16}})
local Device = require("device")
require("document/canvascontext"):init(Device)
require("ui/bidi").setup()
local UIManager = require("ui/uimanager")
local Event = require("ui/event")
local Geom = require("ui/geometry")
local time = require("ui/time")
local Lookup = require("dpd/lookup")
local DB = require("dpd/db")
local Viewer = require("ui/dpd_viewer")
-- Scripted taps follow rebuilds at once; the rebuild guard has its own step.
Viewer.link_guard_s = 0
local font_size = tonumber(os.getenv("DPD_TEST_FONT_SIZE")) or 16
local function flush() UIManager:_checkTasks(); UIManager:_repaint() end
local function rss(label)
    local status = io.open("/proc/self/status", "r")
    if not status then return end
    local contents = status:read("*a")
    status:close()
    local kib = contents:match("VmRSS:%s*(%d+)%s+kB")
    if kib then print("DESKTOP_RSS depth=" .. label .. " kib=" .. kib) end
end
local function screenshot(name)
    if arg[4] then Device.screen.bb:writePNG(arg[4] .. "/" .. name .. ".png") end
end
local function isShown(widget)
    for _,window in ipairs(UIManager._window_stack) do if window.widget == widget then return true end end
    return false
end
-- Stacked above: KOReader puts non-modal windows beneath every modal one.
local function isAbove(widget, below)
    local at = {}
    for i,window in ipairs(UIManager._window_stack) do at[window.widget] = i end
    return at[widget] ~= nil and at[below] ~= nil and at[widget] > at[below]
end
-- Taps the centre of a fixed button below the entry, through the viewer.
local function tapButton(viewer, uri)
    local button = assert(viewer.action_buttons[uri], "no button: " .. uri)
    local d = assert(button.dimen, "button not drawn: " .. uri)
    assert(viewer:handleEvent(Event:new("Gesture", {ges="tap",pos=Geom:new{x=d.x+d.w/2,y=d.y+d.h/2},
        time=time.now()})), uri)
    flush()
end
local function pageData(box, page_number)
    local page = box.document:openPage(page_number)
    local links, words = page:getPageLinks(), page:getPageText()
    page:close()
    return links, words
end
local function showPage(viewer, number)
    viewer.scroll:scrollToRatio((number - .9) / viewer.scroll.htmlbox_widget.page_count)
    flush()
end
local function tapRendered(viewer, uri)
    local box = viewer.scroll.htmlbox_widget
    for number = 1, box.page_count do
        local links = pageData(box, number)
        for _, link in ipairs(links) do
            if link.uri == uri then
                showPage(viewer, number)
                local position = Geom:new{x=box.dimen.x+(link.x0+link.x1)/2,
                    y=box.dimen.y+(link.y0+link.y1)/2}
                assert(viewer:handleEvent(Event:new("Gesture", {ges="tap",pos=position,time=time.now()})), uri)
                flush()
                return
            end
        end
    end
    error("MuPDF did not retain the rendered control: " .. uri)
end
local pan_checked = setmetatable({}, {__mode="k"})
local function holdRendered(viewer, word, required_link)
    local box = viewer.scroll.htmlbox_widget
    for number = 1, box.page_count do
        local links, lines = pageData(box, number)
        for _, line in ipairs(lines) do
            for _, glyph in ipairs(line) do
                if type(glyph) == "table" and glyph.word == word then
                    local x, y = (glyph.x0+glyph.x1)/2, (glyph.y0+glyph.y1)/2
                    local linked = not required_link
                    if required_link then
                        for _, link in ipairs(links) do
                            if link.uri == required_link and x >= link.x0 and x <= link.x1
                                and y >= link.y0 and y <= link.y1 then linked = true end
                        end
                    end
                    if linked then
                        showPage(viewer, number)
                        local position = Geom:new{x=box.dimen.x+x,y=box.dimen.y+y}
                        assert(viewer:handleEvent(Event:new("Gesture", {ges="hold",pos=position,time=time.now()})))
                        assert(box.highlight_text == word and box.highlight_rects,
                            "Holding a rendered glyph must select the actual popup text")
                        if not pan_checked[viewer] then
                            assert(viewer:handleEvent(Event:new("Gesture", {ges="hold_pan",pos=position,time=time.now()})))
                            pan_checked[viewer]=true
                        end
                        assert(viewer:handleEvent(Event:new("Gesture", {ges="hold_release",pos=position,time=time.now()})))
                        flush()
                        return box
                    end
                end
            end
        end
    end
    error("No selectable MuPDF word rectangle: " .. word)
end

local db = DB.new(path)
local lookup = Lookup.new(db)
for _, input in ipairs({"dhamma 1.01","Dhamma 1.01","DHAMMA 1.01"}) do
    local value = lookup:get(input)
    assert(value.found and #value.senses == 1 and value.senses[1].id == 34626, input)
end
for _, input in ipairs({"hotī”ti","HOTĪ”TI","hotī”Ti",'HOTĪ"TI'}) do
    local value = lookup:get(input)
    assert(value.found and value.query == "hotīti" and #value.suggestions == 0, input)
end
assert(lookup:detail(20403).sanskrit == "karmin [kṛ]")
assert(lookup:detail(20403).root_sign == "o")
assert(lookup:detail(316).cognate == "cuss")
assert(lookup:detail(295).non_ia == "erukku, erikku, erke (Tamil)")
local numbered_root = assert(lookup:target("√har 2", "root"))
assert(#numbered_root.roots == 1 and numbered_root.roots[1].root == "√har 2")
assert(not lookup:target("unavailable-dpd-target", "form"))
assert(not lookup:target("48511", "form"))
local function popup(model)
    local viewer = Viewer:new{model=model,lookup=lookup,font_size=font_size}
    UIManager:show(viewer); flush(); return viewer
end
local function targetIndex(detail, text)
    for index, target in ipairs(detail.targets or {}) do
        if target.text == text then return index end
    end
    error("Missing exact detail target: " .. text)
end

local viewer = popup(lookup:get("buddhānussati"))
tapRendered(viewer, "dpd:sense/48579")
local frame = viewer.navigation:current()
assert(frame.expanded[48579])
assert(viewer.scroll.html_body:find("Sanskrit",1,true)
    and viewer.scroll.html_body:find("buddha + anusmṛti",1,true))
local construction = targetIndex(frame.details[48579], "anussati")
tapRendered(viewer, "dpd:detail-target/48579/" .. construction)
assert(viewer.navigation:current().model.query == "anussati")
viewer:back(); flush()
assert(viewer.navigation:current() == frame and frame.expanded[48579])
screenshot("curated-construction-links")
viewer:close(); flush()

for _, case in ipairs({{"akkuṭṭha",316,"Cognates","cuss"},
    {"akka 2",295,"Non-Indo-Aryan origin","erukku, erikku, erke (Tamil)"},
    {"kammī",20403,"Root sign","karmin [kṛ]"}}) do
    viewer=popup(lookup:headword(case[1]))
    tapRendered(viewer,"dpd:sense/" .. case[2])
    assert(viewer.scroll.html_body:find(case[3],1,true)
        and viewer.scroll.html_body:find(case[4],1,true),case[1])
    viewer:close();flush()
end

local compound = lookup:get("vajjakammappabhedanti")
viewer = popup(compound)
local analysis_index, part_index
for i, analysis in ipairs(compound.deconstructions) do
    for p, word in ipairs(analysis.parts or {}) do
        if word == "kammi" and analysis.unique[p] then analysis_index,part_index=i,p end
    end
end
assert(analysis_index and part_index)
local path_prefix = "dpd:component-detail/" .. analysis_index .. "/" .. part_index .. "/"
-- kammi's analysis starts closed.
tapRendered(viewer, "dpd:analysis/" .. analysis_index)
tapRendered(viewer, "dpd:component-sense/" .. analysis_index .. "/" .. part_index .. "/20403")
frame = viewer.navigation:current()
local inline = assert(viewer.navigation:componentDetail(analysis_index,part_index,20403))
assert(inline.sanskrit == "karmin [kṛ]" and not frame.expanded[20403])
assert(viewer.scroll.html_body:find("karmin [kṛ]",1,true))
tapRendered(viewer, path_prefix .. "detail-target/20403/" .. targetIndex(inline, "√kar"))
assert(#viewer.navigation:current().model.roots == 1
    and viewer.navigation:current().model.roots[1].root == "√kar")
viewer:back(); flush()
assert(viewer.navigation:current() == frame
    and viewer.navigation:componentDetail(analysis_index,part_index,20403) == inline)
screenshot("inline-component-etymology")
viewer:close(); flush()

-- Referenced result controls must change the referenced owner, not the root.
viewer = popup(lookup:get("hotī"))
frame = viewer.navigation:current()
local child = assert(frame.references[1])
local a, p, id
for i, analysis in ipairs(child.model.deconstructions or {}) do
    if child.analyses[i] then
        for j, word in ipairs(analysis.parts or {}) do
            local component = child.model.components[word]
            if analysis.unique[j] and component and component.senses[1] then
                a,p,id=i,j,component.senses[1].id; break
            end
        end
    end
    if id then break end
end
assert(id, "Reference fixture needs a real expandable component sense")
tapRendered(viewer, "dpd:reference/1/component-sense/" .. a .. "/" .. p .. "/" .. id)
assert(viewer.navigation:componentDetail(a,p,id,child))
assert(not viewer.navigation:componentDetail(a,p,id,frame))
viewer:close(); flush()

-- Family pages use exact lemma identity and retain the appended page on Back.
viewer = popup(lookup:get("dhamma 1.01"))
tapRendered(viewer, "dpd:sense/34626")
frame = viewer.navigation:current()
local groups = frame.details[34626].families
local group_index
for i, group in ipairs(groups) do
    if group.kind == "compound" and group.key == "dhamma" then group_index=i end
end
assert(group_index and groups[group_index].count == 578)
tapRendered(viewer, "dpd:detail-family/34626/" .. group_index)
local family_frame = viewer.navigation:current()
assert(family_frame.model.family.total == 578 and #family_frame.model.family.items == 20)
tapRendered(viewer, "dpd:family-more")
assert(#family_frame.model.family.items == 40)
local member_index
for i, member in ipairs(family_frame.model.family.items) do if member.available then member_index=i;break end end
assert(member_index)
local member = family_frame.model.family.items[member_index]
tapRendered(viewer, "dpd:family-member/" .. member_index)
assert(#viewer.navigation:current().model.senses == 1
    and viewer.navigation:current().model.senses[1].lemma_1 == member.lemma)
viewer:back(); flush()
assert(viewer.navigation:current() == family_frame and #family_frame.model.family.items == 40)
viewer:back(); flush()
assert(viewer.navigation:current() == frame and frame.expanded[34626])
viewer:close(); flush()

-- Paradigms open from an expanded sense, highlight the looked-up form, link
-- every form to an exact lookup and keep the parent on Back.
viewer = popup(lookup:get("dhammassa"))
frame = viewer.navigation:current()
tapRendered(viewer, "dpd:sense/34626")
assert(frame.details[34626].paradigm_kind == "Declension" and frame.details[34626].ipa_line)
assert(viewer.scroll.html_body:find("<i>IPA:</i>", 1, true))
tapRendered(viewer, "dpd:detail-paradigm/34626")
local paradigm_frame = viewer.navigation:current()
local paradigm = paradigm_frame.model.paradigm
assert(paradigm and paradigm.selected_count == 2 and #paradigm.forms == 19)
assert(viewer.scroll.html_body:find('<span class="selected">▸ dhammassa</span>', 1, true))
screenshot("paradigm-dhamma")
local dhammo
for i, form in ipairs(paradigm.forms) do if form == "dhammo" then dhammo = i end end
tapRendered(viewer, "dpd:paradigm-form/" .. dhammo)
assert(viewer.navigation:current().model.query == "dhammo" and viewer.navigation:current().model.found)
viewer:back(); flush()
assert(viewer.navigation:current() == paradigm_frame)
viewer:back(); flush()
assert(viewer.navigation:current() == frame and frame.expanded[34626])
viewer:close(); flush()
-- Wide grids are split by gender; the popup width decides how many sit side by side.
local sabba = db:sensesByLemma({"sabba 1"})[1].id
viewer = popup(lookup:paradigm(sabba, "sabbe"))
local _, tables = viewer.scroll.html_body:gsub("<table", "")
local per_row = viewer.navigation:current().paradigm_columns
assert(per_row >= 1 and tables == math.ceil(3 / math.min(3, per_row)), "sabba sections per row")
screenshot("paradigm-sabba")
viewer:close(); flush()

-- Frequency opens from an expanded sense, reads its data only then, and
-- packs editions into tables that fit the popup.
local bhikkhu = db:sensesByLemma({"bhikkhu"})[1].id
viewer = popup(lookup:get("bhikkhu"))
frame = viewer.navigation:current()
tapRendered(viewer, "dpd:sense/" .. bhikkhu)
assert(frame.details[bhikkhu].has_frequency == 1)
tapRendered(viewer, "dpd:detail-frequency/" .. bhikkhu)
local table_model = viewer.navigation:current().model.frequency
assert(table_model and #table_model.sections == 4 and table_model.sections[1].rows[1].cells.cst_m.value > 0)
local _, freq_tables = viewer.scroll.html_body:gsub('<table class="freq">', "")
assert(freq_tables >= 1 and freq_tables <= 4)
screenshot("frequency-bhikkhu")
viewer:back(); flush()
assert(viewer.navigation:current() == frame)
viewer:close(); flush()

-- Sutta information opens from an expanded sense, including one whose
-- headword is only an alias of the sutta record.
for _, case in ipairs({ { "brahmajālasutta", "sutta", "brahmajālasutta" }, { "pāṭikavagga", "vagga", "pāthikavaggapāḷi" } }) do
    local id = db:sensesByLemma({ case[1] })[1].id
    viewer = popup(lookup:get(case[1]))
    frame = viewer.navigation:current()
    tapRendered(viewer, "dpd:sense/" .. id)
    assert(frame.details[id].sutta_kind == case[2], case[1] .. " sutta link")
    tapRendered(viewer, "dpd:detail-sutta/" .. id)
    local info = viewer.navigation:current().model.sutta
    assert(info and info.records[1].name == case[3] and #info.records[1].sections >= 2, case[1] .. " sutta panel")
    screenshot("sutta-" .. case[1])
    viewer:back(); flush()
    assert(viewer.navigation:current() == frame)
    viewer:close(); flush()
end

-- Root details open from the root card and return to it on Back.
viewer = popup(lookup:get("√gam"))
frame = viewer.navigation:current()
tapRendered(viewer, "dpd:root-details/1")
local details = viewer.navigation:current().model.root_details
assert(details and #details.rows >= 7 and details.rows[2].label:match("^Bases?$"))
assert(viewer.scroll.html_body:find("bhūvādigaṇa", 1, true))
screenshot("root-details-gam")
viewer:back(); flush()
assert(viewer.navigation:current() == frame)
viewer:close(); flush()

-- ṁ display: displayed text changes, link keys do not, and ṁ input still
-- finds the ṃ entry.
viewer = Viewer:new{ model = lookup:get("saṃgha"), lookup = lookup, font_size = font_size, niggahita = "ṁ" }
UIManager:show(viewer); flush()
local body = viewer.scroll.html_body
assert(body:find("saṁgha", 1, true) and not body:gsub("<[^>]*>", ""):find("ṃ", 1, true), "text shows ṁ")
for href in body:gmatch('href="([^"]*)"') do assert(not href:find("ṁ", 1, true), "href keeps ṃ: " .. href) end
screenshot("niggahita-sangha")
viewer:close(); flush()
local typed = lookup:get("dhammaṁ")
assert(typed.found and typed.query == "dhammaṃ", tostring(typed.query))

-- Spelling suggestions only for typed lookups that miss: kamna offers kamma.
assert(#(lookup:get("kamna").spelling_suggestions or {}) == 0, "no spelling without the option")
viewer = popup(lookup:get("kamna", { spelling = true }))
frame = viewer.navigation:current()
assert(frame.model.spelling_suggestions[1].text == "kamma", tostring(frame.model.spelling_suggestions[1].text))
assert(viewer.scroll.html_body:find("Did you mean", 1, true))
screenshot("spelling-kamna")
tapRendered(viewer, "dpd:spelling/1")
assert(viewer.navigation:current().model.found and viewer.navigation:current().model.query == "kamma")
viewer:back(); flush()
assert(viewer.navigation:current() == frame)
viewer:close(); flush()
assert(#(lookup:get("dhamma", { spelling = true }).spelling_suggestions or {}) == 0, "no spelling for a hit")

-- Other dictionaries: a link at the end of a result; entries stay collapsed
-- until opened; an article shows one part at a time with Previous and Next
-- part; opening another entry closes the first; Back returns.
viewer = Viewer:new{ model = lookup:get("kamma"), lookup = lookup, font_size = font_size,
    dictionaries = { "dppn", "cpd", "nyanatiloka" } }
UIManager:show(viewer); flush()
frame = viewer.navigation:current()
assert(not viewer.scroll.html_body:find("dpd:dictionaries", 1, true))
assert(viewer.action_buttons["dpd:dictionaries"].enabled)
local started_dict = time.now()
tapButton(viewer, "dpd:dictionaries")
assert(not viewer.action_buttons["dpd:dictionaries"].enabled, "a dictionaries view offers no second search")
local dict_frame = viewer.navigation:current()
local groups = dict_frame.model.dictionaries.groups
assert(groups[1].id == "cpd" and #groups[1].entries >= 1 and groups[2].id == "nyanatiloka", groups[1] and groups[1].id)
assert(not viewer.scroll.html_body:find('class="article"', 1, true), "entries start collapsed")
screenshot("dictionaries-kamma")
local largest, largest_index = 0, 1
for e, entry in ipairs(groups[1].entries) do
    local size = db:query("SELECT length(CAST(definition_html AS BLOB)) AS n FROM dict_entries WHERE id = ?", { entry.id })[1].n
    if size > largest then largest, largest_index = size, e end
end
local key = "1/" .. largest_index
tapRendered(viewer, "dpd:dict-entry/" .. key)
local pages = dict_frame.dictionary_pages[key]
assert(pages.open and pages.part == 1 and pages.has_more, "first part of a long article")
screenshot("dictionaries-kamma-cpd")
tapRendered(viewer, "dpd:dict-next/" .. key)
pages = dict_frame.dictionary_pages[key]
assert(pages.part == 2 and pages.offset > 0)
-- The new part opens at the entry's title.
local box = viewer.scroll.htmlbox_widget
local title_seen = false
for _, link in ipairs((pageData(box, box.page_number))) do title_seen = title_seen or link.uri == "dpd:dict-entry/" .. key end
assert(title_seen, "next part starts at the entry title")
tapRendered(viewer, "dpd:dict-prev/" .. key)
pages = dict_frame.dictionary_pages[key]
assert(pages.part == 1 and pages.offset == 0)
print(string.format("DICTIONARIES kamma: open + next + previous part of a %d-byte article %.0f ms", largest,
    time.to_ms(time.since(started_dict))))
-- Opening another entry closes the first and frees its part, but keeps
-- where it was: reopening resumes that part, and Previous part still works.
tapRendered(viewer, "dpd:dict-next/" .. key)
local part2_offset = dict_frame.dictionary_pages[key].offset
tapRendered(viewer, "dpd:dict-entry/2/1")
pages = dict_frame.dictionary_pages[key]
assert(dict_frame.dictionary_pages["2/1"].open and not pages.open and not pages.html, "one article at a time")
tapRendered(viewer, "dpd:dict-entry/2/1")
assert(not dict_frame.dictionary_pages["2/1"].open and not dict_frame.dictionary_pages["2/1"].html, "collapsing frees the part")
tapRendered(viewer, "dpd:dict-entry/" .. key)
pages = dict_frame.dictionary_pages[key]
assert(pages.open and pages.part == 2 and pages.offset == part2_offset, "reopening resumes the part")
assert(viewer.scroll.html_body:find("Previous part", 1, true))
tapRendered(viewer, "dpd:dict-prev/" .. key)
pages = dict_frame.dictionary_pages[key]
assert(pages.part == 1 and pages.offset == 0, "previous part after resuming")
tapRendered(viewer, "dpd:dict-entry/" .. key)
tapRendered(viewer, "dpd:dict-entry/" .. key)
assert(dict_frame.dictionary_pages[key].part == 1, "part 1 resumes as part 1")
viewer:back(); flush()
assert(viewer.navigation:current() == frame)
viewer:close(); flush()

-- Every exact match is reachable: DPPN has 47 Tissas, read 20 at a time.
viewer = Viewer:new{ model = lookup:get("tissa"), lookup = lookup, font_size = font_size, dictionaries = { "dppn" } }
UIManager:show(viewer); flush()
tapButton(viewer, "dpd:dictionaries")
local tissa = viewer.navigation:current().model.dictionaries.groups[1]
local tissa_total = tissa.total
local tissas = db:query("SELECT count(*) AS n FROM dict_entries WHERE dict_id = 'dppn' AND word = 'Tissa'", {})[1].n
local words = {}
for _, w in ipairs(tissa.words) do words[#words + 1] = w.word .. " " .. w.count end
print("DICTIONARIES tissa: " .. table.concat(viewer.navigation:current().model.dictionaries.keys, ", ")
    .. " → " .. table.concat(words, ", "))
assert(tissa.words[1].word == "Tissa" and tissa.words[1].count == tissas and tissas > 40 and #tissa.entries == 20)
assert(viewer.scroll.html_body:find(tissa_total .. "&nbsp;entries · 20&nbsp;shown", 1, true))
tapRendered(viewer, "dpd:dict-entries/1")
tapRendered(viewer, "dpd:dict-entries/1")
assert(#tissa.entries == tissa_total and not viewer.scroll.html_body:find("dpd:dict-entries/", 1, true))
tapRendered(viewer, "dpd:dict-entry/1/" .. tissa_total)
assert(viewer.navigation:current().dictionary_pages["1/" .. tissa_total].open, "the last Tissa opens")
viewer:close(); flush()

-- The largest article, traversed to its end and back, never holds or lays
-- out more than one part.
local bibliography = db:query("SELECT id, length(CAST(definition_html AS BLOB)) AS n FROM dict_entries"
    .. " WHERE dict_id = 'cpd' ORDER BY length(definition_html) DESC LIMIT 1", {})[1]
local word = db:query("SELECT word FROM dict_entries WHERE id = ?", { bibliography.id })[1].word
viewer = Viewer:new{ model = lookup:otherDictionaries({ query = word }, { "cpd" }), lookup = lookup,
    font_size = font_size, dictionaries = { "cpd" } }
UIManager:show(viewer); flush()
local bib_frame = viewer.navigation:current()
assert(bib_frame.model.dictionaries.groups[1].entries[1].id == bibliography.id)
tapRendered(viewer, "dpd:dict-entry/1/1")
local parts, max_html, max_pages, started_bib = 1, 0, 0, time.now()
while true do
    max_html = math.max(max_html, #viewer.scroll.html_body)
    max_pages = math.max(max_pages, viewer.scroll.htmlbox_widget.page_count)
    local part = bib_frame.dictionary_pages["1/1"]
    assert(type(part.html) == "string" and #part.html < require("dpd/dictionaries").article_page * 2)
    if not part.has_more then assert(part.next_offset == bibliography.n); break end
    tapRendered(viewer, "dpd:dict-next/1/1")
    parts = parts + 1
end
tapRendered(viewer, "dpd:dict-prev/1/1")
assert(bib_frame.dictionary_pages["1/1"].part == parts - 1)
assert(max_html < 40000 and max_pages < 25, max_html .. " bytes, " .. max_pages .. " pages")
print(string.format("DICTIONARIES %s: %d bytes in %d parts, at most %d HTML bytes and %d screen pages, %.0f ms",
    word, bibliography.n, parts, max_html, max_pages, time.to_ms(time.since(started_bib))))
viewer:close(); flush()

-- Cell spans survive: Nyanatiloka's dependent-origination diagram keeps
-- "8. Craving" in the factor column under "3. Consciousness".
viewer = Viewer:new{ model = lookup:otherDictionaries({ query = "paticcasamuppāda" }, { "nyanatiloka" }),
    lookup = lookup, font_size = font_size, dictionaries = { "nyanatiloka" } }
UIManager:show(viewer); flush()
tapRendered(viewer, "dpd:dict-entry/1/1")
assert(viewer.scroll.html_body:find('rowspan="2"', 1, true))
local function wordX(target)
    box = viewer.scroll.htmlbox_widget
    for number = 1, box.page_count do
        local _, lines = pageData(box, number)
        for _, line in ipairs(lines) do
            for i, glyph in ipairs(line) do
                if type(glyph) == "table" and glyph.word == target then
                    local previous = line[i - 1]
                    return number, (type(previous) == "table" and previous.x0) or glyph.x0
                end
            end
        end
    end
end
local cp, cx = wordX("Consciousness")
local rp, rx = wordX("Craving")
assert(cx and rx and math.abs(cx - rx) < 4, "Craving under Consciousness: " .. tostring(cx) .. " " .. tostring(rx))
-- The diagram's longest words fit the popup width at every font size.
for number = 1, box.page_count do
    local _, lines = pageData(box, number)
    for _, line in ipairs(lines) do
        for _, glyph in ipairs(line) do
            assert(type(glyph) ~= "table" or not glyph.x1 or glyph.x1 <= box.dimen.w + 1,
                "table text clipped: " .. tostring(glyph.word) .. " at " .. tostring(glyph.x1))
        end
    end
end
showPage(viewer, cp)
screenshot("dictionaries-paticcasamuppada")
if rp ~= cp then showPage(viewer, rp); screenshot("dictionaries-paticcasamuppada-2") end
viewer:close(); flush()
-- No link when the release's dictionary tables are empty.
local empty = { query = function() return {} end }
local empty_lookup = setmetatable({ dictionaries = require("dpd/dictionaries").new(empty) }, { __index = lookup })
assert(not empty_lookup:hasOtherDictionaries())
-- A name DPD lacks still reaches DPPN.
viewer = Viewer:new{ model = lookup:get("Sāriputta"), lookup = lookup, font_size = font_size, dictionaries = { "dppn" } }
UIManager:show(viewer); flush()
tapButton(viewer, "dpd:dictionaries")
assert(viewer.navigation:current().model.dictionaries.groups[1].id == "dppn")
viewer:close(); flush()

-- A repeat tap in the same input batch still sees the old sense link.
viewer = popup(lookup:get("pacchima"))
frame = viewer.navigation:current()
local sense_id = frame.model.senses[1].id
local tap_box = viewer.scroll.htmlbox_widget
local sense_link
for _, link in ipairs(pageData(tap_box, tap_box.page_number)) do
    if link.uri == "dpd:sense/" .. sense_id then sense_link = link; break end
end
assert(sense_link, "sense link on the initial page")
local tap_position = Geom:new{x=tap_box.dimen.x+(sense_link.x0+sense_link.x1)/2,
    y=tap_box.dimen.y+(sense_link.y0+sense_link.y1)/2}
for _ = 1, 2 do
    viewer:handleEvent(Event:new("Gesture", {ges="tap",pos=tap_position,time=time.now()}))
end
assert(frame.expanded[sense_id], "repeat before rebuild did not close the sense")
flush()
assert(frame.expanded[sense_id], "sense remains expanded after redraw")
viewer:close(); flush()

-- The fixed buttons below the entry keep their places from view to view. A
-- second tap right after a rebuild (a bounce, or a repeat before e-ink shows
-- the new view) is ignored rather than hitting "KOReader dictionary".
do
    local normal_opened = 0
    Viewer.link_guard_s = 0.5
    viewer = Viewer:new{ model = lookup:get("gorūpānaṃ"), lookup = lookup, font_size = font_size,
        dictionaries = { "dppn", "cpd", "nyanatiloka" }, normal_callback = function() normal_opened = normal_opened + 1 end }
    UIManager:show(viewer); flush()
    local function tapAt(x, y)
        viewer:handleEvent(Event:new("Gesture", { ges = "tap", pos = Geom:new{ x = x, y = y }, time = time.now() }))
        flush()
    end
    local function settle() require("ffi/util").usleep(math.floor((Viewer.link_guard_s + .1) * 1e6)) end
    settle()
    local other = viewer.action_buttons["dpd:dictionaries"].dimen
    local before = viewer.action_buttons["dpd:normal"].dimen:copy()
    tapAt(other.x + other.w / 2, other.y + other.h / 2)
    assert(viewer.navigation:current().model.dictionaries, "Other dictionaries opened")
    local normal = viewer.action_buttons["dpd:normal"].dimen
    assert(normal.x == before.x and normal.y == before.y, "KOReader dictionary keeps its place")
    tapAt(normal.x + normal.w / 2, normal.y + normal.h / 2)
    assert(not viewer.closed and normal_opened == 0, "bounce ignored")
    settle()
    tapAt(normal.x + 3, normal.y + 3)
    assert(viewer.closed and normal_opened == 1, "a tap near the button's edge follows it")
    flush()
    Viewer.link_guard_s = 0
end

-- The title's pencil edits the lookup, as in KOReader's dictionary popup:
-- tap the popup's own text, hold the form DPD looked up. A nested result
-- edits its own query. Views without a query have no pencil.
do
    local edits = {}
    local function open()
        viewer = Viewer:new{ model = lookup:get("dhammo"), lookup = lookup, font_size = font_size,
            edit_callback = function(text, mode) edits[#edits + 1] = { text = text, mode = mode } end }
        UIManager:show(viewer); flush()
        return assert(viewer.edit_button, "no pencil")
    end
    local function press(gesture)
        local d = assert(viewer.edit_button.dimen, "pencil not drawn")
        assert(viewer:handleEvent(Event:new("Gesture", { ges = gesture, pos = Geom:new{ x = d.x + d.w / 2,
            y = d.y + d.h / 2 }, time = time.now() })), gesture)
        flush(); flush()
    end
    -- The popup stays open under the editor until a search replaces it.
    open(); press("tap")
    assert(not viewer.closed and #edits == 1 and edits[1].text == nil and edits[1].mode == "pali", "tap edits own text")
    viewer:close(); flush()
    open(); press("hold")
    assert(not viewer.closed and edits[2].text == "dhammo" and edits[2].mode == "pali", "hold edits the DPD form")
    viewer:close(); flush()
    open()
    local child = lookup:get("dhamma"); viewer.navigation:push(child, 0); viewer:update(); flush()
    press("tap")
    assert(edits[3].text == "dhamma", "a nested result edits its own query")
    viewer = Viewer:new{ model = lookup:english("good"), lookup = lookup, font_size = font_size,
        edit_callback = function() end }
    UIManager:show(viewer); flush()
    assert(viewer.edit_button, "English results are editable")
    viewer:close(); flush()
    viewer = Viewer:new{ model = lookup:rootMatrix("√gam", 1, 1), lookup = lookup,
        font_size = font_size, edit_callback = function() end }
    UIManager:show(viewer); flush()
    assert(not viewer.edit_button, "a root matrix has no query to edit")
    viewer:close(); flush()
end

-- English→Pāḷi results open a lemma's senses and page with Show more.
viewer = popup(lookup:english("good"))
frame = viewer.navigation:current()
local english = frame.model.english
assert(english.total > 20 and #english.items == 20 and english.has_more)
screenshot("english-good")
tapRendered(viewer, "dpd:english-more")
assert(#viewer.navigation:current().model.english.items == math.min(40, english.total))
tapRendered(viewer, "dpd:english-item/1")
local opened_english = viewer.navigation:current().model
assert(opened_english.found and opened_english.senses[1].lemma_1:gsub(" %d[%d.]*$", "") == english.items[1].lemma)
viewer:back(); flush()
assert(viewer.navigation:current() == frame)
viewer:close(); flush()

-- The root matrix lists categories, a row opens its headwords and a headword
-- opens by ID; Back returns through each page.
viewer = popup(lookup:get("√gam"))
frame = viewer.navigation:current()
tapRendered(viewer, "dpd:root-matrix/1")
local matrix_frame = viewer.navigation:current()
local matrix = matrix_frame.model.root_matrix
assert(matrix and matrix.groups[1].name == "verbs" and matrix.groups[1].rows[1].label == "pr" and matrix.total > 200)
screenshot("root-matrix-gam")
tapRendered(viewer, "dpd:matrix-row/1/1")
local row_frame = viewer.navigation:current()
local pr = row_frame.model.matrix_row
assert(pr and #pr.items > 40, "√gam pr row")
screenshot("root-matrix-gam-pr")
tapRendered(viewer, "dpd:matrix-item/1")
local opened = viewer.navigation:current().model
assert(opened.found and opened.senses[1].id == pr.items[1].id)
viewer:back(); flush()
assert(viewer.navigation:current() == row_frame)
viewer:back(); flush()
assert(viewer.navigation:current() == matrix_frame)
viewer:back(); flush()
assert(viewer.navigation:current() == frame)
viewer:close(); flush()

-- A single approximate result must not hide damage from its selected-form row.
local single = lookup:get("indakhile")
local damaged = {}
for key, value in pairs(single) do damaged[key]=value end
damaged.damaged={"variant readings"}
viewer=popup(damaged)
assert(viewer.scroll.html_body:find("Some DPD details could not be read. Affected data: variant readings",1,true))
viewer:close(); flush()
db:close()

-- Use the plugin's actual stack and MuPDF selection widgets. This dictionary
-- boundary records the arguments which would reach KOReader's normal lookup;
-- the existing reader/lifecycle tools exercise the real dictionary itself.
local fallback_calls, owner_closed = {}, 0
local dictionary = {onLookupWord=function(self, ...)
    fallback_calls[#fallback_calls+1]={args={...},n=select("#",...)}
    local close_callback=select(6,...)
    self.dict_window={dict_close_callback=close_callback}
    function self.dict_window:onClose()
        if self.closed then return end
        self.closed=true
        self.dict_close_callback()
    end
    return true
end}
local plugin = require("main"):new{ui={dictionary=dictionary,
    menu={registerToMainMenu=function() end}}}
rss("baseline")
assert(plugin:showLookup("buddhānussati", {close_callback=function() owner_closed=owner_closed+1 end}))
flush()
local parent = assert(plugin.viewer)
assert(parent.scroll.htmlbox_widget.highlight_text_selection and #plugin.viewers == 1)
rss("1")
tapRendered(parent, "dpd:sense/48579")
local parent_frame = parent.navigation:current()
local linked_target = targetIndex(parent_frame.details[48579], "anussati")
local selected_box = holdRendered(parent, "anussati", "dpd:detail-target/48579/" .. linked_target)
local child_viewer = assert(plugin.viewer)
assert(child_viewer ~= parent and not parent.closed and #plugin.viewers == 2)
assert(parent.navigation:current() == parent_frame and #parent.navigation.stack == 1,
    "Holding a hyperlink must select its word rather than follow the link")
assert(child_viewer.model.query == "anussati" and owner_closed == 0)
rss("2")
local saved_ratio = parent:ratio()
child_viewer:close(); flush()
assert(plugin.viewer == parent and #plugin.viewers == 1 and owner_closed == 0)
assert(parent:ratio() == saved_ratio and parent_frame.expanded[48579])
assert(not selected_box.highlight_text, "Closing the child clears only the parent's HTML selection")

-- Unknown selections and lookup errors fall back without passing book state.
parent:lookupSelection("missing-dpd-native-learning-fixture"); flush()
assert(plugin.viewer == parent and not parent.closed and #fallback_calls == 1)
local fallback = fallback_calls[#fallback_calls]
assert(fallback.n == 6 and fallback.args[1] == "missing-dpd-native-learning-fixture"
    and fallback.args[3] == nil and fallback.args[4] == nil and fallback.args[5] == nil
    and type(fallback.args[6]) == "function")
fallback.args[6](); fallback.args[6]()
local old_get_model = plugin.getModel
plugin.getModel = function() error("intentional learning lookup failure") end
parent:lookupSelection("pacchima"); flush()
plugin.getModel = old_get_model
assert(plugin.viewer == parent and not parent.closed and #fallback_calls == 2)
fallback_calls[2].args[6]()

-- Root closure cancels a complete live stack before the native DB is closed.
parent:lookupSelection("pacchima"); flush()
child_viewer=assert(plugin.viewer)
holdRendered(child_viewer,"pacchima")
local grandchild=assert(plugin.viewer)
assert(grandchild ~= child_viewer and #plugin.viewers == 3 and owner_closed == 0)
while #plugin.viewers < 8 do
    assert(plugin.viewer:lookupSelection("pacchima"))
    flush()
    if #plugin.viewers == 4 or #plugin.viewers == 8 then rss(tostring(#plugin.viewers)) end
end
local top=plugin.viewer
assert(not top:lookupSelection("pacchima"), "The protective limit must reject another child")
flush()
assert(plugin.viewer == top and #plugin.viewers == 8 and not parent.closed and owner_closed == 0,
    "The protective limit must retain the complete existing popup stack")
local limit_notice = UIManager._window_stack[#UIManager._window_stack].widget
assert(limit_notice ~= top, "The limit must show an explanation above the retained stack")
UIManager:close(limit_notice);flush()
local fallback_done=0
assert(plugin:normalFromPopup(top,"missing-dpd-native-learning-fixture",
    function() fallback_done=fallback_done+1 end))
local owned_dictionary=assert(dictionary.dict_window)
local open_viewers={}
for _,value in ipairs(plugin.viewers) do open_viewers[#open_viewers+1]=value end
local connection=assert(plugin.db)
local original_close = connection.close
connection.close = function(self)
    for _,value in ipairs(open_viewers) do assert(value.closed) end
    assert(not plugin.viewer and #plugin.viewers == 0 and owner_closed == 1
        and owned_dictionary.closed and fallback_done == 1,
        "Every popup and its selection owner must close before the database")
    return original_close(self)
end
plugin:closeDatabase(); flush()
assert(not plugin.db and not plugin.lookup and not connection.conn)
plugin:onCloseDocument(); plugin:onCloseDocument()
assert(owner_closed == 1)
rss("closed")

if arg[3] then
    -- Open the fixture through CRe and use the actual ReaderHighlight and
    -- ReaderDictionary, including the normal empty-result dictionary popup.
    local lfs = require("libs/libkoreader-lfs")
    local disabled = {}
    for entry in lfs.dir("plugins") do
        if entry:sub(-9) == ".koplugin" then disabled[entry:sub(1,-10)] = true end
    end
    G_reader_settings:saveSetting("plugins_disabled",disabled)
    G_reader_settings:saveSetting("extra_plugin_paths",{assert(root:match("^(.+)/[^/]+$"))})
    G_reader_settings:saveSetting("dpd",{db_path=path,direct_lookup=true,font_size=font_size})
    G_defaults:saveSetting("DELAY_CLEAR_HIGHLIGHT_S",0)
    local ReaderUI = require("apps/reader/readerui")
    ReaderUI:showReader(arg[3]);flush();flush()
    local reader = assert(ReaderUI.instance)
    local owner = assert(reader.dpd,"KOReader must discover the learning plugin")
    local document = reader.document
    local matches = assert(document:findText("pacchima",0,0,false,reader.view.state.page,false,100,0))
    local match = assert(matches[1])
    reader.rolling:_gotoXPointer(match.start);flush();flush()
    local boxes = document:getScreenBoxesFromPositions(match.start,match["end"],true)
    local glyph = assert(boxes[1],"CRe must locate the fixture word")
    local point = Geom:new{x=glyph.x+glyph.w/2,y=glyph.y+glyph.h/2}
    local position = reader.view:pageToScreenTransform(document:getCurrentPage(),point)
    assert(reader.highlight:onHold(nil,{pos=position}))
    local book_selection = assert(reader.highlight.selected_text)
    assert(book_selection.text == "pacchima")
    reader.highlight:lookupDictWord();flush()
    local root_viewer = assert(owner.viewer)
    local book_cleanup = 0
    local original_clear = owner.clearSelection
    owner.clearSelection = function(self,highlight,...)
        if highlight == reader.highlight then book_cleanup=book_cleanup+1 end
        return original_clear(self,highlight,...)
    end
    holdRendered(root_viewer,"pacchima")
    local selected_child = assert(owner.viewer)
    assert(selected_child ~= root_viewer and reader.highlight.selected_text == book_selection)
    selected_child:close();flush()
    assert(owner.viewer == root_viewer and reader.highlight.selected_text == book_selection and book_cleanup == 0)

    local normal = reader.dictionary
    normal.enabled_dict_names={}
    root_viewer:lookupSelection("missing-dpd-native-reader-fixture");flush()
    local normal_window=assert(normal.dict_window)
    assert(isAbove(normal_window, root_viewer), "KOReader's dictionary must open above the DPD popup")
    assert(isShown(normal_window) and normal_window.highlight == nil
        and owner.viewer == root_viewer and reader.highlight.selected_text == book_selection)
    normal_window:onClose();flush()
    assert(reader.highlight.selected_text == book_selection and book_cleanup == 0)

    -- Force the other no-result branch (installed dictionaries, fuzzy search
    -- disabled): child ownership must retain the standard result card rather
    -- than launch an unowned alternate-search InputDialog.
    normal.enabled_dict_names={"Native learning fixture"}
    normal.disable_fuzzy_search=true
    local original_sdcv = normal.startSdcv
    normal.startSdcv=function()
        return {{dict="Native learning fixture",definition="No fixture result",no_result=true,lookup_cancelled=false}}
    end
    root_viewer:lookupSelection("another-missing-dpd-native-reader-fixture");flush()
    normal_window=assert(normal.dict_window)
    assert(isShown(normal_window) and normal_window.word == "another-missing-dpd-native-reader-fixture"
        and normal_window.highlight == nil and reader.highlight.selected_text == book_selection)
    normal_window:onClose();flush()

    -- Teardown an actual DPD child with an actual normal-dictionary fallback
    -- above it. The root alone clears the selected word in the book.
    holdRendered(root_viewer,"pacchima")
    selected_child=assert(owner.viewer)
    selected_child:lookupSelection("last-missing-dpd-native-reader-fixture");flush()
    normal_window=assert(normal.dict_window)
    assert(isShown(normal_window) and owner.viewer == selected_child and book_cleanup == 0)
    local real_db=assert(owner.db)
    local real_close=real_db.close
    real_db.close=function(self)
        assert(not isShown(normal_window) and root_viewer.closed and selected_child.closed
            and not owner.viewer and book_cleanup == 1,
            "Native normal popup and DPD descendants must close before SQLite")
        return real_close(self)
    end
    owner:closeDatabase();flush()
    assert(not reader.highlight.selected_text and book_cleanup == 1)
    normal.startSdcv=original_sdcv
    reader:onClose(false);flush()
    print("PASS: real CRe book highlight, ReaderUI DPD child selection, both ReaderDictionary no-result branches, "
        .. "normal-popup teardown before SQLite and exactly one root highlight cleanup")
end
print("PASS: native etymology fields, exact construction/root targets, inline component owners, "
    .. "nested reference controls, 20-member family pages and Back, paradigm tables and form links, root details, root matrix, English→Pāḷi, ṁ display, spelling suggestions, other dictionaries (every entry, one article part at a time, cell spans), footer button hit areas and tap bounce, frequency, sutta information, "
    .. "all confirmed lookup gaps, "
    .. "real MuPDF selection/linked-word holds, retained parent popups, fallback ownership, "
    .. "and whole-stack cleanup before SQLite closure")
