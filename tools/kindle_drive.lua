-- Long-presses the device test book's words inside a running KOReader, the
-- way a finger does: KOReader's own word selection under a glyph, then the
-- dictionary lookup DPD intercepts, with real painting and e-ink refresh.
-- Run by tools/kindle_check.py through the HTTP inspector:
--   curl http://127.0.0.1:8080/koreader/globals/dofile/"/path/to/kindle_drive.lua"/
-- It returns at once and works through the cases on KOReader's scheduler,
-- writing results.tsv and one screenshot per case to an out/ folder beside
-- this file, then a line "DONE".
--
-- Then it times what the long-presses leave out: the Vocabulary builder's
-- save on long-press (off, first save, already saved), Search other
-- dictionaries and Other dictionaries (with the Sanskrit fallback) in all
-- eight dictionaries, and a long Monier-Williams article. Everything else
-- runs with the Vocabulary builder off; its setting is restored afterwards and
-- the cards this run added are deleted. Nothing is added to Recent lookups
-- beyond the long-presses' own.
local here = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") or "."
local out_dir = here .. "/out"
local book = rawget(_G, "DPD_DRIVE_BOOK") or "/mnt/us/documents/dpd-test-book.epub"
local Device = require("device")
local Geom = require("ui/geometry")
local UIManager = require("ui/uimanager")
local ReaderUI = require("apps/reader/readerui")
local DataStorage = require("datastorage")
local SQ3 = require("lua-ljsqlite3/init")
local lfs = require("libs/libkoreader-lfs")
local time = require("ui/time")

-- find: text located in the book; hold: character offset of the held glyph;
-- selects: the word KOReader selects; route: dpd or dictionary; query: what
-- DPD looked up; via: DPD's matched_via, when it matters.
local cases = {
    { name = "senses", find = "pacchima", hold = 3, selects = "pacchima", route = "dpd", query = "pacchima" },
    { name = "inflected", find = "pacchimassa", hold = 4, selects = "pacchimassa", route = "dpd",
        query = "pacchimassa" },
    { name = "compound", find = "vajjakammappabhedanti", hold = 6, selects = "vajjakammappabhedanti",
        route = "dpd", query = "vajjakammappabhedanti" },
    { name = "niggahita-alias", find = "saṁ", hold = 1, selects = "saṁ", route = "dpd", query = "saṃ" },
    { name = "attested", find = "indakhile", hold = 3, selects = "indakhile", route = "dpd", query = "indakhile" },
    { name = "apostrophe", find = "bhikkhave’ti", hold = 3, selects = "bhikkhave", route = "dpd",
        query = "bhikkhave" },
    { name = "ti-fused", find = "’’tiettha", hold = 4, selects = "tiettha", route = "dpd", query = "tiettha",
        via = "ti" },
    { name = "n-before-ti", find = "moghamaññan’ti", hold = 3, selects = "moghamaññan", route = "dpd",
        query = "moghamaññan", via = "niggahita" },
    { name = "english-in", find = "’ti, in", hold = 5, selects = "in", route = "dictionary" },
    { name = "n-tilde", find = "dhammañ’ca", hold = 3, selects = "dhammañ", route = "dpd", query = "dhammañ",
        via = "niggahita" },
    { name = "long-miss", find = "kiriyākiriyatosamuṭṭhāti", hold = 6, selects = "kiriyākiriyatosamuṭṭhāti",
        route = "dpd", query = "kiriyākiriyatosamuṭṭhāti" },
    { name = "no-match", find = "dpdtestnomatch", hold = 4, selects = "dpdtestnomatch", route = "dictionary" },
}
-- Plain words DPD opens, which the Vocabulary builder saves as found.
local saving = { cases[1], cases[2], cases[3], cases[5] }
local all_dictionaries = { "dppn", "cpd", "pts", "nyanatiloka", "peu", "bhs", "mw", "apte", "wordnet" }

