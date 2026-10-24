-- Run from the extracted desktop KOReader directory with a disposable config:
-- KO_MULTIUSER=1 XDG_CONFIG_HOME=<temporary directory> SDL_VIDEODRIVER=dummy \
-- ./luajit <plugin>/tools/check_input.lua <plugin> <dpd-mobile.db> [screenshots]
-- Exercises the "Look up a word" dialog with KOReader's real InputDialog.
require("setupkoenv")
local root, path = assert(arg[1]), assert(arg[2])
package.path = root .. "/?.lua;" .. package.path
G_defaults = require("luadefaults"):open()
G_reader_settings = require("luasettings"):wrap({})
local Device = require("device")
require("document/canvascontext"):init(Device)
require("ui/bidi").setup()
local UIManager = require("ui/uimanager")
local Input = require("ui/dpd_input")
local function flush() UIManager:_checkTasks(); UIManager:_repaint() end
local function screenshot(name)
    if arg[3] then Device.screen.bb:writePNG(arg[3] .. "/" .. name .. ".png") end
end
local function isShown(widget)
    for _, window in ipairs(UIManager._window_stack) do if window.widget == widget then return true end end
    return false
end
local function button(dialog, text)
    for _, row in ipairs(dialog.buttons_layout or (dialog.button_table and dialog.button_table.buttons_layout) or {}) do
        for _, b in ipairs(row) do if b.text == text then return b end end
    end
    for _, row in ipairs(dialog.buttons or {}) do
        for _, b in ipairs(row) do if b.text == text then return b end end
    end
    for _, child in ipairs(dialog) do
        local found = button(child, text)
        if found then return found end
    end
end

