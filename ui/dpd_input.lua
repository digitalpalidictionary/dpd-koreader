-- The "Look up a word" dialog. Typed numbers open that headword ID, as on
-- dpdict.net. Velthuis input (aa → ā, .t → ṭ, ~n → ñ) is converted on
-- submission when the reader turns it on. "Recent" lists earlier lookups.
-- "English" switches to English→Pāḷi (and "Pāḷi" back), reopening the
-- dialog with the same text; the choice is remembered. A third mode,
-- "dictionaries", searches the other dictionaries; it is opened from its own
-- menu item, is never remembered, and its "DPD" button switches to Pāḷi.
--
-- Suggestions: InputDialog.edited_callback fires on every keystroke. After
-- `idle_s` without typing, `options.suggest(text, mode)` fills a row of
-- buttons under the input. The row keeps a fixed height and only its area
-- gets a fast refresh, so the dialog and keyboard never move. A generation
-- number drops results for text that has changed since; the pending timer
-- is cancelled when the dialog closes or `cancel()` is called (the plugin
-- does that when it closes the database).
local InputDialog = require("ui/widget/inputdialog")
local UIManager = require("ui/uimanager")
local Velthuis = require("dpd/velthuis")
local Normalize = require("dpd/normalize")

local Input = {}
Input.idle_s = 0.45
Input.columns, Input.rows = 3, 2

-- A fixed-size area that remembers where it was painted, for partial refreshes.
local function suggestionArea(dialog, width, mark)
    local ButtonTable = require("ui/widget/buttontable")
    local CenterContainer = require("ui/widget/container/centercontainer")
    local Geom = require("ui/geometry")
    local VerticalSpan = require("ui/widget/verticalspan")
    local blank = {}
    for r = 1, Input.rows do
        blank[r] = {}
        for c = 1, Input.columns do blank[r][c] = { text = " ", enabled = false } end
    end
    local sample = ButtonTable:new{ width = width, buttons = blank, zero_sep = true, show_parent = dialog }
    local height = sample:getSize().h
    sample:free()
    local Area = CenterContainer:extend{}
    function Area:paintTo(bb, x, y)
        self.dimen.x, self.dimen.y = x, y
        CenterContainer.paintTo(self, bb, x, y)
    end
    local area = Area:new{ dimen = Geom:new{ x = 0, y = 0, w = width, h = height }, VerticalSpan:new{ width = height } }
    function area:show(items, choose, status)
        if self[1].free then self[1]:free() end
        local messages = {
            empty = "No suggestions — Look up still searches.",
            unavailable = "Suggestions unavailable — check Database status.",
            error = "Suggestions failed — try Look up.",
        }
        if messages[status] then
            local TextBoxWidget = require("ui/widget/textboxwidget")
            local Face = require("ui/font")
            self[1] = TextBoxWidget:new{ text = messages[status], width = width,
                face = Face:getFace("smallinfofont"), alignment = "center" }
        elseif #items == 0 then
            self[1] = VerticalSpan:new{ width = height }
        else
            local rows = {}
            for r = 1, Input.rows do
                rows[r] = {}
                for c = 1, Input.columns do
                    local item = items[(r - 1) * Input.columns + c]
                    local shown = item and (mark == "ṁ" and (item.text:gsub("ṃ", "ṁ")) or item.text)
                    rows[r][c] = item and {
                        text = (item.approximate and "≈ " or "") .. shown, font_bold = false,
                        callback = function() choose(item) end,
                    } or { text = " ", enabled = false }
                end
            end
            self[1] = ButtonTable:new{ width = width, buttons = rows, zero_sep = true, show_parent = dialog }
        end
    end
    return area
end

--- Text as it will be looked up. Velthuis applies to Pāḷi, and with the
--- Sanskrit sequences to the other dictionaries; never to English.
function Input.prepare(text, settings, mode)
    text = Normalize.trim(tostring(text or ""))
    if settings and settings.velthuis and mode ~= "english" then
        text = Velthuis.toUnicode(text, { sanskrit = mode == "dictionaries" })
    end
    return text
end

local modes = { pali = true, english = true, dictionaries = true }

--- A paged list of recent lookups; choosing one runs it again.
--- @param options table { history, on_lookup = function(text, mode), on_return = function() }
function Input.showRecent(options)
    local Menu = require("ui/widget/menu")
    local items = {}
    local menu, selected, returned, notified
    for _, item in ipairs(options.history:list()) do
        local label = item.mode == "english" and "English" or item.mode == "dictionaries" and "Dictionaries" or nil
        items[#items + 1] = { text = item.query, mandatory = label,
            callback = function()
                selected = true
                UIManager:close(menu)
                options.on_lookup(item.query, item.mode)
            end }
    end
    if #items == 0 then
        local InfoMessage = require("ui/widget/infomessage")
        UIManager:show(InfoMessage:new{ text = options.history:enabled() and "No recent DPD lookups yet."
            or "Recent lookups are off. Turn on Recent lookups → Record recent lookups in the DPD menu.",
            timeout = options.history:enabled() and 2 or 6 })
        return
    end
    menu = Menu:new{ title = "Recent DPD lookups", item_table = items, covers_fullscreen = true,
        is_borderless = true, is_popout = false }
    local onCloseWidget = menu.onCloseWidget
    function menu:onCloseWidget(...)
        if not notified then
            notified = true
            if options.on_close then options.on_close(self) end
        end
        if onCloseWidget then return onCloseWidget(self, ...) end
    end
    menu.close_callback = function()
        UIManager:close(menu)
        if not selected and not returned and options.on_return then
            returned = true
            options.on_return()
        end
    end
    UIManager:show(menu)
    return menu