lfs.mkdir(out_dir)
local log = assert(io.open(out_dir .. "/results.tsv", "w"))
local function write(...)
    local fields = { ... }
    for i, field in ipairs(fields) do fields[i] = (tostring(field):gsub("[\t\n]", " ")) end
    log:write(table.concat(fields, "\t"), "\n"); log:flush()
end

local function advance(pointer, offset)
    local prefix, index = pointer:match("^(.*%.)(%d+)$")
    return prefix .. (tonumber(index) + offset)
end

local reader, plugin, document
local function clear()
    if plugin.viewer then plugin:closeViewers() end
    if reader.dictionary.dict_window then reader.dictionary.dict_window:onClose() end
    reader.highlight:clear()
    -- Such as the Vocabulary builder's "Vocabulary exists" dialog.
    local stack = UIManager._window_stack
    while #stack > 0 and stack[#stack].widget ~= reader do UIManager:close(stack[#stack].widget) end
end

-- The Vocabulary builder's settings table, which its plugin reads live.
local vocabulary = G_reader_settings:readSetting("vocabulary_builder")
local vocabulary_was = vocabulary and vocabulary.enabled
local vocabulary_db = DataStorage:getSettingsDir() .. "/vocabulary_builder.sqlite3"
local function setVocabulary(on) if vocabulary then vocabulary.enabled = on end end
local function vocabularyQuery(sql, value)
    if not lfs.attributes(vocabulary_db, "mode") then return 0 end
    local conn = SQ3.open(vocabulary_db)
    local stmt, n = conn:prepare(sql), 0
    stmt:bind(value)
    while stmt:step() do n = n + 1 end
    stmt:close(); conn:close()
    return n
end
local saved_before, title_before, snapshot_complete = {}, true, false
local function title() return reader.doc_props and reader.doc_props.display_title or "" end
local function snapshot()
    for _, case in ipairs(saving) do
        saved_before[case.find] = vocabularyQuery("SELECT word FROM vocabulary WHERE word = ?", case.find) > 0
    end
    title_before = vocabularyQuery("SELECT id FROM title WHERE name = ?", title()) > 0
    snapshot_complete = true
end
local function restore()
    setVocabulary(vocabulary_was)
    local removed = 0
    for _, case in ipairs(saving) do
        -- Only words the snapshot read as absent: a failed read leaves nil.
        if saved_before[case.find] == false and vocabularyQuery("SELECT word FROM vocabulary WHERE word = ?", case.find) > 0 then
            vocabularyQuery("DELETE FROM vocabulary WHERE word = ?", case.find)
            removed = removed + 1
        end
    end
    if not title_before then
        vocabularyQuery("DELETE FROM title WHERE name = ? AND id NOT IN "
            .. "(SELECT title_id FROM vocabulary WHERE title_id IS NOT NULL)", title())
    end
    write("INFO", "vocabulary", "restored to " .. tostring(vocabulary_was), "removed " .. removed .. " test cards")
end

local function inspect(case, held, ms, name, parts)
    local viewer = plugin.viewer
    local route = viewer and "dpd" or reader.dictionary.dict_window and "dictionary" or "none"
    local model = viewer and viewer.model or {}
    local ok = held == case.selects and route == case.route
        and (not case.query or model.query == case.query)
        and (not case.via or model.matched_via == case.via)
    Device.screen:shot(out_dir .. "/" .. (name or case.name) .. ".png")
    write(ok and "PASS" or "FAIL", name or case.name, held or "", route, tostring(model.query or ""),
        tostring(model.matched_via or ""), parts or "", string.format("%.0f", ms))
end