-- Velthuis input converts on submission, only when turned on.
local settings = { velthuis = true }
local looked_up
local dialog = Input.show{ settings = settings, on_lookup = function(text) looked_up = text end }
flush()
dialog:setInputText("   ")
button(dialog, "Look up").callback(); flush()
assert(isShown(dialog) and looked_up == nil, "empty submission retains the dialog")
local notice = UIManager._window_stack[#UIManager._window_stack].widget
assert(notice.text:find("word or ID number",1,true))
UIManager:close(notice); flush()
dialog:setInputText("~naa.na")
flush()
screenshot("input-velthuis")
button(dialog, "Look up").callback()
flush()
assert(looked_up == "ñāṇa", tostring(looked_up))
assert(not isShown(dialog), "dialog closed after lookup")

settings.velthuis = false
dialog = Input.show{ settings = settings, on_lookup = function(text) looked_up = text end }
flush()
dialog:setInputText("aardvark")
button(dialog, "Look up").callback()
flush()
assert(looked_up == "aardvark")
-- Recent lists earlier lookups, newest first; choosing one runs it again.
local History = require("dpd/history")
local history = History.new(settings)
history:add("dhamma"); history:add("buddha"); history:add("dhamma")
local chosen, chosen_mode
dialog = Input.show{ settings = settings, history = history,
    on_lookup = function(text, mode) chosen, chosen_mode = text, mode end }
flush()
button(dialog, "Recent").callback()
flush()
assert(not isShown(dialog), "dialog replaced by the recent list")
local menu = UIManager._window_stack[#UIManager._window_stack].widget
assert(menu.item_table[1].text == "dhamma" and menu.item_table[2].text == "buddha" and #menu.item_table == 2)
screenshot("input-recent")
menu:onMenuSelect(menu.item_table[2])
flush()
assert(chosen == "buddha" and chosen_mode == "pali")
assert(not isShown(menu), "recent list closed")
-- Dismissing Recent restores the exact draft; selecting an item does not.
local returned, returns = nil, 0
dialog = Input.show{settings=settings,history=history,input="~naa.na",
    on_lookup=function() error("dismissing Recent must not look up a word") end,
    on_reopen=function(new) returned=new; returns=returns+1 end}
flush()
button(dialog,"Recent").callback(); flush()
menu = UIManager._window_stack[#UIManager._window_stack].widget
menu:onClose(); flush()
assert(returned and isShown(returned) and returned:getInputText() == "~naa.na" and returned.mode == "pali")
assert(returns == 1)
button(returned,"Cancel").callback(); flush()
history:clear()
assert(Input.showRecent{ history = history, on_lookup = function() end } == nil)
flush()
notice = UIManager._window_stack[#UIManager._window_stack].widget
UIManager:close(notice); flush()
dialog = Input.show{settings=settings,history=history,input="unfinished",on_lookup=function() end}
flush()
button(dialog,"Recent").callback(); flush()
assert(isShown(dialog) and dialog:getInputText() == "unfinished", "empty Recent retains the draft")
notice = UIManager._window_stack[#UIManager._window_stack].widget
UIManager:close(notice); button(dialog,"Cancel").callback(); flush()
-- Suggestions: nothing until typing pauses, results for the latest text only,
-- a tap looks the word up, and closing cancels pending work.
local ffiutil = require("ffi/util")
local function pause() ffiutil.usleep(math.floor((Input.idle_s + 0.15) * 1e6)); flush() end
local DB = require("dpd/db")
local Suggest = require("dpd/suggest")
-- SQL-backed autocomplete regression: real English entries come after more
-- than 200 empty Pāḷi rows, and after a next letter crowded with more than
-- the capped slices hold. The portable suggestion spec uses a query double,
-- which cannot check what SQLite's LIMITs keep.
do
    local SQ3 = require("lua-ljsqlite3/init")
    local fixture_path = os.tmpname()
    os.remove(fixture_path)
    local conn = SQ3.open(fixture_path)
    conn:exec([[CREATE TABLE lookup(lookup_key TEXT PRIMARY KEY, headwords TEXT, deconstructor TEXT, epd TEXT);
CREATE TABLE dpd_headwords(id INTEGER PRIMARY KEY, lemma_1 TEXT, pos TEXT, meaning_1 TEXT, meaning_2 TEXT);
BEGIN;]])
    local insert = conn:prepare("INSERT INTO lookup VALUES(?, '', '', ?)")
    local function add(key, epd)
        insert:reset():clearbind():bind(key, epd):step()
    end
    for i = 1, 220 do
        -- Both empty representations must be ignored before the candidate cap.
        add(string.format("meda%03d", i), i % 2 == 0 and "" or "[]")
        add(string.format("méa%03d", i), "")
    end
    conn:exec("INSERT INTO lookup VALUES('meda000', '', '', NULL)")
    add("meadow", '[1]')
    add("meditate", '[1]')
    add("meditation", '[1,2]')
    add("meditated upon", '[1,2,3]')
    add("médical school", '[1,2]')
    -- Lowercase non-ASCII keys are Pāḷi forms: skipped by the key filter.
    add("médical", '[1,2]')
    -- 450 Pāḷi forms under sama… fill the general slice; same and the
    -- per-letter slices still reach it, but not an English key past them.
    for i = 1, 450 do add(string.format("sama%03d", i), "") end
    add("samazz", '[1]')
    add("same", '[1]')
    add("sameness", '[1]')
    insert:close(); conn:exec("COMMIT"); conn:close()
    local fixture = DB.new(fixture_path)
    local suggestions = Suggest.new(fixture)
    local function texts(prefix)
        local words = {}
        for _, item in ipairs(suggestions:complete(prefix, "english")) do words[#words + 1] = item.text end
        return table.concat(words, "|")
    end
    assert(texts("med") == "meditation|meditate|meditated upon",
        "Three-character English prefixes must reach entries beyond 200 non-English keys and retain ranking")
    assert(texts("meditate") == "meditate|meditated upon", "The exact key must rank ahead of a longer phrase")
    assert(texts("m") == "meadow" and texts("me") == "meadow",
        "One- and two-character prefixes must retain the cheap sample and its useful matches")
    assert(texts("mé") == "médical school", "English keys with diacritics and a space stay suggestible")
    assert(texts("sam") == "same|sameness", "A next letter crowded with Pāḷi forms must not hide same")
    assert(texts("samaz") == "samazz", "A key past the capped slices appears once the prefix narrows")
    assert(texts("none") == "", "A genuine miss must still return no suggestions")
    local queries = fixture.query_count
    assert(texts("med") ~= "" and fixture.query_count == queries, "Repeated English prefixes must use the cache")
    fixture:close(); os.remove(fixture_path)
    print("PASS: SQL-backed English autocomplete, capped slices past crowded prefixes and letters, short/Unicode prefixes, ranking, misses and caching")
end
local db = DB.new(path)
local suggester = Suggest.new(db)
for _, prefix in ipairs({ "pat", "par", "med", "vir", "vac", "pac", "sam" }) do
    assert(#suggester:complete(prefix, "english") > 0, "Official English suggestions for " .. prefix)
end
assert(suggester:complete("sam", "english")[1].text == "same" and suggester:complete("par", "english")[1].text == "part",
    "Crowded Pāḷi prefixes still rank their English words first")
-- Follow the plugin's actual manual-dialog callback through showId and byId.
local DPD = dofile(root .. "/main.lua")
local plugin = setmetatable({ db = db, lookup = require("dpd/lookup").new(db), settings = {}, ui = {} }, { __index = DPD })
local id_model
function plugin:showModel(model) id_model = model; return true end
function plugin:showLookup() error("a valid typed ID should not fall back to word lookup") end
plugin:inputLookup()
dialog = plugin.input_dialog
flush()
dialog:setInputText("34626")
button(dialog, "Look up").callback(); flush()
assert(id_model and id_model.senses[1].id == 34626 and id_model.senses[1].lemma_1 == "dhamma 1.01")
assert(not isShown(dialog), "ID submission closed the dialog")
-- Follow the real pencil gesture through the ID route to a real InputDialog.
do
    local editor=setmetatable({db=db,lookup=require("dpd/lookup").new(db),settings={font_size=16},ui={}},
        {__index=DPD})
    local Event,Geom,time=require("ui/event"),require("ui/geometry"),require("ui/time")
    for _,gesture in ipairs({"tap","hold"}) do
        editor:lookupInput("34626","pali","  34626  ");flush()
        local viewer=assert(editor.viewer)
        local d=assert(viewer.edit_button.dimen)
        UIManager:sendEvent(Event:new("Gesture",{ges=gesture,
            pos=Geom:new{x=d.x+d.w/2,y=d.y+d.h/2},time=time.now()}))
        flush();flush()
        local input=assert(editor.input_dialog)
        assert(not viewer.closed and isShown(input), "the edited popup stays under the editor")
        assert(input:getInputText()==(gesture=="tap" and "  34626  " or "dhamma 1.01"),
            "ID pencil must preserve the typed draft on tap and edit the lemma on hold")
        assert(input.mode=="pali")
        button(input,"Cancel").callback();flush()
        assert(not viewer.closed and editor.viewer==viewer, "Cancel returns to the edited popup")
        editor:closeViewers();flush()
    end
end
-- The real history confirmation widgets preserve data on Cancel/Back.
plugin:toggleHistory(); flush()
local confirm = UIManager._window_stack[#UIManager._window_stack].widget
assert(confirm.ok_text == "Turn off" and #plugin:getHistory():list() > 0)
button(confirm,"Cancel").callback(); flush()
assert(plugin:getHistory():enabled() and #plugin:getHistory():list() > 0)
plugin:toggleHistory(); flush()
confirm = UIManager._window_stack[#UIManager._window_stack].widget
button(confirm,"Turn off").callback(); flush()
assert(not plugin:getHistory():enabled() and #plugin:getHistory():list() == 0)
plugin:toggleHistory()
plugin:getHistory():add("dhamma")
plugin:clearHistory(); flush()
confirm = UIManager._window_stack[#UIManager._window_stack].widget
confirm:onClose(); flush()
assert(#plugin:getHistory():list() == 1, "Back cancels Clear")
plugin:clearHistory(); flush()
confirm = UIManager._window_stack[#UIManager._window_stack].widget
button(confirm,"Clear").callback(); flush()
assert(plugin:getHistory():enabled() and #plugin:getHistory():list() == 0)
notice = UIManager._window_stack[#UIManager._window_stack].widget
UIManager:close(notice); flush()
-- Manual Pāḷi and English misses reopen the original draft through a real
-- rendered MuPDF link and the plugin's input callback.
local recover = setmetatable({db=db,lookup=require("dpd/lookup").new(db),
    settings={font_size=16,velthuis=true},ui={}}, {__index=DPD})
local Event, Geom, time = require("ui/event"), require("ui/geometry"), require("ui/time")
for _, trial in ipairs({{mode="pali",draft=".mzzzzzzzzzzz"},{mode="english",draft="  zzzzzzzzzzz  "}}) do
    recover:inputLookup(false,trial.draft,trial.mode); flush()
    dialog = recover.input_dialog
    button(dialog,"Look up").callback(); flush()
    local miss = assert(recover.viewer)
    miss.link_guard_s = 0
    assert(not miss.model.found and isShown(miss))
    local box = miss.scroll.htmlbox_widget
    local page = box.document:openPage(box.page_number)
    local links = page:getPageLinks(); page:close()
    local edit
    for _, link in ipairs(links) do if link.uri == "dpd:edit-search" then edit=link; break end end
    assert(edit,"miss card has an Edit search link")
    screenshot("input-miss-" .. trial.mode)
    assert(miss:handleEvent(Event:new("Gesture",{ges="tap",time=time.now(),
        pos=Geom:new{x=box.dimen.x+(edit.x0+edit.x1)/2,y=box.dimen.y+(edit.y0+edit.y1)/2}})))
    flush()
    dialog = recover.input_dialog
    assert(not miss.closed and isShown(dialog) and dialog:getInputText() == trial.draft and dialog.mode == trial.mode)
    assert(#recover:getHistory():list() == 0,"misses are not recorded")
    button(dialog,"Cancel").callback(); flush()
    assert(not miss.closed and recover.viewer == miss, "Cancel returns to the miss")
    recover:closeViewers(); flush()
end
-- Every niggahīta spelling and decomposed input complete like ṃ.
local function joined(items)
    local out = {}
    for _, item in ipairs(items) do out[#out + 1] = item.text end
    return table.concat(out, ",")
end
for _, forms in ipairs({ { "saṃ", "saṁ", "sam\204\163" }, { "dhammaṃ", "dhammaṁ", "dhammaŋ" },
    { "dhamma", "“dhamma,”", "dham\194\173ma", "dham’ma" } }) do
    local expected = joined(Suggest.new(db):complete(forms[1]))
    assert(expected ~= "", forms[1])
    for i = 2, #forms do assert(joined(Suggest.new(db):complete(forms[i])) == expected, forms[i]) end
end
local calls, typing_during_query = {}, nil
settings.velthuis = true
dialog = Input.show{ settings = settings, history = history,
    on_lookup = function(text, mode) chosen, chosen_mode = text, mode end,
    suggest = function(text, mode)
        calls[#calls + 1] = text
        if typing_during_query then typing_during_query(); typing_during_query = nil end
        return suggester:complete(text, mode)
    end }
flush()
local area = dialog.suggestion_area
local area_height = area:getSize().h
local input = dialog._input_widget
input:addChars("d"); input:addChars("h"); flush()
assert(#calls == 0, "no query before the pause")
input:addChars("a"); input:addChars("m"); pause()
assert(#calls == 1 and calls[1] == "dham", table.concat(calls, ","))
local table_widget = area[1]
assert(table_widget.buttons_layout and table_widget.buttons_layout[1][1].text == "dhamma", "dhamma first")
assert(area:getSize().h == area_height, "the row keeps its height")
screenshot("input-suggestions-dham")
-- Text typed while a query runs makes its result stale: it is dropped and
-- the newer text is queried after the next pause.
typing_during_query = function() input:addChars("m") end
input:addChars("m"); pause()
assert(area[1] == table_widget, "stale result dropped")
pause()
assert(calls[#calls] == "dhammm", calls[#calls])
-- Velthuis applies before suggesting.
input:delChar(); input:delChar(); input:delChar(); input:addChars(".m"); pause()
assert(calls[#calls] == "dhaṃ", calls[#calls])
-- Tapping a suggestion looks it up.
input:delChar(); input:delChar(); input:addChars("mma"); pause()
area[1].buttons_layout[1][1].callback()
flush()
assert(chosen == "dhamma" and chosen_mode == "pali" and not isShown(dialog))
-- Closing while a query is pending cancels it.
local before = #calls
dialog = Input.show{ settings = settings, on_lookup = function() end,
    suggest = function(text) calls[#calls + 1] = text; return {} end }
flush()
dialog._input_widget:addChars("bu")
UIManager:close(dialog); flush(); pause()
assert(#calls == before, "closed dialog ran no query")
-- So does cancel(), which the plugin calls when it closes the database.
dialog = Input.show{ settings = settings, on_lookup = function() end,
    suggest = function(text) calls[#calls + 1] = text; return {} end }
flush()
dialog._input_widget:addChars("bu")
dialog.cancel(); pause()
assert(#calls == before, "cancelled dialog ran no query")
UIManager:close(dialog); flush()
-- English mode: the switch reopens the dialog with the same text, English
-- suggestions, no Velthuis, and the mode reaches the lookup and is remembered.
local reopened
dialog = Input.show{ settings = settings, on_lookup = function(text, mode) chosen, chosen_mode = text, mode end,
    suggest = function(text, mode) calls[#calls + 1] = mode .. ":" .. text; return suggester:complete(text, mode) end,
    on_reopen = function(new) reopened = new end }
flush()
dialog._input_widget:addChars("medit")
button(dialog, "English").callback()
flush()
assert(reopened and reopened.mode == "english" and reopened:getInputText() == "medit" and settings.lookup_mode == "english")
assert(not isShown(dialog), "Pāḷi dialog closed")
pause()
-- The Pāḷi dialog's pending query was cancelled; the reopened dialog
-- suggests for the text it carried over, in English.
assert(#calls == before + 1 and calls[#calls] == "english:medit", calls[#calls])
reopened._input_widget:addChars("a"); pause()
assert(calls[#calls] == "english:medita", calls[#calls])
local offered = {}
for _, row in ipairs(reopened.suggestion_area[1].buttons_layout) do
    for _, b in ipairs(row) do offered[b.text] = true end
end
assert(offered.meditation, "meditation offered")
screenshot("input-english")
reopened._input_widget:addChars("ti.m"); flush()
button(reopened, "Look up").callback(); flush()
assert(chosen == "meditati.m" and chosen_mode == "english", chosen)
settings.lookup_mode = nil
-- Regression for English "sam": exercise the plugin callback, typing pause,
-- rendered suggestion buttons and selection, rather than only the SQL result.
dialog = Input.show{ settings = {}, mode = "english",
    suggest = function(text, mode) return plugin:suggest(text, mode) end,
    on_lookup = function(text, mode) chosen, chosen_mode = text, mode end }
flush()
for _, letter in ipairs({ "s", "a", "m" }) do
    dialog._input_widget:addChars(letter); pause()
end
assert(dialog:getInputText() == "sam" and dialog.mode == "english")
assert(button(dialog, "same"), "Typing sam in the English dialog must visibly offer same")
screenshot("input-english-sam")
dialog._input_widget:addChars("e"); pause()
assert(button(dialog, "same") and button(dialog, "sameness"), "Typing same must offer same and sameness")
button(dialog, "same").callback(); flush()
assert(chosen == "same" and chosen_mode == "english" and not isShown(dialog),
    "Selecting same must submit an English lookup and close the dialog")
print("PASS: typing sam(e) through the English dialog renders same (and sameness); tapping same submits English")
-- Searching the other dictionaries, from its menu item, with the real search
-- and popup: no suggestion queries, Sanskrit Velthuis, exact Sanskrit and
-- proper-name headwords, typed punctuation kept, DPD over the search and
-- Back, the pencil, a miss.
local search = setmetatable({ db = db, lookup = require("dpd/lookup").new(db),
    settings = { font_size = 16, velthuis = true, lookup_mode = "english", dictionaries_off = {} }, ui = {} },
    { __index = DPD })
local suggested = 0
search.suggest = function() suggested = suggested + 1; return {} end
local function group(id)
    for _, g in ipairs(search.viewer.model.dictionaries.groups) do if g.id == id then return g end end
end
local function exact(id, word)
    local g = assert(group(id), id .. " has entries")
    for _, e in ipairs(g.entries) do if e.word == word and not e.approximate then return g end end
    error(id .. " has no exact " .. word)
end
local function searchFor(text)
    dialog = assert(search.input_dialog, "dictionary search dialog")
    assert(dialog.mode == "dictionaries" and not dialog.suggestion_area)
    dialog:setInputText(text); flush()
    button(dialog, "Look up").callback(); flush()
    return assert(search.viewer, "a popup for " .. text)
end
search:inputLookup(false, nil, "dictionaries"); flush()
dialog = search.input_dialog
dialog._input_widget:addChars('"saariputra'); pause()
assert(suggested == 0, "no suggestion queries while searching dictionaries")
screenshot("dictionaries-input")
button(dialog, "Look up").callback(); flush()
local popup = assert(search.viewer)
assert(popup.model.query == "śāriputra" and popup.model.found)
exact("mw", "śāriputra"); exact("bhs", "śāriputra")
screenshot("dictionaries-sariputra")
popup:onLink("dpd:dpd-lookup"); flush()
assert(#popup.navigation.stack == 2 and not popup.navigation:current().model.dictionary_search, "DPD over the search")
screenshot("dictionaries-dpd")
popup:back(); flush()
assert(#popup.navigation.stack == 1 and popup.navigation:current().model.dictionary_search, "Back returns to the search")
assert(popup.edit_button, "the search has a pencil")
popup.edit_button.callback(); flush()
assert(not popup.closed and search.input_dialog and search.input_dialog.mode == "dictionaries"
    and search.input_dialog:getInputText() == '"saariputra', "the pencil restores the typed draft")
local edited = popup
popup = searchFor("Mahā Bodhi")
assert(edited.closed and #search.viewers == 1, "the submitted search replaces the edited popup")
assert(exact("dppn", "Mahā Bodhi").total == 3, "all three DPPN entries")
for _, typed in ipairs({ { "Accayasutta (Akodhanasutta)", "dppn" }, { "e.g.", "wordnet" } }) do
    search:inputLookup(false, nil, "dictionaries"); flush()
    popup = searchFor(typed[1])
    assert(popup.model.query == typed[1], "the title keeps " .. typed[1])
    exact(typed[2], typed[1])
end
search:inputLookup(false, nil, "dictionaries"); flush()
popup = searchFor("Śāriputra")
exact("mw", "śāriputra")
-- Apte's neuter nominative, also behind quotes and a capital (the key limit).
for _, typed in ipairs({ "phala", '"Phala"' }) do
    search:inputLookup(false, nil, "dictionaries"); flush()
    popup = searchFor(typed)
    exact("apte", "phalaṃ"); exact("mw", "phala")
end
search:inputLookup(false, nil, "dictionaries"); flush()
popup = searchFor("Ḹ")
exact("mw", "ḹ"); exact("apte", "ḹ")
search:inputLookup(false, nil, "dictionaries"); flush()
popup = searchFor("dharma")
exact("mw", "dharma"); exact("apte", "dharmaḥ"); exact("bhs", "dharma")
screenshot("dictionaries-dharma")
search:inputLookup(false, nil, "dictionaries"); flush()
popup = searchFor("qqqqzzzz")
assert(not popup.model.found and isShown(popup), "a miss still opens its popup")
assert(not popup.scroll.html_body:find("No DPD entry", 1, true), "the miss is the dictionaries', not DPD's")
screenshot("dictionaries-miss")
do
    local box = popup.scroll.htmlbox_widget
    local page = box.document:openPage(box.page_number)
    local links = page:getPageLinks(); page:close()
    local edit
    for _, link in ipairs(links) do if link.uri == "dpd:edit-search" then edit = link end end
    assert(edit, "the miss offers Edit search")
end
popup:onLink("dpd:edit-search"); flush()
assert(not popup.closed and search.input_dialog.mode == "dictionaries"
    and search.input_dialog:getInputText() == "qqqqzzzz", "Edit search restores the draft in this mode")
UIManager:close(search.input_dialog); flush()
assert(not popup.closed and search.viewer == popup, "closing the editor returns to the miss")
search:closeViewers(); flush()
local recorded = search:getHistory():list()
assert(recorded[1].query == "dharma" and recorded[1].mode == "dictionaries", "found searches are recent")
assert(search.settings.lookup_mode == "english", "the remembered lookup mode is unchanged")

-- Literal fallbacks are trimmed and NFC-normalized by the lookup, so those
-- equivalent drafts must also move one Recent item instead of duplicating it.
for _, sample in ipairs({ { " dharma ", "dharma" }, { " Śāriputra ", "Śāriputra" } }) do
    search:inputLookup(false, nil, "dictionaries"); flush()
    popup = searchFor(sample[1])
    assert(popup.model.found and popup.model.query == sample[2])
    local count = 0
    for _, item in ipairs(search:getHistory():list()) do
        if item.query == sample[2] and item.mode == "dictionaries" then
            count = count + 1
            assert(item.draft == nil, "an equivalent dictionary draft needs no fallback")
        end
    end
    assert(count == 1, "whitespace/NFC variants share one Recent item")
    search:closeViewers(); flush()
end

-- Recent repeats the prepared query and its literal fallback, even after
-- settings are reloaded or Velthuis is changed. WordNet has vacuum, not vacūm.
search:inputLookup(false, nil, "dictionaries"); flush()
popup = searchFor("vacuum")
assert(popup.model.query == "vacūm" and popup.model.found)
local vacuum_id = exact("wordnet", "vacuum").entries[1].id
search:closeViewers(); flush()
search:inputLookup(false, nil, "dictionaries"); flush()
popup = searchFor(" vacuum ")
assert(exact("wordnet", "vacuum").entries[1].id == vacuum_id)
recorded = search:getHistory():list()
assert(recorded[1].query == "vacūm" and recorded[1].draft == "vacuum", "retain the literal fallback in Recent")
local vacuum_count = 0
for _, item in ipairs(recorded) do if item.query == "vacūm" then vacuum_count = vacuum_count + 1 end end
assert(vacuum_count == 1, "whitespace around a distinct literal fallback does not duplicate Recent")
search:closeViewers(); flush()
local history_path = os.tmpname()
os.remove(history_path)
local stored = require("luasettings"):open(history_path)
stored:saveSetting("dpd", search.settings); stored:flush()
search.settings = require("luasettings"):open(history_path):readSetting("dpd")
search.history = nil
os.remove(history_path)
for _, velthuis in ipairs({ false, true }) do
    search.settings.velthuis = velthuis
    search:inputLookup(true); flush()
    local recent = assert(search.input_dialog)
    recent.item_table[1].callback(); flush()
    assert(search.viewer.model.query == "vacūm" and search.viewer.model.found)
    assert(exact("wordnet", "vacuum").entries[1].id == vacuum_id, "Recent keeps the original WordNet result")
    screenshot("dictionaries-vacuum-recent")
    search:closeViewers(); flush()
end

-- This real 101-byte compound ends in a multibyte niggahita. Shortening it
-- to 100 bytes used to turn its two exact analyses into a different lookup.
local long = "muttakarīsacammaaṭṭhinhārukhaṇḍakheḷasiṅghāṇikālohitappabhutinānākuṇapajātaṃ"
assert(#long == 101)
search:lookupInput(long, "pali", long); flush()
assert(search.viewer.model.found and #search.viewer.model.deconstructions == 2)
assert(search:getHistory():list()[1].query == long, "Recent stores the complete long query")
search:closeViewers(); flush()
search:inputLookup(true); flush()
local recent = assert(search.input_dialog)
assert(recent.item_table[1].text == long, "the menu receives the complete label")
screenshot("input-recent-long")
recent.item_table[1].callback(); flush()
assert(search.viewer.model.query == long and search.viewer.model.found
    and #search.viewer.model.deconstructions == 2, "Recent replays the same long compound analyses")
search:closeViewers(); flush()
local long_headword = assert(db:senses({8324})[1]).lemma_1
assert(#long_headword > 100)
search:lookupInput(long_headword, "pali", long_headword); flush()
assert(search.viewer.model.found and search.viewer.model.senses[1].id == 8324)
assert(search:getHistory():list()[1].query == long_headword, "Recent stores the complete long headword")
search:closeViewers(); flush()
search:inputLookup(true); flush()
search.input_dialog.item_table[1].callback(); flush()
assert(search.viewer.model.query == long_headword and search.viewer.model.found
    and search.viewer.model.senses[1].id == 8324, "Recent replays the same long headword")
search:closeViewers(); flush()
print("PASS: Recent deduplicates equivalent drafts, preserves dictionary literal fallbacks across settings reload/Velthuis changes and complete long compounds/headwords")
db:close()

-- An upgrade must keep saved dictionary choices before the first search.
local Dictionaries = require("dpd/dictionaries")
local reader_settings = G_reader_settings
for _, case in ipairs({
    { saved = { dictionaries = { "mw" } }, enabled = { "mw" } },
    { saved = { dictionaries = {} }, enabled = {} },
    { saved = { dictionaries = { "mw" }, dictionaries_off = { "pts" } },
        enabled = { "dppn", "cpd", "nyanatiloka", "peu", "bhs", "mw", "apte", "wordnet" } },
    { saved = { dictionaries = { "mw" }, dictionaries_off = {} }, enabled = Dictionaries.order },
}) do
    case.saved.db_path = path
    G_reader_settings = require("luasettings"):wrap({ dpd = case.saved })
    local upgraded = DPD:new{ path = root, ui = { menu = { registerToMainMenu = function() end } } }
    assert(upgraded.settings.dictionaries == nil, "remove the old enabled list")
    assert(table.concat(Dictionaries.enabled(Dictionaries.order, upgraded.settings.dictionaries_off), ",")
        == table.concat(case.enabled, ","), "preserve all nine snapshot choices, including PTS")
    local found = upgraded:ensureLookup():searchDictionaries("śāriputra", upgraded:enabledDictionaries())
    assert(found.found == (#case.enabled > 0), "an upgrade retains the saved MW search")
    upgraded:onCloseDocument()
end
G_reader_settings = reader_settings
print("PASS: native initialization migrates saved dictionaries, retaining MW search, PTS exclusion, empty selections and existing disabled settings")
print("PASS: empty-input retention, ID routing, draft restoration and miss editing, history confirmations, opt-in Velthuis, pasted-input suggestions (ṁ/ŋ/decomposed as ṃ), English mode and searching the other dictionaries")