end

--- @param options table { settings, history, mode (pali/english/dictionaries; defaults to
---   the remembered settings.lookup_mode), on_lookup = function(text, mode, original_draft),
---   suggest = function(text, mode) -> items or nil, status (ready/empty/unavailable/error),
---   on_close = function(dialog), called once however the dialog closes }
--- @return the dialog, with `cancel()` to drop pending suggestions
function Input.show(options)
    local dialog, area
    local settings = options.settings
    local mode = modes[options.mode] and options.mode
        or (settings.lookup_mode == "english" and "english" or "pali")
    local generation, pending, closed, notified = 0, nil, false, false
    local function cancel()
        generation = generation + 1
        if pending then UIManager:unschedule(pending); pending = nil end
    end
    local function finished()
        closed = true
        cancel()
        if not notified then
            notified = true
            if options.on_close then options.on_close(dialog) end
        end
    end
    local function close()
        finished()
        UIManager:close(dialog)
    end
    local function lookUp(text, chosen_mode)
        if text == "" then
            local InfoMessage = require("ui/widget/infomessage")
            UIManager:show(InfoMessage:new{ text = mode == "english" and "Type an English word first."
                or mode == "dictionaries" and "Type a word first."
                or "Type a Pāḷi word or ID number first.", timeout = 2 })
            return
        end
        local draft = dialog:getInputText()
        close()
        options.on_lookup(text, chosen_mode or mode, draft)
    end
    -- The reopened dialog's mode is named: the same one after Recent, the
    -- new one after a mode button. Copying options alone would keep the old.
    local function reopen(text, target_mode)
        local reopened = {}
        for k, v in pairs(options) do reopened[k] = v end
        reopened.input = text
        reopened.mode = target_mode
        local new = Input.show(reopened)
        if options.on_reopen then options.on_reopen(new) end
    end
    local function refresh(items, status)
        if closed or not area then return end
        area:show(items, function(item) lookUp(item.text) end, status)
        UIManager:setDirty(dialog, function() return "fast", area.dimen end)
    end
    local function edited()
        cancel()
        -- The dictionaries mode has no suggestions, so no queries either. Test
        -- the mode, not the area: InputDialog reports carried-over text while
        -- it is built, before the area exists.
        if closed or not options.suggest or mode == "dictionaries" then return end
        local current = generation
        pending = function()
            pending = nil
            if closed or current ~= generation then return end
            local text = Input.prepare(dialog:getInputText(), settings, mode)
            -- Empty/punctuation-only input and IDs do not request suggestions.
            local query = Normalize.lower(mode == "english" and Normalize.trim(Normalize.nfc(text)) or Normalize.query(text))
            if query == "" or query:match("^%d+$") then return refresh({}, "idle") end
            local ok, items, status = pcall(options.suggest, text, mode)
            -- Typing may have continued while the query ran.
            if current ~= generation then return end
            if not ok then items, status = nil, "error"
            elseif not items then status = status or "unavailable"
            else status = status or (#items == 0 and "empty" or "ready") end
            refresh(items or {}, status)
        end
        UIManager:scheduleIn(Input.idle_s, pending)
    end
    local hint = mode == "english" and "English word" or mode == "dictionaries" and "word or name"
        or "Pāḷi word or ID number"
    local title = mode == "english" and "DPD lookup · English → Pāḷi"
        or mode == "dictionaries" and "Other dictionaries" or "DPD lookup"
    if settings.velthuis and mode ~= "english" then title = title .. " · Velthuis" end
    dialog = InputDialog:new{
        title = title, input = options.input or "",
        -- No legend line: Help explains ≈, and the menu item the Velthuis keys.
        input_hint = hint,
        allow_newline = false,
        edited_callback = edited,
        buttons = { {
            { text = "Cancel", id = "close", callback = close },
            { text = "Recent", enabled = options.history ~= nil, callback = function()
                -- Empty/off history leaves the draft and keyboard in place.
                if #options.history:list() == 0 then Input.showRecent(options); return end
                local text = dialog:getInputText()
                close()
                local recent = {}
                for k, v in pairs(options) do recent[k] = v end
                recent.on_return = function() reopen(text, mode) end
                Input.showRecent(recent)
            end },
            { text = mode == "english" and "Pāḷi" or mode == "dictionaries" and "DPD" or "English",
                callback = function()
                local text = dialog:getInputText()
                close()
                -- From the dictionaries, DPD means Pāḷi lookup.
                settings.lookup_mode = mode == "pali" and "english" or "pali"
                if options.on_mode then options.on_mode(settings.lookup_mode) end
                reopen(text, settings.lookup_mode)
            end },
            { text = "Look up", is_enter_default = true, callback = function()
                lookUp(Input.prepare(dialog:getInputText(), settings, mode))
            end },
        } },
    }
    if options.suggest and mode ~= "dictionaries" then
        area = suggestionArea(dialog, dialog.width, settings.niggahita)
        dialog:addWidget(area, false, true)
    end
    -- Closing by any route (tap outside, back key) stops pending work.
    local onCloseWidget = dialog.onCloseWidget
    function dialog:onCloseWidget(...)
        finished()
        return onCloseWidget(self, ...)
    end
    dialog.cancel = cancel
    dialog.suggestion_area = area
    dialog.mode = mode
    UIManager:show(dialog)
    dialog:onShowKeyboard()
    return dialog
end

return Input