-- Each task does its work and returns how long to wait, then what to record.
local function hold(case, name)
    return function()
        clear()
        -- findText searches forward from the current page.
        reader.rolling:_gotoPage(1)
        local matches = document:findText(case.find, 0, 0, false, 1, false, 5, 0)
        local match = matches and matches[1]
        if not match then
            write("FAIL", name or case.name, "", "not in book", "", "", "0")
            return 0
        end
        reader.rolling:_gotoXPointer(match.start)
        UIManager:forceRePaint()
        local box = document:getScreenBoxesFromPositions(advance(match.start, case.hold),
            advance(match.start, case.hold + 1), true)[1]
        local page_position = Geom:new{ x = box.x + box.w / 2, y = box.y + box.h / 2 }
        local position = reader.view:pageToScreenTransform(document:getCurrentPage(), page_position)
        -- Word selection, then DPD's lookup and popup build (the published
        -- headline: its own lookup ms plus the rest), then painting.
        local started = time.now()
        reader.highlight:onHold(nil, { pos = position, time = started })
        local held = reader.highlight.selected_text and reader.highlight.selected_text.text
        local selected = time.now()
        reader.highlight:lookupDictWord()
        local opened = time.now()
        UIManager:forceRePaint()
        local ms = time.to_ms(time.since(started))
        local parts = string.format("select %.0f · lookup %s · popup %.0f · paint %.0f",
            time.to_ms(selected - started), plugin.viewer and plugin.viewer.lookup_ms or "-",
            time.to_ms(opened - selected), time.to_ms(time.since(opened)))
        -- The normal dictionary searches in the background; give it time to open.
        return case.route == "dictionary" and 1.5 or 1, function() inspect(case, held, ms, name, parts) end
    end
end

local function timed(fn)
    local started = time.now()
    local result = fn()
    UIManager:forceRePaint()
    return time.to_ms(time.since(started)), result
end

