local Compat = require("dpd/compat")
local DataStorage = require("datastorage")
local DB = require("dpd/db")
local VERSION = require("dpd/version")
local Diag = require("dpd/diag")
local Direct = require("dpd/direct")
local InfoMessage = require("ui/widget/infomessage")
local History = require("dpd/history")
local Lookup = require("dpd/lookup")
local PathChooser = require("ui/widget/pathchooser")
local Popup = require("dpd/popup")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local time = require("ui/time")
local util = require("util")

local DPD = WidgetContainer:extend{ name = "dpd", is_doc_only = false, max_popup_depth = 8 }
-- Warn about an unsupported KOReader once per session, not on every book.
local unsupported_warned = false
-- Say once per session, per kind of problem, why long-press fell back to the
-- normal dictionary: a damaged word must not hide a later missing database.
local database_warned = {}

local NO_DATABASE = "No DPD database found. Copy dpd-mobile.db to koreader/data/dpd/, or choose it "
    .. "under Search → Digital Pāḷi Dictionary → Choose database file."
-- DB.new's reasons the reader can act on, shown as they are; others stay generic.
local database_reasons = { "DPD database not found", "This file is not a SQLite database" }
-- A missing column means the wrong file or an older DPD release; the column
-- itself only matters in the log.
local INCOMPATIBLE = "This file isn't a DPD database this version can read. "
    .. "Choose dpd-mobile.db from a current DPD release."
