local Blitbuffer = require("ffi/blitbuffer")
local ButtonTable = require("ui/widget/buttontable")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Diag = require("dpd/diag")
local FrameContainer = require("ui/widget/container/framecontainer")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconButton = require("ui/widget/iconbutton")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local LineWidget = require("ui/widget/linewidget")
local Navigation = require("dpd/navigation")
local Popup = require("dpd/popup")
local Render = require("ui/dpd_render")
local ScrollHtmlWidget = require("ui/widget/scrollhtmlwidget")
local Size = require("ui/size")
local TitleBar = require("ui/widget/titlebar")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local logger = require("logger")
local time = require("ui/time")
local Screen = Device.screen

-- link_guard_s: link taps this soon after a rebuild are ignored. On e-ink the
-- new page is not even visible yet, so such a tap is a touch bounce or a
-- repeat of the tap that caused the rebuild, landing on whatever link the new
-- page put under the finger (e.g. "KOReader dictionary" where "Other
-- dictionaries" was).
-- Not modal: KOReader stacks non-modal windows, such as its dictionary popup
-- opened from a selection in this one, beneath every modal window.
local Viewer = InputContainer:extend{ font_size = 16, anchor_search_pages = 8, link_guard_s = 0.5 }

-- Footer links are drawn as full-width buttons; a tap anywhere on the
-- button follows them, not only on its text.
local button_links = { ["dpd:edit-search"] = true }
local function isButtonLink(uri)
    return button_links[uri] or (type(uri) == "string" and
        (uri:match("^dpd:dict%-prev/%d+/%d+$") or uri:match("^dpd:dict%-next/%d+/%d+$")
            or uri:match("^dpd:dict%-entries/%d+$")))
end

function Viewer:init()
    self.navigation = Navigation.new(self.model)
    self.dimen = Geom:new{ w = Screen:getWidth(), h = Screen:getHeight() }
    if Device:isTouchDevice() then
        local range = function() return self.dimen end
        -- KOReader's own dictionary popups follow the Text selection rate setting.
        local hold_pan_rate = G_reader_settings:readSetting("hold_pan_rate")
            or (Screen.low_pan_rate and 5.0 or 30.0)
        self.ges_events = {
            TapOutside = { GestureRange:new{ ges = "tap", range = range } },
            HoldStartText = { GestureRange:new{ ges = "hold", range = range } },
            HoldPanText = { GestureRange:new{ ges = "hold_pan", range = range, rate = hold_pan_rate } },
            HoldReleaseText = {
                GestureRange:new{ ges = "hold_release", range = range },
                args = function(text) self:lookupSelection(text) end,
            },
        }
    end
    if Device:hasKeys() then
        self.key_events = {
            Back = { { "Back" }, { "Esc" } },
            NextLink = { { "Tab" }, { "Down" }, { "Right" }, event = "FocusLink", args = 1 },
            PreviousLink = { { "Shift", "Tab" }, { "Up" }, { "Left" }, event = "FocusLink", args = -1 },
            ActivateLink = { { "Press" }, { "Return" } },
        }
    end
    self:build()
end

function Viewer:build()
    local started = time.now()
    -- Begin/end lines bracket the native HTML layout, drawing and freeing.
    if Diag.enabled then Diag.log("Build begin:", Diag.memory()) end
    local frame = self.navigation:current()
    local width = math.floor(self.dimen.w * .92)
    local height = math.floor(self.dimen.h * .85)
    local border, padding = Screen:scaleBySize(2), Screen:scaleBySize(10)
    local inner = width - 2 * border
    local title = TitleBar:new{
        width = inner, title = Render.niggahita(Render.title(frame.model), self.niggahita), align = "left",
        with_bottom_line = true, show_parent = self,
        close_callback = function() self:close() end,
        -- Back returns to this popup's previous entry, or closes a child popup
        -- to reveal the parent it was opened from.
        left_icon = (#self.navigation.stack > 1 or self.parent_viewer) and "chevron.left" or nil,
        left_icon_tap_callback = function() self:back() end,
    }
    local edit_button = self:addEditButton(title, frame)
    -- A paradigm section (case label plus two form columns) needs about 19 em.
    local font_px = Screen:scaleBySize(self.font_size)
    self.font_px = font_px
    local target_px = math.ceil(Screen:getDPI() * 7 / 25.4)
    local content_width = inner - 2 * padding - ScrollHtmlWidget.scroll_bar_width - ScrollHtmlWidget.text_scroll_span
    local measured = {}
    self.control_layout = {
        content_em = content_width / font_px, target_em = target_px / font_px,
        border_em = 1 / font_px, buttons = {},
        measure_text = function(text, factor)
            local key = factor .. ":" .. text
            if not measured[key] then
                local widget = TextWidget:new{ text = text,
                    face = Font:getFace("cfont", self.font_size * factor) }
                measured[key] = widget:getSize().w / font_px
                widget:free()
            end
            return measured[key]
        end,
    }
    local html = Popup.render(self.lookup, frame, {
        paradigm_columns = math.max(1, math.floor(content_width / (font_px * 19))),
        content_em = content_width / font_px,
        dictionaries = self.dictionaries,
        edit_search = self.edit_callback ~= nil and #self.navigation.stack == 1,
        niggahita = self.niggahita,
        layout = self.control_layout,
    })
    local actions = self:actionRow(frame, inner)
    local actions_h = actions and actions:getSize().h or 0
    local function layout()
        return ScrollHtmlWidget:new{
            width = inner - 2 * padding, height = height - title:getSize().h - actions_h - 2 * padding - 2 * border,
            html_body = html, css = Render.cssFor(self.font_size),
            default_font_size = font_px,
            dialog = self, highlight_text_selection = true,
        }
    end
    local scroll = layout()
    -- shortcut: move at most three split rows; revisit only if device tests justify more layouts.
    for _ = 1, Viewer.split_passes do
        local moved = self:moveSplitRow(scroll.htmlbox_widget, html)
        if not moved then break end
        scroll:free()
        html = moved
        scroll = layout()
    end
    -- These are popup controls, so they must work even when book-link tapping
    -- is disabled in KOReader. Override only this HTML widget instance.
    scroll.htmlbox_widget.onTapText = function(widget, _, ges)
        return self:onTapText(widget, ges)
    end
    -- A field row's label and value are separate text lines that share a top
    -- but not always a bottom (a link is taller). KOReader merges only lines
    -- with the same top and bottom, so a hold on the value selected the label.
    local update = scroll.htmlbox_widget.updateHighlight
    scroll.htmlbox_widget.updateHighlight = function(widget)
        if widget.page_boxes == nil and widget.hold_start_pos and widget.hold_end_pos then
            local page = widget.document:openPage(widget.page_number)
            widget.page_boxes = Viewer.mergeRowLines(page:getPageText())
            page:close()
        end
        return update(widget)
    end
    local body = FrameContainer:new{ bordersize = 0, padding = padding, scroll }
    local window = FrameContainer:new{
        bordersize = border, padding = 0, background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{ align = "left", title, body, actions },
    }
    local center = CenterContainer:new{ dimen = self.dimen, window }
    local ok, err = pcall(function()
        if frame.restore_page then
            -- Expanding or appending changes the page count. Keep the current page,
            -- rather than jumping to the same percentage of a longer document.
            local box = scroll.htmlbox_widget
            local page = math.min(frame.restore_page, box.page_count)
            if frame.restore_anchor then
                page = self:findAnchor(box, frame.restore_anchor, page) or page
                page = math.min(page + (frame.restore_anchor.offset or 0), box.page_count)
                if frame.restore_anchor.last_uri then
                    local last = self:findAnchor(box, { uri = frame.restore_anchor.last_uri,
                        direction = -1, pages = math.huge }, box.page_count)
                    if last then page = math.min(page, last) end
                end
            end
            scroll:scrollToRatio((page - 1 + .1) / box.page_count)
        else
            scroll:scrollToRatio(frame.ratio)
        end
    end)
    if not ok then center:free(); error(err) end
    -- Restore scrolling successfully before freeing the old tree; failed reflows
    -- keep the old view and release the replacement's native HTML resources.
    if self[1] then self[1]:free() end
    self[1], self.window, self.scroll, self._displayed_frame = center, window, scroll, frame
    self.edit_button = edit_button
    self:setupKeyboardLinks(scroll, actions)
    if frame.restore_page then
        frame.restore_page, frame.restore_anchor = nil, nil
        frame.ratio = scroll:getCurrentRatio()
    end
    self.built_at = time.now()
    logger.dbg("DPD render ms:", time.to_ms(time.since(started)), "HTML bytes:", #html)
    if Diag.enabled then
        local build_ms = time.to_ms(time.since(started))
        Diag.log("Build end: ms:", build_ms, "HTML bytes:", #html,
            "pages:", scroll.htmlbox_widget.page_count, Diag.memory())
        -- One line per popup: its lookup and first build, before painting.
        if not self.ready_logged then
            self.ready_logged = true
            local lookup_ms = self.lookup_ms
            Diag.log("Popup ready:", self.model and self.model.query, "lookup ms:", lookup_ms or "?",
                "build ms:", build_ms, "total ms:", lookup_ms and (lookup_ms + build_ms) or "?")
        end
    end
end

function Viewer:setupKeyboardLinks(scroll, actions)
    self.keyboard_focus, self.keyboard_buttons = nil, nil
    if not Device:hasKeys() then return end
    if actions then
        local buttons = actions[2]
        self.keyboard_buttons = {}
        for _, entry in ipairs(buttons.buttons[1]) do
            self.keyboard_buttons[#self.keyboard_buttons + 1] = {
                uri = entry.uri, button = buttons:getButtonById(entry.id),
            }
        end
        if buttons.layout then buttons:disableFocusManagement(self) end
        buttons.key_events_enabled = false
    end
    -- The host HTML widget has tap links but no focusable link widgets.
    local box, paint = scroll.htmlbox_widget, scroll.htmlbox_widget.paintTo
    box.paintTo = function(widget, bb, x, y)
        paint(widget, bb, x, y)
        local focus = self.keyboard_focus
        if not focus or focus.box ~= widget or focus.page ~= widget.page_number then return end
        for _, rect in ipairs(focus.target.rects or {}) do
            local left, top = math.max(0, rect.x0 - 2), math.max(0, rect.y0 - 2)
            local right, bottom = math.min(widget.dimen.w, rect.x1 + 2), math.min(widget.dimen.h, rect.y1 + 2)
            bb:paintBorder(x + left, y + top, right - left, bottom - top,
                Screen:scaleBySize(2), Blitbuffer.COLOR_BLACK)
        end
    end
    scroll.scroll_callback = function() self:clearKeyboardFocus() end
end

function Viewer:clearKeyboardFocus()
    local focus = self.keyboard_focus
    if not focus then return end
    if focus.target.button then focus.target.button:onUnfocus() end
    self.keyboard_focus = nil
    UIManager:setDirty(self, "fast")
end

function Viewer:keyboardTargets()
    local box = self.scroll.htmlbox_widget
    local page = box.document:openPage(box.page_number)
    local links = page:getPageLinks() or {}
    page:close()
    table.sort(links, function(a, b)
        if a.y0 ~= b.y0 then return a.y0 < b.y0 end
        return a.x0 < b.x0
    end)
    local targets = {}
    for _, link in ipairs(links) do
        if link.uri and link.x1 > 0 and link.x0 < box.dimen.w
            and link.y1 > 0 and link.y0 < box.dimen.h then
            local last = targets[#targets]
            if last and last.uri == link.uri then
                last.rects[#last.rects + 1] = link
            else
                targets[#targets + 1] = { uri = link.uri, rects = { link } }
            end
        end
    end
    if self.edit_button then
        targets[#targets + 1] = { uri = "dpd:edit-search", button = self.edit_button,
            callback = self.edit_button.callback }
    end
    for _, target in ipairs(self.keyboard_buttons or {}) do
        if target.button.enabled then targets[#targets + 1] = target end
    end
    return targets
end

function Viewer:onFocusLink(direction)
    return self:guard("popup keyboard focus", self.focusLink, self, direction)
end

function Viewer:focusLink(direction)
    if self.closed or self._pending_update then return true end
    local box, focus = self.scroll.htmlbox_widget, self.keyboard_focus
    local targets = self:keyboardTargets()
    local index = focus and focus.box == box and focus.page == box.page_number and focus.index + direction
        or (direction > 0 and 1 or #targets)
    self:clearKeyboardFocus()
    for attempt = 0, box.page_count do
        if targets[index] then
            local target = targets[index]
            self.keyboard_focus = { box = box, page = box.page_number, index = index, target = target }
            if target.button then target.button:onFocus() end
            UIManager:setDirty(self, "fast")
            return true
        end
        if attempt == box.page_count then break end
        if direction > 0 and box.page_number == box.page_count then self.scroll:scrollToRatio(0)
        elseif direction < 0 and box.page_number == 1 then self.scroll:scrollToRatio(1)
        else self.scroll:scrollText(direction) end
        targets = self:keyboardTargets()
        index = direction > 0 and 1 or #targets
    end
    return true
end

function Viewer:onActivateLink()
    if self.closed or self._pending_update then return true end
    local focus, box = self.keyboard_focus, self.scroll.htmlbox_widget
    if not focus or focus.box ~= box or focus.page ~= box.page_number then return self:onFocusLink(1) end
    if focus.target.callback then focus.target.callback()
    else self:onLink(focus.target.uri) end
    return true
end

-- At most this many extra layouts per build to move split rows.
Viewer.split_passes = 3

-- Merge text lines that start at the same top and sit side by side, as the
-- cells of one table row do, into one line ordered left to right.
function Viewer.mergeRowLines(lines)
    local merged = {}
    for _, line in ipairs(lines) do
        local row
        for _, other in ipairs(merged) do
            if other.y0 == line.y0 and (line.x0 >= other.x1 or line.x1 <= other.x0) then row = other; break end
        end
        if row then
            local words = {}
            local left, right = row, line
            if line.x1 <= row.x0 then left, right = line, row end
            for _, word in ipairs(left) do words[#words + 1] = word end
            for _, word in ipairs(right) do words[#words + 1] = word end
            for i, word in ipairs(words) do row[i] = word end
            row.x0, row.x1 = math.min(row.x0, line.x0), math.max(row.x1, line.x1)
            row.y1 = math.max(row.y1, line.y1)
        else
            merged[#merged + 1] = line
        end
    end
    return merged
end

-- MuPDF ignores page-break-before and break-inside here. Move one matching
-- row with a top margin; rows filling most of a page stay split.
function Viewer:moveSplitRow(box, html)
    local document = box and box.document
    if not (document and document.openPage and box.page_count and box.page_count > 1) then return end
    local page_height = box.dimen and box.dimen.h
    if not page_height then return end
    local function rows(number)
        local page = document:openPage(number)
        local links = page:getPageLinks() or {}
        page:close()
        return links
    end
    local before = rows(1)
    for number = 2, box.page_count do
        local here = rows(number)
        local first
        for _, link in ipairs(here) do
            if link.uri and (not first or link.y0 < first.y0) then first = link end
        end
        local top
        for _, link in ipairs(first and before or {}) do
            if link.uri == first.uri then top = math.min(top or link.y0, link.y0) end
        end
        if top and page_height - top < page_height / 3 then
            local pattern = '<div class="entry">(<p class="row[^"]*"><a href="'
                .. Render.escape(first.uri):gsub("%p", "%%%0") .. '")'
            local moved, count = html:gsub(pattern, string.format(
                '<div class="entry" style="margin-top:%.1fpx">%%1', page_height - top), 1)
            if count == 1 then return moved end
        end
        before = here
    end
end

function Viewer:ratio() return self.scroll:getCurrentRatio() end

-- What the title's pencil edits: a lookup's query, as in KOReader's dictionary
-- popup. Tap edits what was selected or typed, hold the form DPD looked up.
-- Views opened from an entry (families, tables, roots) have no query to edit.
local function editable(model)
    if type(model.query) ~= "string" or not model.query:find("%S") then return end
    if model.english then return "english" end
    if model.dictionary_search then return "dictionaries" end
    if Render.isResult(model) then return "pali" end
end

function Viewer:addEditButton(title, frame)
    local mode = self.edit_callback and editable(frame.model)
    if not mode or not title.right_button then return end
    local model, root = frame.model, #self.navigation.stack == 1
    local size = title.right_button.width
    local pencil = IconButton:new{
        icon = "edit", width = size, height = size,
        padding = title.button_padding, padding_bottom = size,
        -- The root's own text is the owner's: a typed draft or the selection.
        callback = function() self:editSearch(not root and (model.original_clean or model.query) or nil, mode, not root) end,
        hold_callback = function() self:editSearch(model.query, mode, not root) end,
        allow_flash = false, show_parent = self,
    }
    -- Left of the close button's widened tap zone, so the two never overlap;
    -- the title is shortened to end before it.
    local x = title.width - title.right_button:getSize().w - pencil:getSize().w
    local text_x = title.inner_title_group[1].width
    title.title_widget:setMaxWidth(math.max(0, x - title.title_h_padding - text_x))
    title.inner_title_group:resetLayout()
    title.title_group:resetLayout()
    table.insert(title, HorizontalGroup:new{ HorizontalSpan:new{ width = x }, pencil })
    return pencil
end

-- A view opened from an entry stays open: its edit opens as a child, so Back
-- returns to it, as when a word held in the popup is edited.
function Viewer:editSearch(text, mode, as_child)
    if self.closed or self.edit_pending or not self.edit_callback then return end
    self.edit_pending = true
    self:defer("edit search", function()
        self.edit_pending = nil
        if as_child then return self.edit_callback(text, mode, self) end
        -- As in KOReader, this popup stays under the editor, so Cancel returns
        -- to it; the search the reader submits replaces it.
        self.edit_callback(text, mode, nil, self)
    end)
end

-- Fixed buttons below the entry, reachable from every page of it. An open
-- article keeps its part controls here, with disabled buttons at either end.
function Viewer:actionRow(frame, width)
    local row = {}
    self.action_buttons = {}
    local function add(id, uri, text, enabled)
        row[#row + 1] = { id = id, uri = uri, text = text, enabled = enabled,
            callback = function() self:tapButton(uri) end }
    end
    local article_open = false
    for key, page in pairs(frame.dictionary_pages or {}) do
        if page.open then
            article_open = true
            if page.part > 1 or page.has_more then
                add("dict-prev", "dpd:dict-prev/" .. key, "◂ Part", page.part > 1)
                add("dict-next", "dpd:dict-next/" .. key, "Part ▸", page.has_more == true)
            end
            add("dict-entry", "dpd:dict-entry/" .. key, "Entries", true)
            break
        end
    end
    -- A search of the other dictionaries offers DPD in that button's place.
    if self.navigation.stack[1].model.dictionary_search then
        add("dpd", "dpd:dpd-lookup", "DPD", frame.model.dictionary_search == true)
    elseif frame.other_dictionaries and not article_open then
        add("dictionaries", "dpd:dictionaries", "Other dictionaries", Render.isResult(frame.model))
    end
    if self.normal_callback then
        local word = self:normalWord()
        add("normal", "dpd:normal", word and word ~= frame.model.query and ("KOReader: " .. word) or "KOReader dictionary", true)
    end
    if #row == 0 then return end
    local buttons = ButtonTable:new{ width = width, buttons = { row }, show_parent = self }
    for _, entry in ipairs(row) do
        self.action_buttons[entry.uri] = buttons:getButtonById(entry.id)
    end
    return VerticalGroup:new{
        LineWidget:new{ dimen = Geom:new{ w = width, h = Size.line.medium } },
        buttons,
    }
end

function Viewer:normalWord()
    local selected = self.navigation.stack[1].model
    return self.normal_word or selected.original_clean or selected.original or selected.query
end

-- A button tap right after a rebuild is a bounce of the tap that caused it.
function Viewer:tapButton(uri)
    if self.closed or self._pending_update then return end
    if self.built_at and time.now() - self.built_at < time.s(self.link_guard_s) then
        Diag.log("Tap ignored right after a rebuild:", uri)
        return
    end
    self:onLink(uri)
end

-- All UI boundaries log errors even with diagnostics off. An unexpected state
-- error dismisses this popup and its owned children, leaving its parent live.
function Viewer:guard(label, fn, ...)
    local ok, result = Diag.protect(label, fn, ...)
    if not ok then self:recover(result); return false end
    return result
end

function Viewer:reportError(err)
    Diag.protect("popup error message", self.showError, self, err)
end

function Viewer:recover(err)
    if self._recovering then return end
    self._recovering = true
    self:close()
    -- A failed dictionary handoff must relinquish the original selection even
    -- if the popup has already closed with transfer_selection=true.
    if self.transfer_selection and self.release_selection_callback then
        Diag.protect("failed handoff cleanup", self.release_selection_callback)
    end
    self:reportError(err)
    self._recovering = nil
end

function Viewer:onTapText(widget, ges)
    local result = self:guard("popup tap", self.tapLink, self, widget, ges)
    -- Consume a failed tap so it cannot be delivered to the revealed parent.
    if result == false then return true end
    return result
end

function Viewer:tapLink(widget, ges)
    -- Old links remain visible until the queued rebuild runs; a bounce must
    -- not undo the action which queued it.
    if self.closed or self._pending_update then return true end
    local link = self:linkAt(widget, ges.pos)
    if not link then return end
    local now = ges.time or time.now()
    if self.built_at and now - self.built_at < time.s(self.link_guard_s) then
        Diag.log("Tap ignored right after a rebuild:", link.uri)
        return true
    end
    self:onLink(link.uri)
    return true
end

function Viewer:defer(label, action)
    UIManager:nextTick(function()
        if self.closed then return end
        self:guard(label, action)
    end)
end

-- MuPDF returns one rectangle per wrapped link line. Join adjacent lines of
-- this cell, without joining the duplicate pager at the article's other end.
function Viewer:buttonBounds(link, links)
    local cell = self.control_layout and self.control_layout.buttons[link.uri]
    if not cell then return end
    local font_px = self.font_px or Screen:scaleBySize(self.font_size)
    local x = (link.x0 + link.x1) / 2
    local last_line = link
    local top, bottom, line_height = link.y0, link.y1, link.y1 - link.y0
    local changed = true
    while changed do
        changed = false
        for _, other in ipairs(links) do
            if other.uri == link.uri and math.abs((other.x0 + other.x1) / 2 - x) < font_px * .3
                and other.y0 <= bottom + font_px * .5 and other.y1 >= top - font_px * .5 then
                local next_top, next_bottom = math.min(top, other.y0), math.max(bottom, other.y1)
                line_height = math.max(line_height, other.y1 - other.y0)
                if other.y0 > last_line.y0 then last_line = other end
                if next_top ~= top or next_bottom ~= bottom then
                    top, bottom, changed = next_top, next_bottom, true
                end
            end
        end
    end
    -- A wrapped line's trailing space shifts its reported centre slightly.
    -- The final line has no wrap space and retains the cell's actual centre.
    x = (last_line.x0 + last_line.x1) / 2
    local w = cell.width_em * font_px
    local h = cell.height_em * font_px + bottom - top - line_height
    local y = (top + bottom) / 2
    return { x0 = x - w / 2, x1 = x + w / 2, y0 = y - h / 2, y1 = y + h / 2 }
end

--- Prefer text rectangles, then full button cells and compact sense rows,
--- then the nearest small link within a third of a line. Misses are logged.
function Viewer:linkAt(widget, abs_pos)
    local pos = widget:getPosFromAbsPos(abs_pos)
    if not pos then return end
    local page = widget.document:openPage(widget.page_number)
    local links = page:getPageLinks() or {}
    page:close()
    local font_px = self.font_px or Screen:scaleBySize(self.font_size)
    local pad, radius = math.floor(font_px * .45) + Screen:scaleBySize(1), math.floor(font_px / 3)
    local nearest, best
    for _, link in ipairs(links) do
        if pos.x >= link.x0 and pos.x < link.x1 and pos.y >= link.y0 and pos.y < link.y1 then return link end
    end
    for _, link in ipairs(links) do
        local bounds = self:buttonBounds(link, links)
        if bounds then
            if pos.x >= bounds.x0 and pos.x < bounds.x1
                and pos.y >= bounds.y0 and pos.y < bounds.y1 then return link end
        elseif isButtonLink(link.uri) and pos.y >= link.y0 - pad and pos.y < link.y1 + pad then return link end
    end
    -- Compact sense rows keep their existing margins. Extend taps a little
    -- into that whitespace, bounded halfway to neighboring link rows.
    for _, link in ipairs(links) do
        if link.uri:match("/sense/%d+$") or link.uri:match("^dpd:sense/%d+$")
            or link.uri:match("dict%-entry/%d+/%d+$")
            or link.uri:match("component%-sense/%d+/%d+/%d+$") then
            local top, bottom = link.y0, link.y1
            for _, line in ipairs(links) do
                if line.uri == link.uri then
                    top, bottom = math.min(top, line.y0), math.max(bottom, line.y1)
                end
            end
            local upper, lower = top - font_px * .15, bottom + font_px * .15
            for _, other in ipairs(links) do
                if other.uri ~= link.uri then
                    if other.y1 <= top then upper = math.max(upper, (other.y1 + top) / 2) end
                    if other.y0 >= bottom then lower = math.min(lower, (bottom + other.y0) / 2) end
                end
            end
            if pos.y >= upper and pos.y < lower then return link end
        end
    end
    for _, link in ipairs(links) do
        local dx = math.max(link.x0 - pos.x, 0, pos.x - link.x1)
        local dy = math.max(link.y0 - pos.y, 0, pos.y - link.y1)
        local distance = math.sqrt(dx * dx + dy * dy)
        if not best or distance < best then nearest, best = link, distance end
    end
    if nearest and best <= radius then return nearest end
    if Diag.enabled then
        Diag.log("Tap on no link at", math.floor(pos.x), math.floor(pos.y), "nearest:",
            nearest and nearest.uri or "none", best and math.floor(best) or "")
    end
end

-- When a toggle adds or removes content above itself, its link moves off the
-- kept page. Search pages in the direction it moved, checking only a bounded
-- number of pages; nil keeps the old page.
function Viewer:findAnchor(box, anchor, page)
    local span = anchor.pages or self.anchor_search_pages
    local last = anchor.direction < 0 and math.max(1, page - span)
        or math.min(box.page_count, page + span)
    for candidate = page, last, anchor.direction do
        local opened = box.document:openPage(candidate)
        local links = opened:getPageLinks()
        opened:close()
        for _, link in ipairs(links) do
            if link.uri == anchor.uri then return candidate end
        end
    end
end

-- Locate the unique section heading in the existing rendered window before
-- replacing it. This makes even the bottom pager return to the new readings'
-- start; the search never lays out the remaining database readings.
function Viewer:sectionPage(uri)
    local box = self.scroll and self.scroll.htmlbox_widget
    if not box then return end
    for number = 1, box.page_count do
        local page = box.document:openPage(number)
        local links = page:getPageLinks() or {}
        page:close()
        for _, link in ipairs(links) do if link.uri == uri then return number end end
    end
end

-- Keep the tapped control on screen after an in-place expansion. Content
-- usually changes only below the control, so its page stays the same;
-- direction (-1 or 1) marks changes above it, which move the control.
function Viewer:keepPlace(frame, uri, direction)
    if not self.scroll then return end
    frame.restore_page = self.scroll.htmlbox_widget.page_number
    frame.restore_anchor = direction and { uri = uri, direction = direction } or nil
end

-- `resize` marks a reflow of unchanged content. Every other update has
-- already changed the state the old view's links resolve against.
function Viewer:update(resize)
    if self.closed then return end
    if not resize then self._content_changed = true end
    if self._pending_update then return end
    local action
    action = function()
        if self.closed or self._pending_update ~= action then return end
        self._pending_update = nil
        local changed = self._content_changed
        self._content_changed = nil
        local ok, err = Diag.protect("popup rebuild", self.build, self)
        if not ok then
            -- A failed reflow keeps the old view. After any other change, its
            -- controls would act on hidden state: Next part would skip a part.
            if changed then return self:recover(err) end
            self:reportError(err)
        end
        Diag.protect("popup redraw", UIManager.setDirty, UIManager, self, "ui")
    end
    self._pending_update = action
    UIManager:nextTick(action)
end

function Viewer:onSetDimensions(dimen)
    return self:guard("popup resize", self.setDimensions, self, dimen)
end

function Viewer:setDimensions(dimen)
    if self.closed then return end
    dimen = dimen or Screen:getSize()
    if dimen.w == self.dimen.w and dimen.h == self.dimen.h then return end
    local frame = self.navigation:current()
    -- A navigation action may already be queued. Its target frame's saved ratio
    -- must not be overwritten with the still-visible previous frame's scroll.
    if frame == self._displayed_frame then frame.ratio = self:ratio() end
    self.dimen = Geom:new{ w = dimen.w, h = dimen.h }
    self:update(true)
end

-- SDL and Android broadcast both events for the same resize. The geometry check
-- and queued update ensure that these events produce a single reflow.
Viewer.onScreenResize = Viewer.onSetDimensions

function Viewer:showError(err)
    logger.warn("DPD:", err)
    Diag.log("Popup error:", err)
    UIManager:show(InfoMessage:new{ text = "DPD could not open this view. Try again.\n\n"
        .. "If it keeps failing, turn on Help → Diagnostics → Write diagnostic log in the DPD menu and include the log in a bug report." })
end

function Viewer:clearTextSelection()
    local box = not self.closed and self.scroll and self.scroll.htmlbox_widget
    if box and box.clearHighlight and box:clearHighlight() and box.redrawHighlight then box:redrawHighlight() end
end

function Viewer:lookupSelection(text)
    return self:guard("popup selection", self.followSelection, self, text)
end

function Viewer:followSelection(text)
    if self.closed or type(text) ~= "string" or not text:find("%S") then return false end
    if not self.selection_callback then self:clearTextSelection(); return false end
    -- Arbitrary popup text is a separate selection. Never manufacture a book
    -- highlight or transfer the root popup's book-cleanup ownership to it.
    local cleared = false
    local clear = function()
        if cleared then return end
        cleared = true
        self:clearTextSelection()
    end
    local ok, result = pcall(self.selection_callback, text, clear)
    if not ok then clear(); self:showError(result); return false end
    if not result then clear() end
    return result
end

-- Contain navigation errors here; deferred actions and taps have their own
-- boundaries because they also execute outside this call.
function Viewer:onLink(uri)
    Diag.log("Link:", uri)
    return self:guard("popup link", self.followLink, self, uri)
end

-- Load a view and open it over the current one. A load error shows a message;
-- nothing to show leaves the popup as it is.
function Viewer:openView(ratio, load, ...)
    local ok, model = pcall(load, self.lookup, ...)
    if not ok then return self:showError(model) end
    if not model then return end
    self.navigation:push(model, ratio)
    self:update()
end

function Viewer:followLink(uri)
    if self.closed or type(uri) ~= "string" then return end
    local root_frame = self.navigation:current()
    local frame = root_frame
    local ratio = self:ratio()
    frame.ratio = ratio
    local scoped_detail, tapped = nil, uri
    frame, uri, scoped_detail = self.navigation:resolve(uri)
    if not frame then return end
    local similar_index = tonumber(uri:match("^dpd:similar/(%d+)$"))
    local analysis_index = tonumber(uri:match("^dpd:analysis/(%d+)$"))
    local sense_id = tonumber(uri:match("^dpd:sense/(%d+)$"))
    local suggestion_index = tonumber(uri:match("^dpd:suggestion/(%d+)$"))
    local reference_index = tonumber(uri:match("^dpd:reference/(%d+)$"))
    local reference_toggle = tonumber(uri:match("^dpd:reference%-toggle/(%d+)$"))
    local grammar_index = tonumber(uri:match("^dpd:grammar%-sense/(%d+)$"))
    local component_a, component_p, component_id = uri:match("^dpd:component%-sense/(%d+)/(%d+)/(%d+)$")
    local detail_id, target_index = uri:match("^dpd:detail%-target/(%d+)/(%d+)$")
    local family_id, family_group = uri:match("^dpd:detail%-family/(%d+)/(%d+)$")
    local paradigm_id = tonumber(uri:match("^dpd:detail%-paradigm/(%d+)$"))
    local root_details = tonumber(uri:match("^dpd:root%-details/(%d+)$"))
    local root_matrix = tonumber(uri:match("^dpd:root%-matrix/(%d+)$"))
    local matrix_group, matrix_row = uri:match("^dpd:matrix%-row/(%d+)/(%d+)$")
    local matrix_item = tonumber(uri:match("^dpd:matrix%-item/(%d+)$"))
    local english_item = tonumber(uri:match("^dpd:english%-item/(%d+)$"))
    local spelling_item = tonumber(uri:match("^dpd:spelling/(%d+)$"))
    local part_side = uri:match("^dpd:part/(%a+)$")
    local dict_toggle_g, dict_toggle_e = uri:match("^dpd:dict%-entry/(%d+)/(%d+)$")
    local dict_step, dict_step_g, dict_step_e = uri:match("^dpd:dict%-(%a+)/(%d+)/(%d+)$")
    if dict_step ~= "next" and dict_step ~= "prev" then dict_step = nil end
    local dict_entries_g = tonumber(uri:match("^dpd:dict%-entries/(%d+)$"))
    local frequency_id = tonumber(uri:match("^dpd:detail%-frequency/(%d+)$"))
    local sutta_id = tonumber(uri:match("^dpd:detail%-sutta/(%d+)$"))
    local paradigm_form = tonumber(uri:match("^dpd:paradigm%-form/(%d+)$"))
    local root_index, root_group = uri:match("^dpd:root%-family/(%d+)/(%d+)$")
    local family_item = tonumber(uri:match("^dpd:family%-item/(%d+)$") or uri:match("^dpd:family%-member/(%d+)$"))
    local a, p = uri:match("^dpd:component/(%d+)/(%d+)$")
    if detail_id then
        detail_id, target_index = tonumber(detail_id), tonumber(target_index)
        local detail = scoped_detail or (frame.expanded[detail_id] and frame.details[detail_id])
        local target = detail and detail.targets and detail.targets[target_index]
        if not target or not target.model then return end
        self.navigation:push(target.model, ratio)
        self:update()
    elseif family_id or root_index then
        local groups
        if family_id then
            family_id = tonumber(family_id)
            local detail = scoped_detail or (frame.expanded[family_id] and frame.details[family_id])
            groups = detail and detail.families
        else
            local root = (frame.model.roots or {})[tonumber(root_index)]
            groups = root and root.families
        end
        local group = groups and groups[tonumber(family_group or root_group)]
        if not group then return end
        self:openView(ratio, self.lookup.family, group.kind, group.key)
    elseif frequency_id then
        local detail = scoped_detail or (frame.expanded[frequency_id] and frame.details[frequency_id])
        if not detail or not (detail.has_frequency == 1 or detail.has_frequency == true) then return end
        self:openView(ratio, self.lookup.frequency, frequency_id)
    elseif sutta_id then
        local detail = scoped_detail or (frame.expanded[sutta_id] and frame.details[sutta_id])
        if not detail or not detail.sutta_kind then return end
        self:openView(ratio, self.lookup.sutta, sutta_id)
    elseif root_matrix then
        local root = (frame.model.roots or {})[root_matrix]
        if not root then return end
        self:openView(ratio, self.lookup.rootMatrix, root.root)
    elseif matrix_group then
        local matrix = frame.model.root_matrix
        if not matrix then return end
        self:openView(ratio, self.lookup.rootMatrix, matrix.root, tonumber(matrix_group), tonumber(matrix_row))
    elseif matrix_item then
        local row = frame.model.matrix_row
        local item = row and row.items[matrix_item]
        if not item then return end
        self:openView(ratio, self.lookup.byId, item.id)
    elseif root_details then
        local root = (frame.model.roots or {})[root_details]
        if not root then return end
        self:openView(ratio, self.lookup.rootDetails, root.root)
    elseif paradigm_id then
        local detail = scoped_detail or (frame.expanded[paradigm_id] and frame.details[paradigm_id])
        if not detail or not detail.paradigm_kind then return end
        self:openView(ratio, self.lookup.paradigm, paradigm_id, frame.model.query)
    elseif paradigm_form then
        local value = frame.model.paradigm
        local form = value and value.forms and value.forms[paradigm_form]
        if not form then return end
        local ok, model = pcall(self.lookup.get, self.lookup, form, { approximate = false })
        if not ok then return self:showError(model) end
        if not model.found then
            return UIManager:show(InfoMessage:new{ text = "No DPD entry for “" .. form .. "”.", timeout = 2 })
        end
        self.navigation:push(model, ratio)
        self:update()
    elseif family_item then
        local family = frame.model.family
        local member = family and family.items and family.items[family_item]
        if not member or not member.available then return end
        local ok, model = pcall(self.lookup.headword, self.lookup, member.lemma)
        if not ok then return self:showError(model) end
        if not model or not model.found then return end
        self.navigation:push(model, ratio)
        self:update()
    elseif uri == "dpd:dpd-lookup" then
        -- The searched text in DPD, over the search; Back returns to it.
        if not frame.model.dictionary_search then return end
        self:openView(ratio, self.lookup.get, frame.model.query, { spelling = true })
    elseif uri == "dpd:dictionaries" then
        if not frame.other_dictionaries then return end
        self:openView(ratio, self.lookup.otherDictionaries, frame.model, self.dictionaries)
    elseif dict_entries_g then
        local value = frame.model.dictionaries
        local group = value and value.groups[dict_entries_g]
        if not group or #group.entries >= (group.total or 0) then return end
        local ok, err = pcall(self.lookup.moreDictionaryEntries, self.lookup, group)
        if not ok then return self:showError(err) end
        if self.scroll then root_frame.restore_page = self.scroll.htmlbox_widget.page_number end
        self:update()
    elseif dict_toggle_g or dict_step then
        -- One part of one article is held and laid out at a time: opening an
        -- entry closes the others, collapsing frees its part, and Previous
        -- and Next part replace it. Keep reading pages relative to the title,
        -- since closing another article can move that title by many pages.
        local g, e = tonumber(dict_toggle_g or dict_step_g), tonumber(dict_toggle_e or dict_step_e)
        local value = frame.model.dictionaries
        local entry = value and value.groups[g] and value.groups[g].entries[e]
        if not entry then return end
        frame.dictionary_pages = frame.dictionary_pages or {}
        local key = g .. "/" .. e
        local page = frame.dictionary_pages[key]
        if self.scroll then
            for other_key, other in pairs(frame.dictionary_pages) do
                if other.open then
                    local heading = self:sectionPage("dpd:dict-entry/" .. other_key)
                    if heading then
                        other.reading_pages = other.reading_pages or {}
                        other.reading_pages[other.offset] = math.max(0, self.scroll.htmlbox_widget.page_number - heading)
                    end
                end
            end
        end
        if dict_toggle_g and page and page.open then
            page.open, page.html = false, nil
            if self.scroll then
                root_frame.restore_page = 1
                root_frame.restore_anchor = { uri = "dpd:dict-entry/" .. key, direction = 1, pages = math.huge }
            end
            return self:update()
        end
        local offset, starts = 0, {}
        local resume = not dict_step and page
        local reading_pages = page and page.reading_pages or {}
        if resume then
            offset = page.offset
            for i, start in ipairs(page.starts) do starts[i] = start end
        elseif dict_step then
            if not (page and page.open) then return end
            if dict_step == "next" then
                if not page.has_more then return end
                offset = page.next_offset
                for i, start in ipairs(page.starts) do starts[i] = start end
                starts[#starts + 1] = page.offset
            else
                if #page.starts == 0 then return end
                for i = 1, #page.starts - 1 do starts[i] = page.starts[i] end
                offset = page.starts[#page.starts]
            end
        end
        local ok, loaded = pcall(self.lookup.dictionaryPage, self.lookup, entry.id, offset)
        -- An article whose length changed, such as after the database was
        -- replaced, has other part boundaries: start it from the top.
        if ok and loaded and resume and (loaded.total ~= page.total or loaded.html == "") then
            offset, starts, reading_pages = 0, {}, {}
            ok, loaded = pcall(self.lookup.dictionaryPage, self.lookup, entry.id, 0)
        end
        if not ok then return self:showError(loaded) end
        if not loaded then return end
        for _, other in pairs(frame.dictionary_pages) do other.open, other.html = false, nil end
        frame.dictionary_pages[key] = { open = true, html = loaded.html, offset = loaded.offset,
            next_offset = loaded.next_offset, total = loaded.total, has_more = loaded.has_more,
            starts = starts, part = #starts + 1, reading_pages = reading_pages }
        if self.scroll then
            root_frame.restore_page = 1
            -- The bottom part control bounds the article; a whole one-part
            -- entry shares its boundary page with the following entry heading.
            local last_uri = loaded.has_more and ("dpd:dict-next/" .. key)
                or #starts > 0 and ("dpd:dict-prev/" .. key)
            if not last_uri then
                for next_g = g, #value.groups do
                    local next_e = next_g == g and e + 1 or 1
                    if value.groups[next_g].entries[next_e] then
                        last_uri = "dpd:dict-entry/" .. next_g .. "/" .. next_e
                        break
                    end
                end
            end
            root_frame.restore_anchor = { uri = "dpd:dict-entry/" .. key, direction = 1, pages = math.huge,
                offset = reading_pages[loaded.offset], last_uri = last_uri }
        end
        self:update()
    elseif spelling_item then
        local item = (frame.model.spelling_suggestions or {})[spelling_item]
        if not item then return end
        local ok, model = pcall(self.lookup.get, self.lookup, item.text, { approximate = false })
        if not ok then return self:showError(model) end
        if not model.found then return end
        self.navigation:push(model, ratio)
        self:update()
    elseif english_item then
        local english = frame.model.english
        local item = english and english.items[english_item]
        if not item then return end
        -- Root meanings name a numbered root (√kal 3), which only the root
        -- reader knows; every other item is a headword.
        local ok, model
        if item.pos == "root" then
            ok, model = pcall(self.lookup.target, self.lookup, item.lemma, "root")
        else
            ok, model = pcall(self.lookup.headword, self.lookup, item.lemma)
        end
        if not ok then return self:showError(model) end
        if not model or not model.found then
            return UIManager:show(InfoMessage:new{ text = "No DPD entry for “" .. item.lemma .. "”.", timeout = 2 })
        end
        self.navigation:push(model, ratio)
        self:update()
    elseif uri == "dpd:english-more" then
        if not frame.model.english or not frame.model.english.has_more then return end
        local ok, model = pcall(self.lookup.moreEnglish, self.lookup, frame.model)
        if not ok then return self:showError(model) end
        if self.scroll then root_frame.restore_page = self.scroll.htmlbox_widget.page_number end
        frame.model = model
        self:update()
    elseif uri == "dpd:family-more" then
        if not frame.model.family or not frame.model.family.has_more then return end
        local ok, model = pcall(self.lookup.moreFamily, self.lookup, frame.model)
        if not ok then return self:showError(model) end
        if not model then return end
        if self.scroll then root_frame.restore_page = self.scroll.htmlbox_widget.page_number end
        frame.model = model
        self:update()
    elseif component_a then
        component_a, component_p, component_id = tonumber(component_a), tonumber(component_p), tonumber(component_id)
        -- Check before reading the detail: hidden controls read nothing.
        if not self.navigation:componentSense(component_a, component_p, component_id, frame) then return end
        local detail = frame.component_details and frame.component_details[component_a]
        detail = detail and detail[component_p] and detail[component_p][component_id]
        if not detail then
            local ok, result = pcall(self.lookup.detail, self.lookup, component_id)
            if not ok then return self:showError(result) end
            detail = result
        end
        self:keepPlace(root_frame)
        self.navigation:toggleComponentSense(component_a, component_p, component_id, detail, frame)
        self:update()
    elseif similar_index then
        self:keepPlace(root_frame)
        self.navigation:toggleSuggestion(similar_index, frame)
        self:update()
    elseif reference_toggle then
        self:keepPlace(root_frame)
        self.navigation:toggleReference(reference_toggle, frame)
        self:update()
    elseif uri == "dpd:grammar-toggle" then
        -- The extra parses are inserted (or removed) above this toggle.
        self:keepPlace(root_frame, tapped, frame.grammar_open and -1 or 1)
        frame.grammar_open = not frame.grammar_open
        self:update()
    elseif uri == "dpd:variants-toggle" then
        self:keepPlace(root_frame)
        frame.variants_open = not frame.variants_open
        self:update()
    elseif uri == "dpd:attestations-toggle" then
        self:keepPlace(root_frame)
        frame.attestations_open = not frame.attestations_open
        self:update()
    elseif uri == "dpd:variants-next" or uri == "dpd:variants-prev" then
        if not frame.variants_open then return end
        local total = #(frame.model.variants or {})
        local _, _, current = Render.variantRange(total, frame.variants_page)
        local step = uri == "dpd:variants-next" and 1 or -1
        local _, _, next_page = Render.variantRange(total, current + step)
        if next_page == current then return end
        local heading = tapped:gsub("variants%-%a+$", "variants-toggle")
        root_frame.restore_page = self:sectionPage(heading) or 1
        root_frame.restore_anchor = nil
        frame.variants_page = next_page
        self:update()
    elseif uri == "dpd:more" then
        local ok, model = pcall(self.lookup.more, self.lookup, frame.model)
        if not ok then return self:showError(model) end
        if not model then return end
        if self.scroll then root_frame.restore_page = self.scroll.htmlbox_widget.page_number end
        self.navigation:extend(model, frame)
        self:update()
    elseif reference_index then
        local reference = (frame.model.references or {})[reference_index]
        if not reference or not reference.model then return end
        self.navigation:push(reference.model, ratio)
        self:update()
    elseif grammar_index then
        local parse = (frame.model.grammar or {})[grammar_index]
        if not parse then return end
        self:openView(ratio, self.lookup.headword, parse.headword, frame.model)
    elseif analysis_index then
        self:keepPlace(root_frame)
        self.navigation:toggleAnalysis(analysis_index, frame)
        self:update()
    elseif sense_id then
        local valid, closes_above = false, false
        for _, sense in ipairs(frame.model.senses or {}) do
            if sense.id == sense_id then valid = true; break end
            -- Only one sense stays open, so opening this one closes any above it.
            if frame.expanded[sense.id] then closes_above = true end
        end
        if not valid then return end
        local ok, detail = pcall(self.lookup.detail, self.lookup, sense_id)
        if not ok then return self:showError(detail) end
        self:keepPlace(root_frame, tapped, closes_above and -1 or nil)
        self.navigation:toggleSense(sense_id, detail, frame)
        self:update()
    elseif suggestion_index then
        local suggestion = (frame.model.suggestions or {})[suggestion_index]
        if not suggestion then return end
        self.navigation:push(suggestion.model, ratio)
        self:update()
    elseif a then
        local analysis = frame.model.deconstructions[tonumber(a)]
        local part = analysis and analysis.parts and analysis.parts[tonumber(p)]
        if not part then return end
        self:openView(ratio, self.lookup.get, part, { approximate = false })
    elseif uri == "dpd:edit-search" and #self.navigation.stack == 1 then
        self:editSearch()
    elseif part_side then
        local part = ((frame.model.long_miss and frame.model.parts) or {})[part_side]
        if not part then return end
        self.navigation:push(part.model, ratio)
        self:update()
    elseif uri == "dpd:normal" and self.normal_callback then
        -- The popup's own selection, not the title of a view opened from it
        -- (Word family: dhamma, dhamma 1.01, √dhar 1).
        local word = self:normalWord()
        self:defer("dictionary handoff", function()
            self:close(true)
            self.normal_callback(word)
        end)
    end
end

function Viewer:back()
    return self:guard("popup Back", function()
        if self.navigation:back() then self:update() else self:close() end
        return true
    end)
end

function Viewer:onBack() return self:back() end
function Viewer:onTapOutside(_, ges)
    return self:guard("popup outside tap", function()
        if self.window.dimen and not self.window.dimen:contains(ges.pos) then self:close() end
        return true
    end)
end

-- Complete every cleanup step even if an earlier callback fails. Mark each
-- callback consumed before invoking it so repeated events never replay it.
function Viewer:closeStep(label, fn, ...)
    local ok, err = Diag.protect(label, fn, ...)
    if not ok and not self._close_error then self._close_error = err end
end

function Viewer:beforeClose()
    local callback = self.before_close_callback
    self.before_close_callback = nil
    if callback then self:closeStep("popup child cleanup", callback) end
end

function Viewer:close(transfer_selection)
    if self.closed or self.closing then return end
    self.closing = true
    self.transfer_selection = transfer_selection
    self:beforeClose()
    local ok, err = Diag.protect("popup dismissal", UIManager.close, UIManager, self)
    if not ok then
        self:finishClose()
        self:reportError(err)
    end
end

function Viewer:onCloseWidget()
    -- Keep the nil return so KOReader can propagate CloseWidget to children.
    local ok, err = Diag.protect("popup close", self.finishClose, self)
    if not ok then self:reportError(err) end
end

function Viewer:finishClose()
    if self.closed then return end
    self.closing = true
    self:beforeClose()
    self.closed = true
    if self._pending_update then
        local action = self._pending_update
        self._pending_update = nil
        self:closeStep("popup cancel rebuild", UIManager.unschedule, UIManager, action)
    end
    local callback = self.close_callback
    self.close_callback = nil
    if callback then self:closeStep("popup owner cleanup", callback, self.transfer_selection) end
    self:closeStep("popup close redraw", UIManager.setDirty, UIManager, nil, "ui")
    if self._close_error then
        local err = self._close_error
        self._close_error = nil
        self:reportError(err)
    end
end

function Viewer:onShow() UIManager:setDirty(self, "ui"); return true end

return Viewer