-- Each dictionary's first entry, ≈ when approximate, and any Sanskrit word used.
local function summary(model)
    local list = {}
    for _, group in ipairs(model and model.dictionaries and model.dictionaries.groups or {}) do
        local first = group.entries[1]
        list[#list + 1] = group.id .. ":" .. (first and ((first.approximate and "≈" or "") .. first.word) or "")
            .. (group.via and #group.via > 0 and ("<" .. table.concat(group.via, ",")) or "")
    end
    return table.concat(list, " ")
end
local function record(name, ok, word, model, ms)
    Device.screen:shot(out_dir .. "/" .. name .. ".png")
    write(ok and "PASS" or "FAIL", name, word, "dpd", tostring(model and model.query or ""), summary(model),
        string.format("%.0f", ms))
end

-- Search other dictionaries, as the menu does, without recording it.
local searched
local function search(name, word, found)
    return function()
        -- The page under the last popup is repainted before timing, as for a hold.
        clear(); UIManager:forceRePaint()
        local ms, model = timed(function()
            local model = plugin:ensureLookup():searchDictionaries(word, all_dictionaries)
            plugin:showModel(model, {})
            return model
        end)
        searched = model
        return 1, function() record(name, plugin.viewer ~= nil and model.found == found, word, model, ms) end
    end
end

-- The last search's Monier-Williams article, or its next part.
local function article(name, link)
    return function()
        local viewer, g = plugin.viewer, nil
        for i, group in ipairs(searched and searched.dictionaries.groups or {}) do
            if group.id == "mw" then g = i end
        end
        if not (viewer and g) then
            write("FAIL", name, "", "no Monier-Williams result", "", "", "0")
            return 0
        end
        local ms = timed(function() return viewer:onLink(link .. g .. "/1") end)
        local page = (viewer.navigation:current().dictionary_pages or {})[g .. "/1"]
        return 1, function()
            Device.screen:shot(out_dir .. "/" .. name .. ".png")
            write(page and page.open and "PASS" or "FAIL", name, searched.query, "dpd",
                "part " .. tostring(page and page.part), tostring(page and page.total) .. " bytes",
                string.format("%.0f", ms))
        end
    end
end

-- Other dictionaries over a DPD popup, as its button does.
local function other(name, word)
    return function()
        clear()
        plugin:showModel(plugin:getModel(word), {})
        UIManager:forceRePaint()
        local viewer = plugin.viewer
        local ms = timed(function() return viewer and viewer:onLink("dpd:dictionaries") end)
        local model = viewer and viewer.navigation:current().model
        return 1, function() record(name, model and model.dictionaries ~= nil, word, model, ms) end
    end
end

local function call(fn) return function() fn(); return 0 end end

local function plan()
    local tasks = {}
    local function add(task) tasks[#tasks + 1] = task end
    -- The long-presses, with the Vocabulary builder off as on a new install.
    -- Off before the snapshot, so a failed read can't leave lookups saving.
    add(call(function() setVocabulary(false); snapshot() end))
    for _, case in ipairs(cases) do add(hold(case)) end
    if reader.vocabbuilder and vocabulary then
        for round = 1, 3 do
            for _, case in ipairs(saving) do add(hold(case, "vocab-off-" .. case.name .. "-" .. round)) end
        end
        -- Saving needs to know which cards were already there.
        add(call(function()
            assert(snapshot_complete, "vocabulary snapshot failed; saving not timed")
            setVocabulary(true)
        end))
        for _, case in ipairs(saving) do add(hold(case, "vocab-first-" .. case.name)) end
        for round = 1, 2 do
            for _, case in ipairs(saving) do add(hold(case, "vocab-saved-" .. case.name .. "-" .. round)) end
        end
    end
    add(call(restore))
    -- All eight dictionaries; the first search is the least cached.
    add(search("search-dharma", "dharma", true))
    add(search("search-dharma-again", "dharma", true))
    add(search("search-Phala", '"Phala"', true))
    add(search("search-mahabodhi", "Mahā Bodhi", true))
    add(search("search-sariputra", "sariputra", true))
    add(search("search-miss", "qqqqzzzz", false))
    add(search("search-kr", "kṛ", true))
    add(article("article-kr-mw", "dpd:dict-entry/"))
    add(article("article-kr-mw-next", "dpd:dict-next/"))
    local chosen
    add(call(function() chosen = plugin.settings.dictionaries; plugin.settings.dictionaries = all_dictionaries end))
    add(other("other-pacchima", "pacchima"))
    add(other("other-dhamma", "dhamma"))
    add(call(function() plugin.settings.dictionaries = chosen end))
    return tasks
end

local function run(tasks, index)
    local task = tasks[index]
    if not task then
        clear(); UIManager:forceRePaint()
        write("DONE"); log:close()
        return
    end
    local ok, wait, after = pcall(task)
    if not ok then write("FAIL", "task " .. index, "", wait, "", "", "0"); wait, after = 0, nil end
    UIManager:scheduleIn(wait or 0, function()
        if after then
            local done, err = pcall(after)
            if not done then write("FAIL", "task " .. index, "", err, "", "", "0") end
        end
        run(tasks, index + 1)
    end)
end

local function start(tries)
    tries = tries or 0
    reader = ReaderUI.instance
    plugin = reader and reader.dpd
    if not (reader and reader.document and reader.document.file == book) then
        return write("FAIL", "open", book, "test book is not open")
    end
    if not plugin then return write("FAIL", "plugin", "", "DPD plugin not loaded") end
    document = reader.document
    -- A book just opened or replaced is still laying out; wait until it can be searched.
    reader.rolling:_gotoPage(1)
    local ready = document:findText(cases[1].find, 0, 0, false, 1, false, 1, 0)
    if not (ready and ready[1]) then
        if tries < 30 then return UIManager:scheduleIn(1, function() start(tries + 1) end) end
        return write("FAIL", "open", book, "test book never became searchable")
    end
    local ok, version = pcall(require, "dpd/version")
    write("INFO", "version", tostring(ok and version or "?"), "direct", tostring(plugin.settings.direct_lookup))
    write("INFO", "vocabulary", reader.vocabbuilder and ("on " .. tostring(vocabulary_was)) or "plugin off",
        "dictionaries " .. table.concat(plugin:enabledDictionaries(), ","))
    if not plugin.settings.direct_lookup then
        return write("FAIL", "direct", "", "turn on DPD on word long-press")
    end
    run(plan(), 1)
end

if ReaderUI.instance and ReaderUI.instance.document and ReaderUI.instance.document.file == book then
    UIManager:nextTick(start)
else
    if ReaderUI.instance then ReaderUI.instance:switchDocument(book) else ReaderUI:showReader(book) end
    UIManager:scheduleIn(5, start)
end
return "started"