-- Any other long-press failure: damaged pages or rows, or a bug. The reader
-- can't fix those from here, but must not mistake them for DPD misses.
local LOOKUP_FAILED = "DPD could not look up this word. Check Database status in the DPD menu."
local DAMAGED = "Some DPD data could not be read. Replace the database with a fresh DPD mobile download."
-- Where the reader fixes a missing, moved or wrong database file.
local CHOOSE_MENU = "Search → Digital Pāḷi Dictionary → Choose database file"
local CHOOSE = "Choose it under " .. CHOOSE_MENU .. "."
local function databaseMessage(err)
    -- assert prefixes the error with where it was raised.
    local text = tostring(err):gsub("^[^\n]-:%d+: ", "")
    if text:find(DB.read_only_message, 1, true) then return text end
    if text:find("^Choose the DPD database") then return NO_DATABASE end
    if text:find("^Incompatible DPD database") then return INCOMPATIBLE end
    if text:find("^Invalid DPD") or text:find("^Missing DPD headword")
        or text:find("ljsqlite3%[notadb%]") or text:find("ljsqlite3%[corrupt%]") then
        return DAMAGED
    end
    for _, reason in ipairs(database_reasons) do
        if text:sub(1, #reason) == reason then return text end
    end
end

-- Put DPD on the first page of Search, after KOReader's own dictionary items,
-- rather than appended at the end of the menu. KOReader keeps these order
-- tables for the whole process and lets plugins add to them (see
-- ui/plugin/insert_menu), so insert once; a user's saved menu order wins.
local function placeInSearch()
    for _, name in ipairs({ "ui/elements/filemanager_menu_order", "ui/elements/reader_menu_order" }) do
        local ok, order = pcall(require, name)
        local search = ok and type(order) == "table" and order.search
        if type(search) == "table" then
            local after
            for i, id in ipairs(search) do
                if id == "dpd" then after = nil; break end
                if id == "dictionary_lookup" or id == "dictionary_lookup_history" or id == "vocabbuilder" then
                    after = i
                end
            end
            if after then table.insert(search, after + 1, "dpd") end
        end
    end
end

function DPD:init()
    self.settings = G_reader_settings:readSetting("dpd", {})
    if self.settings.direct_lookup == nil then self.settings.direct_lookup = true end
    if self.settings.font_size == nil then self.settings.font_size = 16 end
    if not self.settings.db_path then
        local default = DataStorage:getDataDir() .. "/data/dpd/dpd-mobile.db"
        if lfs.attributes(default, "mode") == "file" then self.settings.db_path = default end
    end
    -- The header marks each KOReader session, not each opened book.
    if (self.settings.diagnostics == true) ~= Diag.enabled then Diag.setEnabled(self.settings.diagnostics) end
    local missing = Compat.missing()
    placeInSearch()
    self.ui.menu:registerToMainMenu(self)
    if #missing > 0 then
        -- Keep the menu, which explains why, but never route a lookup to DPD.
        self.unsupported = Compat.message(missing)
        Diag.log("Unsupported KOReader:", table.concat(missing, ", "))
        if not unsupported_warned then
            unsupported_warned = true
            UIManager:nextTick(function() self:message(self.unsupported) end)
        end
        return
    end
    self:registerEntryPoints()
    self:syncDirectMode()
end

function DPD:enabledDictionaries()
    return self.settings.dictionaries or require("dpd/dictionaries").defaults
end

function DPD:dictionariesMenu()
    local Dictionaries = require("dpd/dictionaries")
    local items = {}
    for _, id in ipairs(Dictionaries.order) do
        items[#items + 1] = {
            text = Dictionaries.names[id],
            -- Hold for the full title, author and size; lookups show a short name.
            help_text_func = function() return self:dictionaryDetails(id) end,
            checked_func = function()
                for _, enabled in ipairs(self:enabledDictionaries()) do if enabled == id then return true end end
                return false
            end,
            callback = function()
                local chosen, found = {}, false
                for _, enabled in ipairs(self:enabledDictionaries()) do
                    if enabled == id then found = true else chosen[#chosen + 1] = enabled end
                end
                if not found then chosen[#chosen + 1] = id end
                self.settings.dictionaries = chosen
                self:saveSettings()
            end,
        }
    end
    return { text = "Other dictionaries", sub_item_table = items }
end

-- Bibliographic details from the open database's dict_meta, else the copy
-- recorded from the tested release. A dictionary the open database lacks
-- (PTS before its first release) says so.
function DPD:dictionaryDetails(id)
    local Dictionaries = require("dpd/dictionaries")
    local fallback = Dictionaries.bibliography[id] or { Dictionaries.names[id] or id }
    local name, author, count, missing = fallback[1], fallback[2], nil, false
    if self.db then
        local ok, rows = pcall(self.db.query, self.db,
            "SELECT name, author, entry_count FROM dict_meta WHERE dict_id = ?", { id })
        if ok and rows[1] then
            name, author, count = rows[1].name or name, rows[1].author or author, tonumber(rows[1].entry_count)
        else
            missing = ok or tostring(rows):find("no such table: dict_meta", 1, true) ~= nil
        end
    end
    return name .. (author and author ~= "" and ("\n" .. author) or "")
        .. (count and ("\n" .. count .. " entries") or "")
        .. (missing and "\n\nNot in this DPD database. It comes with newer DPD releases." or "")
        .. (Dictionaries.notes[id] and ("\n\n" .. Dictionaries.notes[id]) or "")
end

function DPD:getHistory()
    self.history = self.history or History.new(self.settings or {})
    return self.history
end

function DPD:saveSettings() G_reader_settings:saveSetting("dpd", self.settings) end

function DPD:message(text, dismiss_callback)
    UIManager:show(InfoMessage:new{ text = text, dismiss_callback = dismiss_callback })
end

function DPD:showError(err, message, dismiss_callback)
    logger.warn("DPD:", err)
    Diag.log("Error:", err)
    self:message(message .. "\n\nIf it keeps failing, turn on Help → Diagnostics → Write diagnostic log in the DPD menu and include the log in a bug report.",
        dismiss_callback)
end

-- A setup problem the reader can fix shows only its fix, not the bug-report
-- advice; anything else falls back to showError with the generic text.
function DPD:showDatabaseError(err, fallback, dismiss_callback)
    local text = databaseMessage(err)
    if not text then return self:showError(err, fallback, dismiss_callback) end
    logger.warn("DPD:", err)
    Diag.log("Error:", err)
    self:message(text, dismiss_callback)
end

function DPD:ensureLookup()
    -- Plugin management stops the plugin in-session; its buttons and menu may
    -- remain until KOReader restarts, so never reopen the database after that.
    assert(not self.stopped, "Digital Pāḷi Dictionary is disabled until KOReader restarts.")
    if self.lookup then return self.lookup end
    local started = time.now()
    local db = DB.new(self.settings.db_path)
    self.db, self.lookup = db, Lookup.new(db)
    logger.dbg("DPD open ms:", time.to_ms(time.since(started)), "journal:", db.journal_mode,
        "release:", db.info.dpd_release_version)
    return self.lookup
end

function DPD:getModel(word, options)
    local original = word
    word = util.cleanupSelectedText(word or "")
    local lookup = self:ensureLookup()
    local started, count = time.now(), self.db.query_count
    local model = lookup:get(word, options)
    model.original, model.original_clean = original or word, word
    local ms = time.to_ms(time.since(started))
    logger.dbg("DPD lookup:", word, "normalized:", model.query, "via:", model.matched_via,
        "ms:", ms, "queries:", self.db.query_count - count)
    -- Handed to the next popup so its diagnostic line can total lookup and build.
    self.last_lookup_ms = ms
    return model
end

function DPD:normalLookup(word, is_sane, boxes, highlight, link, close_callback)
    local dictionary = self.ui.dictionary
    if not dictionary then return end
    if self.direct then return self.direct:handoff(word, is_sane, boxes, highlight, link, close_callback) end
    local method = dictionary.onLookupWord
    assert(type(method) == "function", "KOReader's dictionary lookup API is unavailable.")
    return method(dictionary, word, is_sane, boxes, highlight, link, close_callback)
end

-- For soak tests, called between popups (e.g. through KOReader's HTTP
-- inspector): the full collection stays out of the popup path, so it cannot
-- skew popup timings by emptying KOReader's caches.
function DPD:logSettledMemory()
    if Diag.enabled then Diag.log("Settled memory:", Diag.memory(true)) end
    return Diag.enabled
end

function DPD:clearSelection(highlight, close_callback)
    if highlight then
        local clear_id = highlight:getClearId()
        UIManager:scheduleIn(G_defaults:readSetting("DELAY_CLEAR_HIGHLIGHT_S"), function()
            highlight:clear(clear_id)
        end)
    end
    if close_callback then close_callback() end
end

function DPD:showModel(model, options)
    options = options or {}
    -- Taken before any early return, so a refused popup's time never reaches the next.
    local lookup_ms = self.last_lookup_ms
    self.last_lookup_ms = nil
    if self.stopped then return false end
    local parent = options.parent
    self.viewers = self.viewers or {}
    if parent then
        if parent.closed or self.viewer ~= parent then return false end
        if #self.viewers >= self.max_popup_depth then
            self:message("DPD popup limit reached. Close the top popup to continue.")
            return false
        end
    else
        self:closeViewers()
    end
    local viewer
    local selection_released = false
    local release_selection = function()
        if selection_released then return end
        selection_released = true
        self:clearSelection(options.highlight, options.close_callback)
    end
    local Viewer = self.viewer_class or require("ui/dpd_viewer")
    viewer = Viewer:new{
        model = model, lookup = self.lookup, lookup_ms = lookup_ms, normal_callback = options.normal_callback,
        -- Without text, the edit is of this popup's own lookup: what was selected.
        -- A child's edit replaces only the child; a view opened from an entry
        -- passes itself as the parent of its edit.
        edit_callback = options.edit_callback or function(text, mode, edit_parent, replaced)
            self:inputLookup(false, text or model.original_clean or model.query, mode, edit_parent or parent, replaced)
        end,
        release_selection_callback = release_selection,
        parent_viewer = parent,
        before_close_callback = function() self:closeChildren(viewer) end,
        selection_callback = function(word, clear_selection)
            return self:lookupFromPopup(viewer, word, clear_selection)
        end,
        font_size = self.settings.font_size, niggahita = self.settings.niggahita,
        dictionaries = self:enabledDictionaries(),
        close_callback = function(transfer_selection)
            Diag.log("Popup closed:", model.query)
            for i = #self.viewers, 1, -1 do
                if self.viewers[i] == viewer then table.remove(self.viewers, i); break end
            end
            self.viewer = self.viewers[#self.viewers]
            if not transfer_selection then
                release_selection()
            end
        end,
    }
    self.viewers[#self.viewers + 1] = viewer
    self.viewer = viewer
    Diag.log("Popup open:", model.query, "depth:", #self.viewers)
    local ok, err = pcall(UIManager.show, UIManager, viewer)
    if not ok then viewer:close(); error(err) end
    return true
end

function DPD:closeChildren(parent)
    self:closePopupFallbacks(parent)
    local index
    for i, viewer in ipairs(self.viewers or {}) do if viewer == parent then index = i; break end end
    if not index then return end
    for i = #self.viewers, index + 1, -1 do self.viewers[i]:close() end
end

function DPD:closeViewers()
    self:closePopupFallbacks()
    -- Use a snapshot: a failing owner callback must not leave this loop stuck
    -- on an already-closed viewer. Descendants release selections first.
    local viewers = {}
    for _, viewer in ipairs(self.viewers or {}) do viewers[#viewers + 1] = viewer end
    for i = #viewers, 1, -1 do viewers[i]:close() end
    self.viewers = {}
    -- Keep compatibility with owners/tests created before stack support.
    if self.viewer then self.viewer:close(); self.viewer = nil end
end

local function once(callback)
    local called = false
    return function()
        if called then return end
        called = true
        if callback then callback() end
    end
end

function DPD:lookupFromPopup(parent, word, clear_selection)
    local clear = once(clear_selection)
    if self.stopped or parent.closed or self.viewer ~= parent then clear(); return false end
    local ok, model = pcall(self.getModel, self, word, Popup.selection_options)
    if ok and Popup.route(model) == "dpd" then
        local shown, result = pcall(self.showModel, self, model, {
            parent = parent, close_callback = clear,
            normal_callback = function(current) self:normalFromPopup(parent, current, clear) end,
        })
        if shown and result then
            -- A long word DPD lacks opens its miss screen; that is not a lookup to keep.
            if model.found then self:getHistory():add(model.original_clean or word) end
            return true
        end
        if not shown then
            logger.warn("DPD popup lookup failed; using normal dictionary:", result)
            return self:normalFromPopup(parent, word, clear)
        end
        clear()
        return false
    end
    if not ok then logger.warn("DPD popup lookup failed; using normal dictionary:", model) end
    return self:normalFromPopup(parent, word, clear)
end

-- ReaderDictionary may finish a cancellable lookup after the caller returns.
-- Identify only our fallback by its callback, so teardown can dismiss it without
-- touching an unrelated dictionary window or changing automatic DPD routing.
function DPD:trackPopupFallbacks(dictionary)
    if self.popup_fallback_hook or type(dictionary.showDict) ~= "function" then return end
    local owner, original = self, dictionary.showDict
    local hook = { dictionary = dictionary, original = original, active = true,
        no_results_original = dictionary.showNoResultsDialog }
    hook.wrapper = function(dict, word, results, boxes, link, close_callback, ...)
        local token = hook.active and owner.popup_fallbacks and owner.popup_fallbacks[close_callback]
        if token and token.cancelled then
            if dict.dismissLookupInfo then dict:dismissLookupInfo() end
            close_callback()
            return
        end
        local result = original(dict, word, results, boxes, link, close_callback, ...)
        local window = dict.dict_window
        if token and window and window.dict_close_callback == close_callback then token.window = window end
        return result
    end
    if type(hook.no_results_original) == "function" then
        hook.no_results_wrapper = function(dict, word, dict_names, fuzzy, boxes, link, close_callback, ...)
            local token = hook.active and owner.popup_fallbacks and owner.popup_fallbacks[close_callback]
            if not token then
                return hook.no_results_original(dict, word, dict_names, fuzzy, boxes, link, close_callback, ...)
            end
            if token.cancelled then
                if dict.dismissLookupInfo then dict:dismissLookupInfo() end
                close_callback()
                return true
            end
            -- This optional prompt is a local InputDialog, rather than the
            -- dictionary window, and preset actions replace its close callback.
            -- For child fallbacks show the normal dictionary's empty result
            -- card instead, keeping selection ownership and teardown exact.
            return false
        end
        dictionary.showNoResultsDialog = hook.no_results_wrapper
    end
    self.popup_fallback_hook = hook
    dictionary.showDict = hook.wrapper
end

function DPD:releasePopupFallbackHook()
    if self.popup_fallbacks and next(self.popup_fallbacks) then return end
    local hook = self.popup_fallback_hook
    if not hook then return end
    hook.active = false
    if hook.dictionary.showDict == hook.wrapper then hook.dictionary.showDict = hook.original end
    if hook.no_results_wrapper and hook.dictionary.showNoResultsDialog == hook.no_results_wrapper then
        hook.dictionary.showNoResultsDialog = hook.no_results_original
    end
    self.popup_fallback_hook = nil
end

function DPD:normalFromPopup(parent, word, clear_selection)
    local clear = once(clear_selection)
    local dictionary = self.ui.dictionary
    if self.stopped or parent.closed or not dictionary then clear(); return false end
    self.popup_fallbacks = self.popup_fallbacks or {}
    local token = { parent = parent, clear_selection = clear }
    local callback
    callback = once(function()
        self.popup_fallbacks[callback] = nil
        clear()
        self:releasePopupFallbackHook()
    end)
    token.close_callback = callback
    self.popup_fallbacks[callback] = token
    self:trackPopupFallbacks(dictionary)
    local previous = dictionary.dict_window
    local ok, result = pcall(self.normalLookup, self, word, true, nil, nil, nil, callback)
    local window = dictionary.dict_window
    if window and window ~= previous and window.dict_close_callback == callback then token.window = window end
    if not ok or not result then
        callback()
        if not ok then self:showError(result, "KOReader's dictionary could not open. Try the lookup again.") end
        return false
    end
    return true
end

function DPD:closePopupFallbacks(parent)
    local tokens = {}
    for _, token in pairs(self.popup_fallbacks or {}) do
        if not parent or token.parent == parent then tokens[#tokens + 1] = token end
    end
    for _, token in ipairs(tokens) do
        token.cancelled = true
        local window = token.window
        if window and window.dict_close_callback == token.close_callback and window.onClose then
            local ok, err = pcall(window.onClose, window)
            token.close_callback()
            if not ok then logger.warn("DPD normal dictionary close failed:", err) end
        else
            -- Keep the identity guard for an asynchronous showDict. The selection
            -- is safe to clear immediately, even if the lookup hasn't finished.
            token.clear_selection()
        end
    end
    self:releasePopupFallbackHook()
end

function DPD:showLookup(word, options)
    -- A popup or selection menu opened before the plugin stopped can still call this.
    if self.stopped then return self:stoppedMessage() end
    local ok, result = pcall(function()
        local model = self:getModel(word, options and options.spelling and { spelling = true } or nil)
        -- A typed number that is not a headword ID says so instead of "No DPD entry".
        model.id_query = options and options.id_query or nil
        local shown = self:showModel(model, options)
        -- A mistyped word with only did-you-mean offers is a miss, not history.
        if shown and model.found and not Lookup.isSpellingOnly(model) then
            self:getHistory():add(model.original_clean or word)
        end
        return shown
    end)
    if not ok then
        logger.warn("DPD lookup failed:", result)
        Diag.log("Lookup failed:", word, result)
        self:showDatabaseError(result, "DPD could not look up this word. Check Database status in the DPD menu, then try again.")
    end
    return ok and result
end

function DPD:showId(text, options)
    if self.stopped then return self:stoppedMessage() end
    options = options or {}
    local ok, result = pcall(function()
        local model = self:ensureLookup():byId(tonumber(text))
        if not model then return false end
        model.original, model.original_clean = text, text
        local shown = self:showModel(model, {
            -- Other dictionaries know the word (dhamma), not DPD's ID or homonym number.
            normal_callback = self.ui.dictionary and function(current)
                if current == text then current = model.query:gsub(" %d[%d.]*$", "") end
                self:normalLookup(current, true)
            end or nil,
            edit_callback = options.edit_callback, parent = options.parent,
        })
        if shown then self:getHistory():add(text) end
        return shown
    end)
    if not ok then
        self:showError(result, "DPD could not open this ID. Check Database status in the DPD menu, then try again.")
        -- Already reported: the caller must not retry it as a word.
        return nil, "error"
    end
    return result
end

-- Older databases ship without the other dictionaries; say so rather than
-- offering a search that can only come back empty.
function DPD:hasDictionaries()
    if self.lookup then
        local ready, err = self.lookup:hasOtherDictionaries()
        if err then self:message(err); return false end
        if ready then return true end
    end
    self:message("This DPD database has no other dictionaries. They come with DPD v0.4.20260926 and newer.")
    return false
end

-- Typed text in the selected other dictionaries, from the lookup dialog only.
-- Unlike the other lookups, the popup opens on a miss too: it says that
-- nothing was found and where to choose dictionaries.
function DPD:showDictionarySearch(word, options)
    if self.stopped then return self:stoppedMessage() end
    options = options or {}
    local ok, result = pcall(function()
        local model = self:ensureLookup():searchDictionaries(word, self:enabledDictionaries(), options.draft)
        model.original_clean = model.query
        local shown = self:showModel(model, {
            normal_callback = self.ui.dictionary and function(current) self:normalLookup(current, true) end or nil,
            edit_callback = options.edit_callback, parent = options.parent,
        })
        if shown and model.found then self:getHistory():add(model.query, "dictionaries") end
        return shown
    end)
    if not ok then
        self:showError(result, "DPD could not search the other dictionaries. Check Database status in the DPD menu, then try again.")
    end
    return ok and result
end

-- English→Pāḷi, from the lookup dialog only.
function DPD:showEnglish(word, options)
    if self.stopped then return self:stoppedMessage() end
    options = options or {}
    local ok, result = pcall(function()
        local model = self:ensureLookup():english(word)
        if Popup.route(model) ~= "dpd" then return false end
        local shown = self:showModel(model, {
            normal_callback = self.ui.dictionary and function(current) self:normalLookup(current, true) end or nil,
            edit_callback = options.edit_callback, parent = options.parent,
        })
        if shown and model.found then self:getHistory():add(word, "english") end
        return shown
    end)
    if not ok then self:showError(result, "DPD could not search in English. Check Database status in the DPD menu, then try again.") end
    return ok and result
end

-- The Vocabulary builder reviews a saved word by looking it up without a
-- selection, after noting which word it is reviewing.
local function vocabularyReview(ui, word)
    local vocabulary = ui.vocabbuilder
    return vocabulary ~= nil and vocabulary.widget ~= nil and vocabulary.widget.current_lookup_word == word
end

function DPD:tryDirect(word, is_sane, boxes, highlight, link, close_callback)
    -- Reading selections use direct mode, as do Vocabulary builder reviews.
    -- Manual dictionary searches keep their normal behavior and still have
    -- the DPD button.
    local review = not highlight and vocabularyReview(self.ui, word)
    -- Reviews belong to the reader's word list, not to the open book, so they
    -- follow the global setting; a book's own choice covers its selections.
    local enabled
    if review then enabled = self.settings.direct_lookup else enabled = highlight and self:directEnabled() end
    if self.stopped or not enabled then return false end
    if not self.settings.db_path then self:warnDatabase(NO_DATABASE); return false end
    local model = self:getModel(word, Popup.selection_options)
    if Popup.route(model) ~= "dpd" then
        if #(model.damaged or {}) > 0 then self:warnDatabase(LOOKUP_FAILED) end
        return false
    end
    -- A long word DPD lacks opens its miss screen; that is not a lookup to keep.
    local keep = model.found and not model.long_miss and not review
    -- Before the popup, as KOReader's dictionary does.
    local announced = keep and self:announceLookup(word, is_sane)
    local shown = self:showModel(model, {
        highlight = highlight, close_callback = close_callback,
        normal_callback = function(current)
            -- KOReader's dictionary cleans the selection as it would have,
            -- and doesn't announce the word again: the Vocabulary builder
            -- would show "Vocabulary exists" for it.
            self:withoutAnnouncing(announced, function()
                self:normalLookup(current, is_sane, boxes, highlight, link, close_callback)
            end)
        end,
    })
    if shown and keep then self:getHistory():add(model.original_clean or word) end
    return shown
end

-- KOReader's dictionary announces each lookup for the Vocabulary builder,
-- which saves the word when its own setting says so. A failing listener must
-- not turn a DPD lookup into a fallback, which would announce it twice.
-- A word the Vocabulary builder already has isn't announced: its "Vocabulary
-- exists" dialog would open hidden under DPD's popup, stay after DPD closes,
-- and delay the popup by about 270 ms on a Kindle. Returns the word, so a
-- handoff to KOReader's dictionary doesn't announce it either.
function DPD:announceLookup(word, is_sane)
    local props, dictionary = self.ui.doc_props, self.ui.dictionary
    local announced
    Diag.protect("lookup announcement", function()
        -- The word as KOReader's dictionary would save it: a PDF selection's
        -- "pacchima," must not become a second card beside "pacchima".
        if dictionary and dictionary.cleanSelection then word = dictionary:cleanSelection(word, is_sane) end
        if not self:vocabularyHas(word) then
            self.ui:handleEvent(require("ui/event"):new("WordLookedUp", word, props and props.display_title))
        end
        announced = word
    end)
    return announced
end

-- Whether KOReader's Vocabulary builder is on and has saved the word. Any
-- failure reads as not saved, which announces the word as before.
function DPD:vocabularyHas(word)
    if not self.ui.vocabbuilder then return false end
    local conn
    local ok, saved = pcall(function()
        local settings = G_reader_settings:readSetting("vocabulary_builder")
        if not (settings and settings.enabled) then return false end
        local path = DataStorage:getSettingsDir() .. "/vocabulary_builder.sqlite3"
        if lfs.attributes(path, "mode") ~= "file" then return false end
        conn = require("lua-ljsqlite3/init").open(path, "ro")
        local stmt = conn:prepare("SELECT 1 FROM vocabulary WHERE word = ? LIMIT 1")
        local row = stmt:bind(word):step()
        stmt:close()
        return row ~= nil
    end)
    -- The binding keeps a connection open until closed, even after a failed
    -- query; closing also finalizes its statements.
    if conn then pcall(conn.close, conn) end
    return ok and saved
end

-- Runs fn while the Vocabulary builder ignores the word DPD announced.
-- KOReader's dictionary announces synchronously, before its lookup yields.
function DPD:withoutAnnouncing(word, fn)
    local vocabulary = self.ui.vocabbuilder
    if not (word and vocabulary and vocabulary.onWordLookedUp) then return fn() end
    local own, listener = rawget(vocabulary, "onWordLookedUp"), vocabulary.onWordLookedUp
    vocabulary.onWordLookedUp = function(v, looked_up, ...)
        if looked_up ~= word then return listener(v, looked_up, ...) end
    end
    local ok, err = pcall(fn)
    vocabulary.onWordLookedUp = own
    if not ok then error(err, 0) end
end

-- A book's own long-press choice, or nil when it follows the global setting.
-- Only books have their own settings; the file manager uses the global one.
function DPD:bookDirect()
    local book = self.ui.doc_settings
    if book then return book:readSetting("dpd_direct_lookup") end
end

function DPD:directEnabled()
    local book = self:bookDirect()
    if book ~= nil then return book end
    return self.settings.direct_lookup
end

function DPD:toggleBookDirect()
    local value = not self:directEnabled()
    -- Matching the global setting is no exception: the book follows it again.
    if value == self.settings.direct_lookup then self.ui.doc_settings:delSetting("dpd_direct_lookup")
    else self.ui.doc_settings:saveSetting("dpd_direct_lookup", value) end
    self:syncDirectMode()
end

-- Long-press falls back to the normal dictionary when DPD cannot open its
-- database, or cannot read one word. Say why once per session for each, above
-- that dictionary, not silently. A database problem names where to fix it
-- before "Until then"; damaged data affects only the words DPD can't read.
function DPD:warnDatabase(text)
    local damaged = text == LOOKUP_FAILED or text == DAMAGED
    local kind = damaged and "data" or "database"
    if database_warned[kind] then return end
    database_warned[kind] = true
    if damaged then
        text = text .. "\n\nLong-press opens your normal dictionary for words DPD can't read."
    else
        -- One instruction: the incompatible text already names the file to choose.
        if text == INCOMPATIBLE then
            text = text:sub(1, -2) .. " under " .. CHOOSE_MENU .. "."
        elseif not text:find("Choose database file", 1, true) then
            text = text .. "\n\n" .. CHOOSE
        end
        text = text .. "\n\nUntil then, long-press opens your normal dictionary."
    end
    UIManager:nextTick(function() self:message(text) end)
end

-- The wrapper stays while either setting is on: a book that turns DPD off
-- still lets Vocabulary builder reviews follow the global setting.
function DPD:syncDirectMode()
    if (self.settings.direct_lookup or self:directEnabled()) and self.ui.dictionary then
        if not self.direct then
            local err
            self.direct, err = Direct.install(self.ui.dictionary,
                function(...) return self:tryDirect(...) end,
                function(err)
                    logger.warn("DPD direct lookup failed; using normal dictionary:", err)
                    Diag.log("Direct lookup failed:", err)
                    self:warnDatabase(databaseMessage(err) or LOOKUP_FAILED)
                end)
            if err then logger.warn("DPD:", err); Diag.log("Direct lookup unavailable:", err) end
        end
    elseif self.direct then self.direct:remove(); self.direct = nil end
end

function DPD:registerEntryPoints()
    local dictionary = self.ui.dictionary
    if dictionary and type(dictionary.addToDictButtons) == "function" then
        dictionary:addToDictButtons{
            id = "dpd", menu_text = "Digital Pāḷi Dictionary", text = "DPD",
            -- A transient row stays visible even with an existing custom button layout.
            -- KOReader appends conditional rows; insert_first applies only to others.
            conditional = true, row_group = "dpd",
            callback = function(popup) self:fromDictionary(popup) end,
        }
    end
    if self.ui.highlight and type(self.ui.highlight.addToHighlightDialog) == "function" then
        self.ui.highlight:addToHighlightDialog("06_dpd", function(highlight)
            return { text = "DPD", callback = function()
                local word = highlight.selected_text and highlight.selected_text.text or ""
                -- Close the selection menu, keeping the selection until DPD closes.
                highlight:onClose(true)
                local shown = self:showLookup(word, {
                    highlight = highlight,
                    normal_callback = function(current) self:normalLookup(current, true, nil, highlight) end,
                })
                if not shown then self:clearSelection(highlight) end
            end }
        end)
    end
end

function DPD:fromDictionary(popup)
    -- A fallback opened from a DPD popup keeps that popup: open DPD above it.
    local parent
    for _, token in pairs(self.popup_fallbacks or {}) do
        if token.window == popup and not token.cancelled then parent = token.parent; break end
    end
    if parent then
        if parent.closed or self.viewer ~= parent then return false end
        return self:showLookup(popup.word, {
            parent = parent,
            -- The fallback beneath DPD owns the selection cleanup.
            normal_callback = function(word)
                if word ~= popup.word then self:normalFromPopup(parent, word) end
            end,
        })
    end
    self:showLookup(popup.word, {
        -- The dictionary beneath DPD owns the selection cleanup.
        normal_callback = function(word)
            if word ~= popup.word then self:normalLookup(word, true) end
        end,
    })
end

-- Suggestions use the open database only: after it closes (suspend, a new
-- database) they stop rather than reopen it.
function DPD:suggest(text, mode)
    if self.stopped then return nil, "unavailable" end
    -- Suspend closes the database under an open dialog; reopen it as a lookup would.
    if not self.db and not (self.settings.db_path and pcall(self.ensureLookup, self)) then
        return nil, "unavailable"
    end
    local ok, items = pcall(function()
        self.suggester = self.suggester or require("dpd/suggest").new(self.db)
        return self.suggester:complete(text, mode)
    end)
    if not ok then
        logger.warn("DPD suggestions failed:", items)
        Diag.log("Suggestions failed:", items)
        return nil, "error"
    end
    return items, #items == 0 and "empty" or "ready"
end

function DPD:stoppedMessage()
    self:message("Digital Pāḷi Dictionary is disabled until KOReader restarts.")
    return false
end

-- `parent` is the popup whose child is being edited: the result replaces only
-- that child, so Back returns to the parent. `replaced` is the popup being
-- edited, kept open until a search is submitted.
function DPD:inputLookup(recent, input, mode, parent, replaced)
    if self.stopped then return self:stoppedMessage() end
    if self.unsupported then return self:message(self.unsupported) end
    -- Searching the other dictionaries is its own menu item, never the
    -- remembered mode of Look up a word.
    if mode == "pali" or mode == "english" then self.settings.lookup_mode = mode; self:saveSettings() end
    if not recent then
        local ok, err = pcall(self.ensureLookup, self)
        if not ok then return self:recoverDatabase(err, input, mode) end
        if mode == "dictionaries" and not self:hasDictionaries() then return end
    end
    self.input_dialog = require("ui/dpd_input")[recent and "showRecent" or "show"]{
        settings = self.settings, history = self:getHistory(), input = input, mode = mode,
        suggest = function(text, mode) return self:suggest(text, mode) end,
        on_mode = function() self:saveSettings() end,
        on_reopen = function(dialog) self.input_dialog = dialog end,
        -- Don't keep a closed dialog's widgets, or cancel it again later.
        on_close = function(dialog) if self.input_dialog == dialog then self.input_dialog = nil end end,
        on_lookup = function(word, mode, draft)
            if replaced and not replaced.closed then replaced:close() end
            self:lookupInput(word, mode, draft, parent)
        end,
    }
end

function DPD:lookupInput(word, mode, draft, parent)
    if self.stopped or self.unsupported then return self:inputLookup(false, draft or word, mode) end
    local ok, err = pcall(self.ensureLookup, self)
    if not ok then
        return self:recoverDatabase(err, draft or word, mode,
            function() self:lookupInput(word, mode, draft, parent) end)
    end
    -- A parent closed meanwhile (sleep, outside tap) makes this a fresh search.
    if parent and (parent.closed or self.viewer ~= parent) then parent = nil end
    local edit = function(text, edit_mode, edit_parent, replaced)
        self:inputLookup(false, text or draft or word, edit_mode or mode, edit_parent or parent, replaced)
    end
    if mode == "english" then return self:showEnglish(word, { edit_callback = edit, parent = parent }) end
    if mode == "dictionaries" then
        if not self:hasDictionaries() then return end
        return self:showDictionarySearch(word, { edit_callback = edit, parent = parent, draft = draft })
    end
    -- As on dpdict.net, a typed number opens that headword ID.
    local id_query = word:match("^%d+$") ~= nil
    if id_query then
        local shown, failed = self:showId(word, { edit_callback = edit, parent = parent })
        if shown or failed then return end
    end
    return self:showLookup(word, { spelling = true, edit_callback = edit, id_query = id_query, parent = parent,
        normal_callback = self.ui.dictionary and function(current) self:normalLookup(current, true) end or nil })
end

function DPD:recoverDatabase(err, input, mode, retry)
    logger.warn("DPD database unavailable:", err)
    Diag.log("Database unavailable:", err)
    local ButtonDialog = require("ui/widget/buttondialog")
    local dialog, acted
    local function finish(action)
        if acted then return end
        acted = true
        UIManager:close(dialog)
        if action then action() end
    end
    dialog = ButtonDialog:new{
        title = databaseMessage(err) or "DPD database unavailable",
        buttons = {
            { { text = "Choose database file", callback = function()
                finish(function()
                    -- A file that won't open returns here with the draft, not to nothing.
                    self:chooseDatabase(retry or function() self:inputLookup(false, input, mode) end,
                        function(invalid) self:recoverDatabase(invalid, input, mode, retry) end,
                        function() self:recoverDatabase(err, input, mode, retry) end)
                end)
            end } },
            -- Status is a detour: dismissing it resumes the lookup if the
            -- database now opens, or returns to this recovery choice.
            { { text = "Database status", callback = function()
                finish(function()
                    self:databaseStatus(function(ok)
                        if self.stopped then return end
                        if ok then (retry or function() self:inputLookup(false, input, mode) end)()
                        else self:recoverDatabase(err, input, mode, retry) end
                    end)
                end)
            end } },
            { { text = "Cancel", callback = function() finish() end } },
        },
    }
    -- Back and outside dismissal must also invalidate retained button callbacks.
    local onCloseWidget = dialog.onCloseWidget
    function dialog:onCloseWidget(...)
        acted = true
        if onCloseWidget then return onCloseWidget(self, ...) end
    end
    UIManager:show(dialog)
    return dialog
end

-- `on_invalid(err)` runs after the reader dismisses the error for a file that
-- won't open, so recovery can offer its choices again. `on_cancel()` runs when
-- the chooser closes without a chosen file, so recovery keeps the draft.
function DPD:chooseDatabase(on_selected, on_invalid, on_cancel)
    local current = self.settings.db_path
    local chosen
    local chooser = PathChooser:new{
        path = current and current:match("^(.+)/[^/]+$") or require("device").home_dir or DataStorage:getDataDir(),
        select_directory = false, select_file = true,
        file_filter = function(name) return name:lower():match("%.db$") ~= nil end,
        onConfirm = function(path)
            chosen = true
            local ok, candidate = pcall(DB.new, path)
            if not ok then return self:showDatabaseError(candidate,
                "That file could not be opened as a DPD database. Choose the extracted dpd-mobile.db file.",
                on_invalid and function() if not self.stopped then on_invalid(candidate) end end) end
            candidate:close()
            self:closeDatabase()
            self.settings.db_path = path
            self:saveSettings()
            if on_selected then on_selected()
            else self:message("DPD database selected. DPD on word long-press is " .. (self:directEnabled() and "on." or "off.")) end
        end,
    }
    local plugin, onCloseWidget = self, chooser.onCloseWidget
    function chooser:onCloseWidget(...)
        if on_cancel and not chosen then
            chosen = true
            UIManager:nextTick(function() if not plugin.stopped then on_cancel() end end)
        end
        if onCloseWidget then return onCloseWidget(self, ...) end
    end
    UIManager:show(chooser)
end

function DPD:chooseFontSize(touchmenu_instance)
    local SpinWidget = require("ui/widget/spinwidget")
    UIManager:show(SpinWidget:new{
        title_text = "DPD popup font size",
        info_text = "Applies to the next DPD popup.",
        value = self.settings.font_size, value_min = 12, value_max = 32, value_step = 1, value_hold_step = 4,
        default_value = 16, ok_text = "Set",
        callback = function(spin)
            self.settings.font_size = spin.value
            self:saveSettings()
            if touchmenu_instance then touchmenu_instance:updateItems() end
        end,
    })
end

-- `on_dismiss(ok)` runs when the status or error message closes.
function DPD:databaseStatus(on_dismiss)
    -- The menu outlives a stop; choosing another database can't undo that.
    if self.stopped then return self:stoppedMessage() end
    local ok, result = pcall(function()
        self:ensureLookup()
        local size = lfs.attributes(self.settings.db_path, "size") or 0
        return "Digital Pāḷi Dictionary for KOReader " .. VERSION .. "\n\n" .. self.settings.db_path .. "\n"
            .. string.format("%.1f MB", size / 1000000) .. "\nRelease: " .. (self.db.info.dpd_release_version or "unknown")
            .. "\nSchema: " .. (self.db.info.db_schema_version or "unknown")
            .. "\nCore columns: OK\nOpen: read-only\nJournal: " .. self.db.journal_mode
            .. "\n\nTested with " .. require("dpd/db_compat").tested() .. ". Newer releases with the same core columns work."
    end)
    local dismissed = on_dismiss and function() UIManager:nextTick(function() on_dismiss(ok) end) end
    if ok then self:message(result, dismissed)
    else self:showDatabaseError(result,
        "DPD could not open the database. Use Choose database file in the DPD menu to select dpd-mobile.db.",
        dismissed) end
end

function DPD:toggleHistory()
    local history = self:getHistory()
    local enabled = not history:enabled()
    local function apply()
        history:setEnabled(enabled)
        self:saveSettings()
    end
    if not enabled and #history:list() > 0 then
        local ConfirmBox = require("ui/widget/confirmbox")
        UIManager:show(ConfirmBox:new{
            text = "Turn off recording and clear recent DPD lookups? New lookups will not be recorded.",
            ok_text = "Turn off", ok_callback = apply,
        })
    else apply() end
end

function DPD:clearHistory()
    if #self:getHistory():list() == 0 then return end
    local ConfirmBox = require("ui/widget/confirmbox")
    UIManager:show(ConfirmBox:new{
        text = "Clear the saved list of recent DPD lookups?", ok_text = "Clear",
        ok_callback = function()
            self:getHistory():clear()
            self:saveSettings()
            self:message("Recent DPD lookups cleared.")
        end,
    })
end

function DPD:showDiagnosticLog()
    local text = Diag.tail(200)
    if not text or text == "" then return self:message("No DPD diagnostic log yet. Turn on Help → Diagnostics → Write diagnostic log first.") end
    local TextViewer = require("ui/widget/textviewer")
    UIManager:show(TextViewer:new{ title = "DPD diagnostic log", text = Diag.path() .. "\n\n" .. text })
end

function DPD:showHelp()
    local TextViewer = require("ui/widget/textviewer")
    UIManager:show(TextViewer:new{ title = "DPD help", add_default_buttons=true,
        buttons_table={{{text="About & licenses",callback=function() self:aboutLicenses() end}}},
        text = [[Look up a word
Use Pāḷi for a word or a DPD ID number. Switch to English to search English meanings. ≈ marks an approximate spelling, not an exact match. With Velthuis input on, type aa for ā, .t for ṭ and ~n for ñ.

Search other dictionaries
Searches the dictionaries chosen under Other dictionaries for what you type, such as a Sanskrit word or a name. With Velthuis input on, "s, .s, .r and .rr also give ś, ṣ, ṛ and ṝ ("s is a quote mark then s). The DPD button in the results looks the word up in DPD.

Explore an entry
Tap an underlined word to open it. Tap ▸ to expand details in place; ▾ collapses them. One main sense stays expanded at a time. Hold or select text to open a child popup.

Joined forms
In a book, holding a form joined by ’ or - (bhikkhave’ti, akaṭa-anudhammena) may select only one part. Drag the selection over the whole form, or type it in Look up a word.

Back and Close
Back restores the previous DPD view or reveals the parent popup. Close dismisses this popup.

Recent and editing
Recent runs a fresh lookup. Dismissing Recent restores your draft. The pencil beside the title edits the lookup: tap it for the word you selected or typed, hold it for the form DPD looked up. Edit search after a miss restores the original text and language.

Dictionaries
The buttons below the entry stay in place on every page. Other dictionaries opens the sources bundled with DPD; Back returns to the entry. A long article is read in parts. In the DPD menu, hold a name under Other dictionaries for its full title and author. KOReader dictionary hands the word to your usual dictionary and closes the current DPD popup. Unknown words selected in a book fall back automatically; very long Pāḷi words first show the parts DPD knows, with KOReader dictionary below.

Setup
Use Choose database file for the extracted dpd-mobile.db. Database status checks it. Display and input holds the popup font size, which applies to the next popup. DPD on long-press in this book turns long-press lookup on or off for one book, such as an English one.]] })
end

function DPD:diagnosticsMenu()
    return { text = "Diagnostics", sub_item_table = {
        { text = "Write diagnostic log", checked_func = function() return Diag.enabled end,
            callback = function()
                self.settings.diagnostics = not Diag.enabled
                self:saveSettings()
                Diag.setEnabled(self.settings.diagnostics)
                if Diag.enabled then
                    self:message("DPD now writes a diagnostic log to:\n" .. Diag.path()
                        .. "\n\nThe log includes words you look up, links you tap, timings and errors."
                        .. " Turn it off when you have sent it.")
                end
            end },
        { text = "Show diagnostic log", callback = function() self:showDiagnosticLog() end },
    } }
end

function DPD:aboutLicenses()
    local TextViewer = require("ui/widget/textviewer")
    UIManager:show(TextViewer:new{title="About & licenses",
        text=require("dpd/about").text(self.db and self.db.info)})
end

function DPD:helpMenu()
    return { text = "Help", sub_item_table = {
        { text = "DPD help", callback = function() self:showHelp() end },
        { text = "About & licenses", callback = function() self:aboutLicenses() end, separator = true },
        self:diagnosticsMenu(),
    } }
end

function DPD:displayMenu()
    return { text = "Display and input", sub_item_table = {
        { text_func = function() return "Popup font size: " .. self.settings.font_size end,
            keep_menu_open = true,
            callback = function(touchmenu_instance) self:chooseFontSize(touchmenu_instance) end },
        { text = "Show ṁ instead of ṃ", checked_func = function() return self.settings.niggahita == "ṁ" end,
            callback = function()
                self.settings.niggahita = self.settings.niggahita ~= "ṁ" and "ṁ" or nil
                self:saveSettings()
            end },
        { text = "Velthuis input (aa → ā, .t → ṭ, ~n → ñ)", checked_func = function() return self.settings.velthuis end,
            callback = function()
                self.settings.velthuis = not self.settings.velthuis
                self:saveSettings()
            end },
    } }
end

function DPD:addToMainMenu(items)
    local entries
    if self.unsupported then
        entries = { { text = "Needs a newer KOReader", callback = function() self:message(self.unsupported) end } }
    else
        entries = {
            { text = "Look up a word", callback = function() self:inputLookup() end },
            { text = "Search other dictionaries", callback = function() self:inputLookup(false, nil, "dictionaries") end },
            { text = "Recent lookups", sub_item_table = {
                { text = "Show recent lookups", callback = function() self:inputLookup(true) end },
                { text = "Record recent lookups", checked_func = function() return self:getHistory():enabled() end,
                    callback = function() self:toggleHistory() end },
                { text = "Clear recent lookups", enabled_func = function() return #self:getHistory():list() > 0 end,
                    callback = function() self:clearHistory() end },
            }, separator = true },
            { text = "Choose database file", callback = function() self:chooseDatabase() end },
            { text = "Database status", callback = function() self:databaseStatus() end, separator = true },
            self:displayMenu(),
            self:dictionariesMenu(),
            { text = "DPD on word long-press", checked_func = function() return self.settings.direct_lookup end,
                callback = function()
                    self.settings.direct_lookup = not self.settings.direct_lookup
                    self:saveSettings()
                    self:syncDirectMode()
                end, separator = not self.ui.doc_settings },
        }
        if self.ui.doc_settings then
            entries[#entries + 1] = { text = "DPD on long-press in this book", checked_func = function()
                    return self:directEnabled()
                end,
                help_text = "Overrides DPD on word long-press for this book only, for example an English "
                    .. "book. Choosing the same as that setting makes the book follow it again.",
                callback = function() self:toggleBookDirect() end, separator = true }
        end
    end
    -- Help, About and Diagnostics in one place, below the settings.
    entries[#entries + 1] = self:helpMenu()
    items.dpd = { text = "Digital Pāḷi Dictionary", sorting_hint = "search", sub_item_table = entries }
end

function DPD:closeDatabase()
    -- The search dialog stays open over Suspend; keep it, so the next Suspend
    -- also cancels its suggestions. Its on_close forgets it.
    if self.input_dialog and self.input_dialog.cancel then self.input_dialog.cancel() end
    self.suggester = nil
    self:closeViewers()
    if self.db then self.db:close() end
    self.db, self.lookup = nil, nil
end

function DPD:onSuspend() self:closeDatabase() end
function DPD:removeEntryPoints()
    if self.ui.highlight and type(self.ui.highlight.removeFromHighlightDialog) == "function" then
        self.ui.highlight:removeFromHighlightDialog("06_dpd")
    end
    -- ReaderDictionary has no public removal API for addToDictButtons.
    local dictionary = self.ui.dictionary
    if dictionary and type(rawget(dictionary, "_dict_buttons")) == "table" then
        dictionary._dict_buttons.dpd = nil
    end
end

function DPD:onCloseDocument()
    if self.stopped then return end
    self.stopped = true
    Diag.log("Plugin stopped")
    self:closeDatabase()
    if self.direct then self.direct:remove(); self.direct = nil end
    self:removeEntryPoints()
    self:saveSettings()
end
-- UIManager sends CloseWidget to the closed owner's children. FileManager
-- has no CloseDocument event; popup closures do not propagate to this plugin.
function DPD:onCloseWidget() self:onCloseDocument() end
function DPD:onExit() self:onCloseDocument() end
function DPD:stopPlugin() self:onCloseDocument() end

return DPD
