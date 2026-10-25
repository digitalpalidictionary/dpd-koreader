local M = { variant_page = 50 }
local Normalize = require("dpd/normalize")
M.css = [[
@page { margin: 0; font-family: 'Noto Sans'; }
body { margin: 0; padding: 0; font-family: 'Noto Sans'; line-height: 1.25; }
/* A word longer than a line (abhivādanapaccuṭṭhāna…, 107 letters, and its
   IPA) breaks at the edge instead of being cut off. Table columns still
   size to their longest words. */
body { overflow-wrap: break-word; }
table { overflow-wrap: normal; }
/* Underlined links open something; chevron toggles (.toggle) expand in place. */
a[href] { color: #000; text-decoration: underline; }
a.toggle, .footer a, a.plain { text-decoration: none; }
/* MuPDF lets the link's rule override <u>, so restate it for the underlined word. */
a.plain u { text-decoration: underline; }
table.actions { border-collapse: collapse; table-layout: fixed; margin: .3em 0; }
table.actions td.action { border: 1px solid #000; text-align: center; vertical-align: middle; }
table.actions a { text-decoration: none; }
p { margin: .3em 0; }
h3 { font-size: 1em; font-weight: bold; margin: .7em 0 .35em; border-top: 1px solid #000; padding-top: .35em; }
h3.lead { margin-top: 0; border-top: 0; padding-top: 0; }
h3 .quiet { font-weight: normal; }
.header { font-size: .85em; margin-bottom: .7em; }
.grammar { font-size: .85em; margin: .15em 0; }
.grammar-more { margin-bottom: .5em; }
.grammar-parse { white-space: nowrap; }
.grammar a.toggle { white-space: nowrap; }
.entry { margin: .35em 0; padding: .15em 0; }
.article { margin: .3em 0 .3em .6em; }
.article p { margin: .3em 0; }
.article blockquote { margin: .3em 0 .3em 1em; }
.article table { border-collapse: collapse; }
.article .src { font-size: .8em; color: #666; }
.article td, .article th { vertical-align: top; padding: .15em .4em .15em 0; border-top: 1px solid #888; }
.row { margin: 0; padding-left: .95em; text-indent: -.95em; }
.row.still { text-indent: 0; }
.components { margin: .2em 0 .4em .95em; }
.component { margin: .25em 0; }
.component p { margin: .12em 0; }
.component p + p { margin-left: .7em; }
/* Only the component's own sense rows step in, not the fields of an opened sense. */
.component .detail p { margin-left: 0; }
.count { font-size: .85em; }
.detail { margin: .3em 0 .6em .95em; border-left: 1px solid #000; padding-left: .65em; font-size: .9em; }
/* MuPDF adds a paragraph's bottom margin at its first <br>, splitting verse,
   so expanded senses space their paragraphs with top margins only. */
.detail p { margin: .18em 0 0; }
.detail p.meta, .detail .cite { font-size: .9em; }
.detail p.example { margin-top: .5em; }
.detail .item { white-space: nowrap; }
table.fields { border-collapse: collapse; table-layout: fixed; width: 100%; margin: .18em 0 0; }
/* Baselines keep MuPDF's linked words level with plain text and labels. */
table.fields td { vertical-align: baseline; padding: .18em .3em 0 0; }
table.fields td.label { font-style: italic; padding-right: .6em; }
.provenance { margin: .2em 0 .5em .95em; font-size: .85em; }
.similar { margin: .4em 0 .8em; border-top: 1px solid #000; padding-top: .4em; }
.similar-body { margin-left: .8em; }
/* A card at the top of a view sits right under the title bar's rule. */
.first { margin-top: 0; border-top: 0; padding-top: 0; }
.note { font-size: .9em; margin-top: .8em; }
.more { margin-top: .8em; }
.footer { margin-top: .8em; border: 1px solid #000; text-align: center; padding: .4em .6em; }
.section { font-weight: bold; margin: .8em 0 .2em; }
.section .count { font-weight: normal; }
table.paradigm { border-collapse: collapse; width: 100%; table-layout: fixed; margin: .2em 0 .5em; }
table.paradigm th { font-size: .9em; font-weight: normal; font-style: italic; text-align: left;
    border-bottom: 1px solid #000; padding: .1em .3em; }
table.paradigm td { vertical-align: top; padding: .2em .3em; border-bottom: 1px solid #888; }
table.paradigm td.case { font-size: .9em; font-style: italic; }
table.paradigm p.form { margin: 0; padding: .15em 0; }
/* KOReader's MuPDF ignores inline backgrounds, so mark the form instead. */
.selected { font-weight: bold; }
table.freq { border-collapse: collapse; font-size: .85em; margin: .3em 0 .6em; }
table.freq th { font-weight: normal; text-align: left; padding: .1em .35em; }
table.freq th.corpus { font-weight: bold; text-align: center; border-bottom: 1px solid #000; }
table.freq th.part { text-align: right; font-style: italic; }
table.freq th.section { font-weight: bold; padding-top: .45em; border-bottom: 1px solid #000; }
table.freq td { text-align: right; padding: .1em .35em; border-bottom: 1px solid #888; }
table.freq td.high { background-color: #ccc; font-weight: bold; }
]]

-- Imported dictionary tables cannot shrink below their longest words, so at
-- large popup fonts they render at most at font 22, where they fit the popup.
M.table_font_max = 22
function M.cssFor(font_size)
    font_size = tonumber(font_size) or 16
    local css = M.css
    if font_size > M.table_font_max then
        css = css .. string.format("\n.article table { font-size: %.3fem; }\n", M.table_font_max / font_size)
    end
    return css
end

function M.escape(text)
    return (tostring(text or ""):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
        :gsub('"', "&quot;"):gsub("'", "&#39;"))
end

-- Keep supported, attribute-free inline markup from DPD while escaping text
-- and all other tags. Do not allow source fields to introduce popup controls.
function M.inline(text)
    local output, stack, start = {}, {}, 1
    text = tostring(text or "")
    local allowed = { b=true, strong=true, i=true, em=true, sub=true, sup=true }
    -- Includes allowed names, so unbalanced or attributed b/i tags vanish
    -- instead of showing as text; anything else (script, img) stays escaped.
    local dropped = { a=true, span=true, font=true, div=true, p=true, small=true, big=true,
        u=true, s=true, abbr=true, cite=true, code=true, mark=true,
        b=true, strong=true, i=true, em=true, sub=true, sup=true }
    local entities = { amp=true, lt=true, gt=true, quot=true, apos=true, nbsp=true }
    local function escaped(value)
        return M.escape(value):gsub("&amp;([#%w]+);", function(entity)
            if entities[entity] or entity:match("^#%d+$") or entity:match("^#x[%da-fA-F]+$") then
                return "&" .. entity .. ";"
            end
            return "&amp;" .. entity .. ";"
        end):gsub("\n", "<br>")
    end
    while true do
        local first, last = text:find("<[^<>]*>", start)
        output[#output + 1] = escaped(text:sub(start, first and first - 1 or #text))
        if not first then break end
        local tag = text:sub(first, last)
        -- A tag name must follow "<" directly, so prose such as "a < b > c"
        -- stays text. Other elements (DPD's <a href>, <span>) are dropped,
        -- keeping their words but never their attributes or links.
        local slash, name = tag:match("^<(/?)([%a]+)%s*>$")
        name = name and name:lower()
        if name and allowed[name] and (slash == "" or stack[#stack] == name) then
            output[#output + 1] = "<" .. slash .. name .. ">"
            if slash == "" then stack[#stack + 1] = name else table.remove(stack) end
        elseif tag:lower():match("^<br%s*/?%s*>$") then
            output[#output + 1] = "<br>"
        elseif dropped[(tag:match("^</?(%a[%w]*)[%s/>]") or ""):lower()] then
            -- presentational markup only: keep the words, drop the element
        else
            output[#output + 1] = M.escape(tag)
        end
        start = last + 1
    end
    for i = #stack, 1, -1 do output[#output + 1] = "</" .. stack[i] .. ">" end
    -- MuPDF won't break a line-long word whose punctuation follows its closing
    -- tag ("<i>rūpanimittaniketavisāravinibandha</i>."), so the punctuation
    -- hangs past the edge; moving it inside lets the word break.
    return (table.concat(output):gsub("</(%a+)>([.,;:!?]+)", function(name, marks)
        if name == "i" or name == "em" or name == "b" or name == "strong" then return marks .. "</" .. name .. ">" end
    end))
end

local function link(uri, text, class)
    return '<a href="' .. M.escape(uri) .. '"' .. (class and (' class="' .. class .. '"') or "")
        .. '>' .. text .. '</a>'
end
-- A chevron control that expands or collapses content in place.
local function toggle(uri, open, text, control)
    return (control or link)(uri, (open and "▾  " or "▸  ") .. text, "toggle")
end

-- "kamma 1, 2, 5, 6": one word's homonym numbers after its first sense,
-- cut after eight senses (the part's link opens them all).
local function senseNames(senses)
    local out, word = {}, nil
    for i, sense in ipairs(senses) do
        if i > 8 then out[#out + 1] = "…"; break end
        local lemma = tostring(sense.lemma_1 or "")
        local base, number = lemma:match("^(.-) (%d[%d.]*)$")
        if base and base == word then out[#out + 1] = number else out[#out + 1] = lemma end
        word = base
    end
    return table.concat(out, ", ")
end

local function brief(sense)
    local meaning = sense.meaning_combo or ""
    return "<b>" .. M.escape(sense.lemma_1) .. "</b> · <i>" .. M.escape(sense.pos) .. "</i>"
        .. (meaning ~= "" and (" · " .. M.inline(meaning)) or "")
end

-- DPD uses a lone "-" as an empty placeholder (e.g. commentary, source_1).
local function present(value)
    return value ~= nil and tostring(value):match("^%s*%-?%s*$") == nil
end

-- Matches DPD text literally inside a Lua pattern.
local function literal(text)
    return (tostring(text):gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"))
end

-- DPD's grammar without what the sense row and origin line already say: a
-- leading part of speech and "from <derived from>". "masc, normally pl dhammā"
-- keeps its note; "pp of na karoti" stays whole.
local function grammarNote(grammar, pos, derived_from)
    local kept = {}
    for item in (tostring(grammar or "") .. ","):gmatch("%s*([^,]*),") do
        item = item:match("^(.-)%s*$")
        if item ~= "" and not (#kept == 0 and item == pos)
                and not (present(derived_from) and item == "from " .. derived_from) then
            kept[#kept + 1] = item
        end
    end
    return table.concat(kept, ", ")
end

--- Shows niggahīta as ṁ in displayed text only: tags and their attributes
--- (hrefs carry lookup keys) keep ṃ. Lookups fold ṁ back to ṃ.
function M.niggahita(text, mark)
    if mark ~= "ṁ" or not text then return text end
    local out, pos = {}, 1
    while true do
        local s, e = text:find("<[^>]*>", pos)
        out[#out + 1] = (text:sub(pos, (s or #text + 1) - 1):gsub("ṃ", "ṁ"):gsub("Ṃ", "Ṁ"))
        if not s then break end
        out[#out + 1] = text:sub(s, e)
        pos = e + 1
    end
    return table.concat(out)
end

-- The popup's title: a family list names itself and its size ("Idioms:
-- dhamma · 19") instead of repeating the word it was opened from.
function M.title(model)
    local family = model and model.family
    if family and family.title and family.title ~= "" then
        return family.title .. ((family.total or 0) > 0 and (" · " .. family.total) or "")
    end
    return model and model.query
end

-- Views opened from a result are not results themselves.
local function isResult(model)
    return not (model.paradigm or model.family or model.frequency or model.sutta or model.root_details
        or model.root_matrix or model.matrix_row or model.english or model.dictionaries)
end
M.isResult = isResult
M.senseNames = senseNames

local function moreParses(n)
    return "+" .. n .. (n == 1 and " parse" or " parses")
end

-- Combine parses by part of speech and headword before fitting them. Three-word
-- parses that share their first and last words join the middle one
-- ("masc dat sg", "masc gen sg" → "masc dat/gen sg"), and first words with the
-- same remainder share a segment ("masc, nt dat/gen sg"). Other parses ("2nd
-- acc sg" stays as it is, "present") keep their own segment. Each line opens
-- its headword through its first parse's index; every parse in it names that
-- headword, so the link goes to the same place.
function M.mergeParses(parses)
    local groups, order = {}, {}
    for i, parse in ipairs(parses or {}) do
        local key = tostring(parse.pos) .. "\0" .. tostring(parse.headword)
        local group = groups[key]
        if not group then
            group = { index = i, count = 0, pos = parse.pos, headword = parse.headword, segments = {}, by_ends = {} }
            groups[key], order[#order + 1] = group, key
        end
        group.count = group.count + 1
        local first, middle, last = tostring(parse.parse):match("^(%S+) (%S+) (%S+)$")
        if first then
            local ends = first .. " " .. last
            local segment = group.by_ends[ends]
            if not segment then
                segment = { first = first, last = last, middles = {} }
                group.by_ends[ends] = segment
                group.segments[#group.segments + 1] = segment
            end
            segment.middles[#segment.middles + 1] = middle
        else
            group.segments[#group.segments + 1] = { text = tostring(parse.parse) }
        end
    end
    local merged = {}
    for _, key in ipairs(order) do
        local group = groups[key]
        local parts, by_rest = {}, {}
        for _, segment in ipairs(group.segments) do
            if segment.text then
                parts[#parts + 1] = { text = segment.text }
            else
                local rest = table.concat(segment.middles, "/") .. " " .. segment.last
                local part = by_rest[rest]
                if part then part.firsts[#part.firsts + 1] = segment.first
                else
                    part = { firsts = { segment.first }, rest = rest }
                    by_rest[rest], parts[#parts + 1] = part, part
                end
            end
        end
        for i, part in ipairs(parts) do
            parts[i] = part.text or (table.concat(part.firsts, ", ") .. " " .. part.rest)
        end
        merged[#merged + 1] = { pos = group.pos, headword = group.headword, index = group.index, count = group.count,
            parse = table.concat(parts, "; ") }
    end
    return merged
end

function M.variantRange(total, page)
    page = math.max(1, math.min(page or 1, math.max(1, math.ceil(total / M.variant_page))))
    local first = (page - 1) * M.variant_page + 1
    return first, math.min(total, first + M.variant_page - 1), page
end

function M.render(model, state, scope, edit_search, layout, indent_em)
    layout = layout or { content_em = state.content_em or 30, target_em = 2.5, buttons = {} }
    indent_em = indent_em or 0
    -- HtmlBoxWidget wraps this fragment in its own document and stylesheet.
    local html = {}
    local function add(text) html[#html + 1] = text end
    if state.dictionaries_error then add('<p class="note">' .. M.escape(state.dictionaries_error) .. '</p>') end
    -- A heading at the top of a view or card needs no rule: the title bar or
    -- card border above already separates it.
    local function heading(text) return (#html == 0 and '<h3 class="lead">' or "<h3>") .. text .. "</h3>" end
    -- The title bar shows the query, so a view's heading leaves out a name
    -- that only repeats it.
    local function isTitle(text)
        return text ~= nil and Normalize.lower(tostring(text)) == Normalize.lower(tostring(model.query or ""))
    end
    -- A bordered card; the first in a view needs no rule under the title bar.
    local function card() return #html == 0 and '<div class="similar first">' or '<div class="similar">' end
    if type(scope) == "number" then scope = "similar/" .. scope end
    local function control(uri, text, class)
        if scope then uri = uri:gsub("^dpd:", "dpd:" .. scope .. "/") end
        return link(uri, text, class)
    end
    local function childScope(kind, index)
        return (scope and scope .. "/" or "") .. kind .. "/" .. index
    end
    local function labelWidth(text, factor)
        if layout.measure_text then return layout.measure_text(text, factor) / factor end
        local _, count = text:gsub("[\128-\191]", "")
        return (#text - count) * .6
    end
    -- MuPDF reports link text rectangles, not the surrounding cell. Record
    -- each cell's size so the viewer can make its outline fully tappable.
    -- Rows wrap before their measured labels stop fitting.
    local function buttons(items, owner_control, factor, extra_indent, compact)
        if #items == 0 then return end
        owner_control, factor = owner_control or control, factor or 1
        -- Definition actions use a 5.5mm floor; standalone pagers keep 7mm.
        -- Large fonts can still grow either row to fit the text comfortably.
        local target_em = layout.target_em * (compact and 5.5 / 7 or 1)
        local available = (layout.content_em - indent_em - (extra_indent or 0)) / factor
        local first = 1
        while first <= #items do
            local last = first
            local widths = { [first] = math.min(available - 2 * (layout.border_em or 0) / factor,
                labelWidth(items[first][2], factor) + 1.4) }
            local width = widths[first]
            while last < #items do
                local proposed = labelWidth(items[last + 1][2], factor) + 1.4
                if width + .5 + proposed > available then break end
                last, width = last + 1, width + .5 + proposed
                widths[last] = proposed
            end
            local padding = math.max(.15, (target_em / factor - 1.25) / 2)
            add(string.format('<table class="actions" style="width:%.3fem"><tr>', width))
            for i = first, last do
                local cell_width = widths[i]
                if i > first then add('<td style="width:.5em"></td>') end
                local anchor = owner_control(items[i][1], M.escape(items[i][2]))
                local uri = anchor:match('href="([^"]+)"')
                local border = 2 * (layout.border_em or 0)
                layout.buttons[uri] = { width_em = cell_width * factor + border,
                    height_em = math.max(target_em, (1.25 + 2 * padding) * factor) + border }
                add(string.format('<td class="action" style="width:%.3fem;padding:%.3fem .5em">',
                    cell_width - 1, padding) .. anchor .. '</td>')
            end
            add('</tr></table>')
            first = last + 1
        end
    end
    -- Labelled rows with the labels in their own column, sized to the longest
    -- label up to 7em, or its widest word, so a longer label wraps. When that
    -- leaves the values under 10em, or a field has a long word, use paragraphs:
    -- MuPDF wraps them without inserting separators that break word selection.
    local function fieldTable(rows, factor)
        if #rows == 0 then return end
        local width, widest_word, long_word = 0, 0, false
        for _, row in ipairs(rows) do
            width = math.max(width, labelWidth(row[1], factor))
            for word in row[1]:gmatch("%S+") do widest_word = math.max(widest_word, labelWidth(word, factor)) end
            for word in row[2]:gsub("<[^>]*>", ""):gmatch("%S+") do
                local _, length = word:gsub("[^\128-\191]", "")
                if length > 20 then long_word = true; break end
            end
        end
        width = math.min(width, math.max(7, widest_word)) + .6
        -- The detail sits about 1em in; its cells pad .6em after a label.
        if long_word or layout.content_em - indent_em - 1.6 - width < 10 then
            for _, row in ipairs(rows) do
                add('<p><i>' .. row[1] .. ':</i> ' .. row[2] .. '</p>')
            end
        else
            add(string.format('<table class="fields"><col style="width:%.3fem"><col>', width))
            for _, row in ipairs(rows) do
                add('<tr><td class="label">' .. row[1] .. '</td><td>' .. row[2] .. '</td></tr>')
            end
            add('</table>')
        end
    end
    local function fields(values, names)
        for _, field in ipairs(names) do
            local value = values[field[1]]
            if present(value) then
                add("<p><i>" .. field[2] .. ":</i> " .. M.inline(value) .. "</p>")
            end
        end
    end
    local function damaged()
        if #(model.damaged or {}) > 0 then
            add('<p class="note">Some DPD details could not be read. Affected data: '
                .. M.escape(table.concat(model.damaged, ", ")) .. '. Try a fresh DPD mobile database download.</p>')
        end
    end
    local function familyLinks(groups, path, owner_control)
        for i, group in ipairs(groups or {}) do
            local count = group.count and (" · " .. M.escape(group.count)) or ""
            add('<p>' .. (owner_control or control)("dpd:" .. path .. "/" .. i,
                M.escape(group.title or group.label or group.kind)) .. count .. '</p>')
        end
    end
    -- An expanded sense: grammar and origin, related words and variants,
    -- buttons for the views it opens, then commentary, examples and notes.
    -- The web link and completion metadata stay last.
    local function detail(values, sense_id, owner_control, pos)
        owner_control = owner_control or control
        local function value(name)
            if not present(values[name]) then return nil end
            local parts = (values.field_parts or {})[name]
            if not parts then return M.inline(values[name]) end
            local rendered = {}
            for _, part in ipairs(parts) do
                local text = M.inline(part.text)
                if part.target_index and (values.targets or {})[part.target_index] then
                    text = owner_control("dpd:detail-target/" .. sense_id .. "/" .. part.target_index, text)
                end
                rendered[#rendered + 1] = text
            end
            return table.concat(rendered)
        end
        local function labelled(label, text) return text and ("<i>" .. label .. ":</i> " .. text) or nil end
        -- Items share a line between dots. A short item keeps together, so
        -- "Root sign: a" never splits inside its label and "IPA: /dʰəmmə/" never
        -- after its slash; one that might not fit a line wraps as usual.
        local function line(class, ...)
            local kept = {}
            for i = 1, select("#", ...) do
                if select(i, ...) then kept[#kept + 1] = select(i, ...) end
            end
            if #kept == 0 then return end
            local factor = class == "meta" and .81 or .9
            local available = (layout.content_em - indent_em - 2.4) / factor
            for i, item in ipairs(kept) do
                local text = item:gsub("<[^>]*>", ""):gsub("&#?%w+;", "x")
                if #kept > 1 and labelWidth(text, factor) + 1 < available then
                    kept[i] = '<span class="item">' .. item .. "</span>"
                end
            end
            add("<p" .. (class and (' class="' .. class .. '"') or "") .. ">" .. table.concat(kept, " · ") .. "</p>")
        end
        add('<div class="detail">')
        -- Grammar and origin, one labelled row per field in a label column.
        local rows = {}
        local function field(label, text) if text then rows[#rows + 1] = { label, text } end end
        local grammar = grammarNote(values.grammar_line, pos, values.derived_from)
        field("Grammar", present(grammar) and M.inline(grammar) or nil)
        local from = value("derived_from") and ("<i>from</i> " .. value("derived_from"))
        if value("construction") then field("Construction", value("construction") .. (from and (" · " .. from) or ""))
        else field("From", value("derived_from")) end
        local root = value("root_key")
        if root and present(values.root_meaning) then root = root .. " (" .. M.inline(values.root_meaning) .. ")" end
        field("Root", root)
        field("Root sign", value("root_sign"))
        field("Root base", value("root_base"))
        field("Sanskrit", value("sanskrit"))
        field("Cognates", value("cognate"))
        field("Derivative", value("derivative"))
        -- A suffix that ends the construction ("√dhar + ma") is already shown there.
        if not tostring(values.construction or ""):find("%+%s*" .. literal(values.suffix or "") .. "%s*$") then
            field("Suffix", value("suffix"))
        end
        field("Phonetic change", value("phonetic"))
        field("IPA", value("ipa_line"))
        field("Traditional lemma (grammar-book headword)", value("traditional_line"))
        field("Non-Indo-Aryan origin", value("non_ia"))
        field("Compound type", value("compound_type"))
        if values.compound_construction ~= values.construction then
            field("Compound construction", value("compound_construction"))
        end
        fieldTable(rows, .9)
        line(nil, labelled("Synonym", value("synonym")), labelled("Antonym", value("antonym")),
            labelled("Variant", value("variant")), labelled("Phonetic variant", value("var_phonetic")),
            labelled("Textual variant", value("var_text")))
        local actions = {}
        if values.paradigm_kind then
            actions[#actions + 1] = { "dpd:detail-paradigm/" .. sense_id, values.paradigm_kind }
        end
        if values.has_frequency == 1 or values.has_frequency == true then
            actions[#actions + 1] = { "dpd:detail-frequency/" .. sense_id, "Frequency" }
        end
        if values.sutta_kind then
            -- A plain sutta needs no kind; "· sutta" would only repeat the label.
            actions[#actions + 1] = { "dpd:detail-sutta/" .. sense_id, "Sutta information"
                .. (values.sutta_kind ~= "sutta" and (" · " .. values.sutta_kind) or "") }
        end
        -- A family button names its family unless the entry already does: the
        -- root's own family, or the headword's only compound, idiom or word family.
        local lemma = tostring(values.lemma_1 or ""):gsub(" %d[%d.]*$", "")
        local root_name = tostring(values.root_key or ""):gsub(" %d+$", "")
        local kinds = {}
        for _, group in ipairs(values.families or {}) do kinds[group.kind] = (kinds[group.kind] or 0) + 1 end
        for i, group in ipairs(values.families or {}) do
            local title = tostring(group.title or group.label or group.kind)
            local name, key = title:match("^(.-):%s*(.+)$")
            if name and (group.kind == "root" and key == root_name
                    or group.kind ~= "set" and kinds[group.kind] == 1 and key == lemma) then
                title = name
            end
            actions[#actions + 1] = { "dpd:detail-family/" .. sense_id .. "/" .. i,
                title .. (group.count and (" · " .. group.count) or "") }
        end
        buttons(actions, owner_control, .9, 2.4, true)
        line(nil, labelled("Commentary", value("commentary")))
        -- An example carries its citation in its own paragraph; verse keeps its
        -- line breaks. A sutta name can put its vagga on a second line.
        for n = 1, 2 do
            if present(values["example_" .. n]) then
                local cite = {}
                for _, name in ipairs({ "source_" .. n, "sutta_" .. n }) do
                    if present(values[name]) then
                        cite[#cite + 1] = M.inline((tostring(values[name]):gsub("%s*\n%s*", " · ")))
                    end
                end
                add('<p class="example">' .. M.inline(values["example_" .. n]) .. (#cite > 0
                    and ('<br><span class="cite">&#8195;— ' .. table.concat(cite, " · ") .. "</span>") or "") .. "</p>")
            end
        end
        line(nil, labelled("Notes", value("notes")))
        line(nil, value("web_line") and (labelled("Web link", value("web_line")) .. " (requires internet)"))
        line("meta", value("status_line"), value("link_line"))
        add('</div>')
    end
    local function attestation(suggestion, frame, path, prefix)
        local matches = suggestion.attestations or {}
        if #matches == 0 then
            local label = suggestion.reason == "prefix" and "approximate · shortened prefix"
                or suggestion.reason == "digits" and "approximate · trailing digits removed"
                or suggestion.reason == "ti" and "ti split from the next word"
                or suggestion.reason == "niggahita" and (suggestion.printed == "n" and "ṃ printed as n before ti"
                    or "ṃ printed as " .. suggestion.printed .. " before a consonant") or "similar form"
            add('<p class="header">' .. (prefix or "") .. label .. '</p>'); return
        end
        local readings, seen = {}, {}
        for _, reading in ipairs(matches) do
            local key = reading.source .. "\0" .. reading.book .. "\0" .. reading.note
            if not seen[key] then readings[#readings + 1] = reading; seen[key] = true end
        end
        local first = readings[1]
        local label = "variant reading (" .. M.escape(first.source .. " " .. first.book) .. ")"
            .. (#readings > 1 and (" · +" .. (#readings - 1) .. " more") or "")
        add('<p class="header">' .. (prefix or "")
            .. toggle("dpd:" .. path .. "/attestations-toggle", frame.attestations_open, label) .. '</p>')
        if frame.attestations_open then
            add('<div class="provenance">')
            for _, reading in ipairs(readings) do
                add('<p>' .. M.escape(reading.source .. " " .. reading.book)
                    .. ': “' .. M.escape(reading.note) .. '”</p>')
            end
            add('</div>')
        end
    end
    -- Wide paradigms are split by gender or voice. `state.paradigm_columns`,
    -- set by the viewer from the popup width and font size, is how many of
    -- these sections fit side by side.
    local function paradigm(value)
        if not isTitle(value.lemma) then add(heading("<b>" .. M.escape(value.lemma) .. "</b>")) end
        if value.error then add('<p class="note">' .. M.escape(value.error) .. '</p>'); return end
        -- DPD marks irregular paradigms with the model word "irreg".
        local like = value.like == "irreg" and " · irregular"
            or present(value.like) and value.like ~= value.lemma:gsub(" [%d.]+$", "")
                and (" · like " .. M.escape(value.like)) or ""
        add('<p class="header">' .. M.escape(value.kind) .. " · pattern <i>" .. M.escape(value.pattern) .. "</i>"
            .. like .. '</p>')
        local per_row = math.max(1, math.floor(tonumber(state.paradigm_columns) or 1))
        -- MuPDF ignores overflow-wrap in table cells, so a form wider than its
        -- column (ID 8324 is 107 letters; at font 26 even apaṇṇakasuttānaṃ)
        -- gets zero-width spaces it can break at: between the stem's letters
        -- and before the ending; whole-word irregular forms break throughout.
        -- Lookups drop zero-width spaces, so holding the form still finds it.
        local function breakable(text)
            return (text:gsub("([%z\1-\127\194-\244][\128-\191]*)", "%1\226\128\139"))
        end
        local function cell(forms, column_em)
            local out = {}
            for _, form in ipairs(forms) do
                local text = M.escape(form.text)
                if labelWidth(tostring(form.text), 1) > column_em then
                    local ending = tostring(form.ending or "")
                    local stem = form.text:sub(1, #form.text - #ending)
                    if stem == "" or ending == "" or stem .. ending ~= form.text then stem, ending = form.text, "" end
                    text = M.escape(breakable(stem) .. ending)
                end
                if form.selected then text = '<span class="selected">▸ ' .. text .. '</span>' end
                out[#out + 1] = '<p class="form">' .. control("dpd:paradigm-form/" .. form.index, text) .. '</p>'
            end
            return table.concat(out)
        end
        -- Case label and form column widths (percent, and a form column's text
        -- width in em: its share of the popup less cell padding).
        local function widths(count)
            local case_width = math.max(10, math.floor(24 / count + 8))
            local percent = math.floor((100 - case_width) / count)
            return case_width, percent, layout.content_em * percent / 100 - .6
        end
        -- At large fonts three columns (eka's masc, fem and neut sg) may not
        -- hold ordinary forms, so such a section stacks as fewer, wider columns
        -- rather than breaking every form; two columns still break long ones.
        local sections = {}
        for _, section in ipairs(value.sections or {}) do
            local widest = 0
            for _, line in ipairs(section.rows) do
                for _, item in ipairs(line.cells) do
                    for _, form in ipairs(item.forms) do widest = math.max(widest, labelWidth(tostring(form.text), 1)) end
                end
            end
            local fit = #section.columns
            while fit > 2 and widest + .3 > select(3, widths(fit)) do fit = fit - 1 end
            for first = 1, #section.columns, fit do
                local last = math.min(#section.columns, first + fit - 1)
                local part = { title = first == 1 and section.title or nil, columns = {}, rows = {} }
                for index = first, last do part.columns[#part.columns + 1] = section.columns[index] end
                for _, line in ipairs(section.rows) do
                    local cells, filled = {}, false
                    for index = first, last do
                        cells[#cells + 1] = line.cells[index]
                        filled = filled or #line.cells[index].forms > 0
                    end
                    if filled then part.rows[#part.rows + 1] = { label = line.label, cells = cells } end
                end
                sections[#sections + 1] = part
            end
        end
        for first = 1, #sections, per_row do
            local group = {}
            for i = first, math.min(#sections, first + per_row - 1) do group[#group + 1] = sections[i] end
            local side_by_side = #group > 1
            if not side_by_side and group[1].title then
                add('<p class="section">' .. M.escape(group[1].title) .. '</p>')
            end
            -- Fixed, equal form columns keep stacked sections aligned.
            local count = 0
            for _, section in ipairs(group) do count = count + #section.columns end
            local case_width, percent, column_em = widths(count)
            local width = string.format(' style="width: %d%%"', percent)
            local row = { string.format('<tr><th style="width: %d%%"></th>', case_width) }
            for _, section in ipairs(group) do
                for _, column in ipairs(section.columns) do
                    local label = side_by_side and section.title and (section.title .. " " .. column) or column
                    row[#row + 1] = "<th" .. width .. ">" .. M.escape(label) .. "</th>"
                end
            end
            add('<table class="paradigm">' .. table.concat(row) .. "</tr>")
            -- Sections share the template's row order, but each omits rows with
            -- no forms; line them up by label when they sit side by side.
            local labels, seen = {}, {}
            for _, section in ipairs(group) do
                for _, line in ipairs(section.rows) do
                    if not seen[line.label] then seen[line.label] = true; labels[#labels + 1] = line.label end
                end
            end
            for _, label in ipairs(labels) do
                row = { '<tr><td class="case">' .. M.escape(label) .. "</td>" }
                for _, section in ipairs(group) do
                    local line
                    for _, candidate in ipairs(section.rows) do
                        if candidate.label == label then line = candidate; break end
                    end
                    for index = 1, #section.columns do
                        row[#row + 1] = "<td>" .. (line and cell(line.cells[index].forms, column_em) or "") .. "</td>"
                    end
                end
                add(table.concat(row) .. "</tr>")
            end
            add("</table>")
        end
        add('<p class="note">' .. (value.selected and ("“" .. M.escape(value.selected) .. "” is highlighted. ") or "")
            .. "Tap a form to look it up. This database does not show which individual forms occur in the texts.</p>")
    end
    -- Editions are packed into as few tables as fit the popup width
    -- (`state.content_em`, set by the viewer); spans stay within sections.
    local function frequency(value)
        local Frequency = require("dpd/frequency")
        if not isTitle(value.lemma or model.query) then
            add(heading("<b>" .. M.escape(value.lemma or model.query) .. "</b>"))
        end
        if value.error then add('<p class="note">' .. M.escape(value.error) .. '</p>'); return end
        add('<p class="header">' .. M.inline(value.heading or "") .. '</p>')
        if value.only_compounds then
            add("<p>No separate-form counts are available. Forms may occur inside compounds or sandhi.</p>")
            return
        end
        local available = tonumber(state.content_em) or 30
        local groups, current, width = {}, {}, 7.5
        for _, corpus in ipairs(Frequency.corpora) do
            local needed = 3 * #corpus.columns
            if #current > 0 and width + needed > available then
                groups[#groups + 1] = current; current, width = {}, 7.5
            end
            current[#current + 1] = corpus; width = width + needed
        end
        groups[#groups + 1] = current
        for _, group in ipairs(groups) do
            local columns, top, parts = {}, { "<tr><th></th>" }, { "<tr><th></th>" }
            for _, corpus in ipairs(group) do
                top[#top + 1] = '<th class="corpus" colspan="' .. #corpus.columns .. '">' .. corpus.label .. "</th>"
                for _, column in ipairs(corpus.columns) do
                    columns[#columns + 1] = column
                    parts[#parts + 1] = '<th class="part">' .. Frequency.column_labels[column] .. "</th>"
                end
            end
            add('<table class="freq">' .. table.concat(top) .. "</tr>" .. table.concat(parts) .. "</tr>")
            for _, section in ipairs(value.sections) do
                add('<tr><th class="section" colspan="' .. (#columns + 1) .. '">' .. M.escape(section.label) .. "</th></tr>")
                local covered = {}
                for _, line in ipairs(section.rows) do
                    local cells = { "<tr><th>" .. M.escape(line.label) .. "</th>" }
                    for _, column in ipairs(columns) do
                        local cell = line.cells[column]
                        if cell then
                            local level = Frequency.emphasis(cell.grade)
                            local text = tostring(cell.value)
                            if level >= 1 then text = "<b>" .. text .. "</b>" end
                            cells[#cells + 1] = "<td" .. (level == 2 and ' class="high"' or "")
                                .. (cell.rowspan > 1 and (' rowspan="' .. cell.rowspan .. '"') or "") .. ">" .. text .. "</td>"
                            covered[column] = cell.rowspan - 1
                        elseif (covered[column] or 0) > 0 then
                            covered[column] = covered[column] - 1
                        else
                            cells[#cells + 1] = "<td></td>"
                        end
                    end
                    add(table.concat(cells) .. "</tr>")
                end
            end
            add("</table>")
        end
        -- The key follows the tables, which start on the first screen.
        local names = {}
        for _, corpus in ipairs(Frequency.corpora) do names[#names + 1] = "<b>" .. corpus.label .. "</b>: " .. corpus.name end
        add('<p class="note">' .. table.concat(names, " · ") .. ". M mūla, A aṭṭhakathā, Ṭ ṭīkā.</p>")
        add('<p class="note">Counts are exact matches of the headword and all its inflected forms, '
            .. "not of this sense alone: identical forms of other words are counted too, and forms inside "
            .. "compounds or sandhi are not. Bold and grey mark the highest counts.</p>")
    end
    local function dictionaries(value)
        local keys = {}
        for _, key in ipairs(value.keys or {}) do keys[#keys + 1] = M.escape(key) end
        -- Name the searched forms only when they differ from the title.
        local searched = (#keys == 1 and isTitle(value.keys[1]) or #keys == 0) and ""
            or (" · " .. table.concat(keys, ", "))
        add('<p class="header">Other dictionaries' .. searched .. '</p>')
        if (value.omitted or 0) > 0 then
            -- Their senses' Sanskrit equivalents are still searched.
            add('<p class="note">' .. value.omitted .. (value.omitted == 1 and " more Pāḷi form" or " more Pāḷi forms")
                .. " of this result not searched by spelling.</p>")
        end
        if value.none_selected then
            -- Another spelling cannot help when nothing is searched.
            add("<p>No other dictionaries are selected.</p>")
            add('<p class="note">Choose at least one under DPD menu → Other dictionaries.</p>')
        elseif #(value.groups or {}) == 0 then
            add("<p>No entries in the selected dictionaries.</p>")
            add('<p class="note">Try another spelling. You can choose dictionaries under DPD menu → Other dictionaries.</p>')
        end
        if #(value.groups or {}) == 0 and model.dictionary_search and edit_search then
            add('<p class="footer">' .. link("dpd:edit-search", "Edit search") .. '</p>')
        end
        local pages = state.dictionary_pages or {}
        -- Previous part above the article, where a reader goes back from;
        -- both below it, where one continues.
        local function pager(page, key, below)
            local actions = {}
            if page.part > 1 then
                actions[#actions + 1] = { "dpd:dict-prev/" .. key, "Previous part" }
            end
            if below and page.has_more then
                actions[#actions + 1] = { "dpd:dict-next/" .. key, "Next part" }
            end
            buttons(actions)
        end
        for g, group in ipairs(value.groups or {}) do
            local shown, total = #group.entries, group.total or #group.entries
            local approximate = group.entries[1] and group.entries[1].approximate
            -- Non-breaking spaces keep a number with its word when the line wraps.
            local count = approximate and (shown .. "&nbsp;approximate · limited&nbsp;search")
                or (total .. (total == 1 and "&nbsp;entry" or "&nbsp;entries")
                    .. (shown < total and (" · " .. shown .. "&nbsp;shown") or "")
                    -- Found by the headwords' Sanskrit equivalent, not their spelling.
                    .. (group.via and #group.via > 0
                        and (" · via Sanskrit&nbsp;" .. M.escape(table.concat(group.via, ", "))) or ""))
            -- One line per dictionary: a compact name and the count. It wraps
            -- at large fonts rather than shrinking.
            add('<p class="section">' .. M.escape(group.heading or group.name or group.id)
                .. ' <span class="count">·&nbsp;' .. count .. '</span></p>')
            for e, entry in ipairs(group.entries) do
                local key = g .. "/" .. e
                local page = pages[key]
                local open = page and page.open
                local label = (entry.approximate and "≈ " or "") .. "<b>" .. M.escape(entry.word) .. "</b>"
                    .. (entry.homonym and ("<sup>" .. M.escape(entry.homonym) .. "</sup>") or "")
                    .. (open and "" or (present(entry.preview) and (" · " .. M.escape(entry.preview)) or ""))
                add('<div class="entry"><p class="row">' .. toggle("dpd:dict-entry/" .. key, open, label, control) .. '</p>')
                if open then
                    -- One part of the article at a time.
                    -- A whole article in one part needs no part label.
                    if page.part > 1 or page.has_more then
                        local last = not page.has_more and " · last part" or ""
                        add('<p class="header">Part ' .. page.part .. last .. '</p>')
                    end
                    pager(page, key)
                    add('<div class="article">' .. page.html .. '</div>')
                    pager(page, key, true)
                end
                add('</div>')
            end
            if #group.entries < (group.total or 0) then
                add('<p class="footer">' .. control("dpd:dict-entries/" .. g, "More entries") .. '</p>')
            end
        end
    end
    local function variants()
        if #(model.variants or {}) == 0 then return end
        local form = model.variant_rescue and (" · " .. M.escape(model.query)) or ""
        add(heading(toggle("dpd:variants-toggle", state.variants_open,
            "Variant readings" .. form .. " · " .. #model.variants, control)))
        if state.variants_open then
            -- Common particles carry over a thousand readings (ca: 1,679).
            -- Replace each 50-reading window instead of accumulating HTML.
            local first, last = M.variantRange(#model.variants, state.variants_page)
            local function pager()
                local actions = {}
                if first > 1 then actions[#actions + 1] = { "dpd:variants-prev", "Previous readings" } end
                if last < #model.variants then actions[#actions + 1] = { "dpd:variants-next", "Next readings" } end
                buttons(actions)
            end
            if #model.variants > M.variant_page then
                add('<p class="header">Readings ' .. first .. "–" .. last .. "&nbsp;of&nbsp;" .. #model.variants .. '</p>')
            end
            pager()
            for i = first, last do
                local variant = model.variants[i]
                local note = (variant.note or "") ~= "" and ("<br>" .. M.inline(variant.note)) or ""
                add("<p><b>" .. M.escape(variant.source) .. " · " .. M.escape(variant.book) .. ":</b> "
                    .. M.inline(variant.context) .. note .. "</p>")
            end
            pager()
        end
    end
    local function references()
        for index, reference in ipairs(model.references or {}) do
            local target = M.escape(reference.target)
            local child = (state.references or {})[index]
            local label = reference.kind == "spelling" and "Incorrect spelling of " or "See "
            if reference.model then target = control("dpd:reference/" .. index, "<b>" .. target .. "</b>") end
            add(card() .. '<p class="row">'
                .. (child and toggle("dpd:reference-toggle/" .. index, child.open, "", control) or "")
                .. label .. target .. '</p>')
            if child and child.open then
                add('<div class="similar-body">' .. M.render(child.model, child,
                    childScope("reference", index), nil, layout, indent_em + .8) .. '</div>')
            elseif not child and reference.status and reference.status ~= "missing" then
                local statuses = { cycle="Circular DPD reference", depth_limit="DPD reference chain is too deep",
                    limit="Additional DPD references omitted" }
                add('<p class="note">' .. M.escape(statuses[reference.status] or reference.status) .. '</p>')
            end
            add('</div>')
        end
    end
    -- Words one edit away, after a typed lookup found no exact or similar form.
    local spelling_only = #(model.spelling_suggestions or {}) > 0 and #model.senses == 0
        and #(model.suggestions or {}) == 0 and #model.deconstructions == 0 and #model.roots == 0
        and #(model.grammar or {}) == 0 and #(model.references or {}) == 0
    local function miss()
        if model.english and model.english.error then
            add("<p>" .. M.escape(model.english.error) .. "</p>")
        elseif model.id_query then
            add("<p>No DPD headword with ID " .. M.escape(model.query) .. ".</p>")
        else
            -- Variant readings are shown below, so the word isn't entirely absent.
            add("<p>No " .. (model.english and "English→Pāḷi entries"
                or #(model.variants or {}) > 0 and "DPD definition" or "DPD entry")
                .. " for “" .. M.escape(model.query) .. "”.</p>")
        end
        -- A long word DPD lacks: the longest beginning and ending it has.
        local parts = model.long_miss and model.parts or {}
        if parts.begins or parts.ends then
            add('<p class="header">Parts DPD has</p>')
            if parts.begins then
                add('<p>Begins with ' .. control("dpd:part/begins", "<b>" .. M.escape(parts.begins.form) .. "</b>") .. '…</p>')
            end
            if parts.ends then
                add('<p>Ends with …' .. control("dpd:part/ends", "<b>" .. M.escape(parts.ends.form) .. "</b>") .. '</p>')
            end
            add('<p class="note">Letters can change where parts join, so a part may be missing.</p>')
        end
        -- The title bar's edit button already edits a long word; no footer.
        if edit_search and not model.long_miss then
            add('<p class="note">' .. (model.english and "Try another English word, or switch to Pāḷi."
                or model.id_query and "Check the number, or search for a Pāḷi word."
                or "Check the spelling, or try English mode.") .. '</p>')
            add('<p class="footer">' .. link("dpd:edit-search", "Edit search") .. '</p>')
        end
    end
    if #(model.spelling_suggestions or {}) > 0 then
        if spelling_only then miss() end
        add('<p class="header">Did you mean:</p>')
        for index, item in ipairs(model.spelling_suggestions) do
            add('<p>' .. control("dpd:spelling/" .. index, "≈ " .. M.escape(item.text)) .. '</p>')
        end
    end
    if model.single_suggestion then
        references()
        local suggestion, candidate = model.suggestions[1], state.suggestions[1]
        local route = M.escape(model.original or model.query) .. ' → '
            .. (suggestion.particle and (M.escape(suggestion.particle) .. ' + ') or '') .. M.escape(suggestion.query)
        if #(suggestion.attestations or {}) > 0 then
            -- Keep the source toggle at the start of its own line.
            add('<p class="header" style="margin-bottom: .1em;">' .. route .. '</p>')
            attestation(suggestion, candidate, childScope("similar", 1))
        else
            attestation(suggestion, candidate, childScope("similar", 1), route .. ' · ')
        end
        add(M.render(candidate.model, candidate, childScope("similar", 1), nil, layout, indent_em))
        -- Readings belonging to the selected form remain available independently
        -- of the candidate's own readings and nested controls.
        variants()
        damaged()
        return table.concat(html, "\n")
    end
    -- Views opened from an entry keep their own title in `original`.
    if isResult(model) and model.original and model.original ~= model.query
        and Normalize.isRewrite(model.original, model.query) then
        add('<p class="header">Selected: “' .. M.escape(model.original) .. '” · DPD form: “'
            .. M.escape(model.query) .. '”</p>')
    end
    local parses = M.mergeParses(model.grammar)
    if #parses > 0 then
        local labels, widths, total = {}, {}, 0
        local available = (layout.content_em - indent_em) / .85
        local separator, toggle_gap = "  |  ", "    "
        local gap = not state.grammar_open and labelWidth(separator, .85) or 0
        for i, parse in ipairs(parses) do
            labels[i] = '<i>' .. M.escape(parse.pos) .. '</i> · '
                .. M.escape(parse.parse .. " of ") .. control("dpd:grammar-sense/" .. parse.index, M.escape(parse.headword))
            if not state.grammar_open then
                -- Leave room for italic glyphs and native font rounding.
                widths[i] = labelWidth(parse.pos .. " · " .. parse.parse .. " of " .. parse.headword, .85) + .3
                total = total + widths[i] + (i > 1 and gap or 0)
            end
        end
        if state.grammar_open then
            for _, label in ipairs(labels) do add('<p class="grammar">' .. label .. '</p>') end
            add('<p class="grammar grammar-more">'
                .. toggle("dpd:grammar-toggle", true, "Show fewer parses", control) .. '</p>')
        else
            local shown, used, hidden = #parses, 0, 0
            if total > available then
                shown, hidden = 0, #model.grammar
                for i = 1, #parses - 1 do
                    local width = used + widths[i] + (i > 1 and gap or 0)
                    local remaining = hidden - parses[i].count
                    if width + gap + labelWidth("▸  " .. moreParses(remaining), .85) > available then break end
                    shown, used, hidden = i, width, remaining
                end
                if shown == 0 then shown, hidden = 1, #model.grammar - parses[1].count end
            end
            local row = {}
            for i = 1, shown do
                row[i] = shown > 1 and ('<span class="grammar-parse">' .. labels[i] .. '</span>') or labels[i]
            end
            local text = table.concat(row, separator)
            if shown < #parses then
                -- The toggle is not another parse, so a wide space sets it off
                -- instead of the bar; it is as wide as the separator it replaces.
                local more = toggle("dpd:grammar-toggle", false, moreParses(hidden), control)
                if used > 0 then text = text .. toggle_gap .. more
                else
                    add('<p class="grammar">' .. text .. '</p>')
                    text = more
                end
            end
            add((shown < #parses and '<p class="grammar grammar-more">' or '<p class="grammar">') .. text .. '</p>')
        end
    end
    -- A dictionary search says what it missed in its own empty state.
    -- A long word known only from variant readings still shows its parts.
    if (not model.found or model.long_miss) and not spelling_only and not model.dictionary_search then miss() end
    if #(model.suggestions or {}) > 0 then
        add('<p class="header">' .. (model.variant_rescue and "No exact DPD definition" or "No exact DPD match")
            .. ' for “' .. M.escape(model.query) .. '”. '
            .. (model.matched_via == "prefix" and ('Approximate matches for shortened prefix “'
                .. M.escape(model.shortened_prefix) .. '”:') or 'Similar forms:') .. '</p>')
        for index, suggestion in ipairs(model.suggestions) do
            local candidate = state.suggestions[index]
            local value, kinds = suggestion.model, {}
            if #(value.senses or {}) > 0 then kinds[#kinds + 1] = "headwords" end
            if #(value.deconstructions or {}) > 0 then kinds[#kinds + 1] = "compound analyses" end
            if value.abbrev or #(value.abbrev_other or {}) > 0 then kinds[#kinds + 1] = "abbreviation" end
            if #(value.roots or {}) > 0 then kinds[#kinds + 1] = "roots" end
            if #(value.references or {}) > 0 then kinds[#kinds + 1] = "DPD references" end
            if #(value.variants or {}) > 0 then kinds[#kinds + 1] = "variant readings" end
            if #(value.grammar or {}) > 0 then kinds[#kinds + 1] = "grammar" end
            if value.help and value.help ~= "" then kinds[#kinds + 1] = "help" end
            if #kinds == 0 then kinds[#kinds + 1] = "DPD result" end
            add(card() .. '<p class="row">'
                .. toggle("dpd:similar/" .. index, candidate.open, "", control)
                .. control("dpd:suggestion/" .. index,
                "<b>" .. M.escape(suggestion.query) .. "</b>")
                .. " · " .. table.concat(kinds, " + ") .. '</p>')
            if #(suggestion.attestations or {}) > 0 then
                attestation(suggestion, candidate, childScope("similar", index))
            end
            if candidate.open then
                add('<div class="similar-body">' .. M.render(candidate.model, candidate,
                    childScope("similar", index), nil, layout, indent_em + .8) .. '</div>')
            end
            add('</div>')
        end
        local total = model.suggestion_total or #model.suggestions
        if total > #model.suggestions then
            add('<p class="more">' .. #model.suggestions .. "&nbsp;of&nbsp;" .. total .. "&nbsp;similar forms · "
                .. control("dpd:more", "Show more") .. '</p>')
        end
        if model.prefix_limited then
            add('<p class="note">Only the first 20 lookup forms for this prefix were checked. '
                .. 'Look up a more specific word to narrow the results.</p>')
        end
    end
    references()
    if #(model.senses or {}) > 0 then
        if #(model.deconstructions or {}) > 0 then add(heading("Headwords")) end
        for _, sense in ipairs(model.senses) do
            local open = state.expanded[sense.id]
            add('<div class="entry"><p class="row">' .. toggle("dpd:sense/" .. sense.id, open, brief(sense), control) .. '</p>')
            if open then
                detail(state.details[sense.id] or {}, sense.id, nil, sense.pos)
            end
            add("</div>")
        end
    end
    if type(model.abbrev) == "table" then
        add(heading("Abbreviation · " .. M.escape(model.query)))
        fields(model.abbrev, {{"meaning","Meaning"},{"pāli","Pāḷi"},{"example","Example"},{"explanation","Explanation"}})
    end
    for _, abbreviation in ipairs(model.abbrev_extra or {}) do
        add(heading("Abbreviation · " .. M.escape(abbreviation.form)))
        fields(abbreviation.value, {{"meaning","Meaning"},{"pāli","Pāḷi"},{"example","Example"},{"explanation","Explanation"}})
    end
    for _, abbreviation in ipairs(model.abbrev_other or {}) do
        add("<p><b>" .. M.escape(abbreviation.source) .. ":</b> " .. M.inline(abbreviation.meaning)
            .. (abbreviation.notes and abbreviation.notes ~= "" and (" · " .. M.inline(abbreviation.notes)) or "") .. "</p>")
    end
    -- Labelled, so help about using DPD (Pāḷi) is not read as a definition.
    if model.help and model.help ~= "" then add("<p><b>DPD help:</b> " .. M.inline(model.help) .. "</p>") end
    -- Root matches are independent of the headwords above; without a heading
    -- they read as those headwords' etymology. Root-only results need none.
    if #(model.roots or {}) > 0 and (#(model.senses or {}) > 0 or #(model.deconstructions or {}) > 0) then
        add(heading("Other root matches"))
    end
    for index, root in ipairs(model.roots or {}) do
        add('<div class="entry">' .. heading(M.escape(root.root) .. " · " .. M.inline(root.root_meaning)))
        fields(root, {{"root_group","Group"},{"root_sign","Sign"},{"root_example","Example"},
            {"sanskrit_root","Sanskrit root"},{"sanskrit_root_meaning","Sanskrit meaning"},{"note","Notes"}})
        add('<p>' .. control("dpd:root-details/" .. index, "Root details") .. " · "
            .. control("dpd:root-matrix/" .. index, "Root matrix") .. '</p>')
        familyLinks(root.families, "root-family/" .. index)
        add('</div>')
    end
    if model.root_details then
        local details = model.root_details
        if not isTitle(details.root) then add(heading(M.escape(details.root))) end
        if details.error then add('<p class="note">' .. M.escape(details.error) .. '</p>') end
        for _, row in ipairs(details.rows or {}) do
            local parts = {}
            for _, part in ipairs(row.parts) do
                local text = M.inline(part.text)
                if part.italic then text = "<i>" .. text .. "</i>" elseif part.sup then text = "<sup>" .. text .. "</sup>" end
                parts[#parts + 1] = text
            end
            add("<p><i>" .. M.escape(row.label) .. ":</i> " .. table.concat(parts) .. "</p>")
        end
    end
    if model.dictionaries then dictionaries(model.dictionaries) end
    if model.english then
        local english = model.english
        -- A miss has already said there are no entries.
        if model.found then
            local count = (english.total or 0) .. ((english.total or 0) == 1 and "&nbsp;entry" or "&nbsp;entries")
            if isTitle(english.query or model.query) then
                add('<p class="header">English → Pāḷi · ' .. count .. '</p>')
            else
                add(heading("English · " .. M.escape(english.query or model.query) .. " · " .. count))
            end
        end
        if english.error and model.found then add('<p class="note">' .. M.escape(english.error) .. '</p>') end
        for index, item in ipairs(english.items or {}) do
            add('<p>' .. control("dpd:english-item/" .. index, "<b>" .. M.escape(item.lemma) .. "</b>")
                .. (present(item.pos) and (" · <i>" .. M.escape(item.pos) .. "</i>") or "")
                .. (present(item.meaning) and (" · " .. M.inline(item.meaning)) or "") .. '</p>')
        end
        local shown = #(english.items or {})
        if english.total and english.total > 0 then
            add('<p class="more">' .. shown .. "&nbsp;of&nbsp;" .. english.total .. "&nbsp;entries"
                .. (english.has_more and (" · " .. control("dpd:english-more", "Show more")) or "") .. '</p>')
        end
    end
    if model.root_matrix then
        local matrix = model.root_matrix
        local words = matrix.total .. (matrix.total == 1 and "&nbsp;word" or "&nbsp;words")
        if isTitle(matrix.root) then add('<p class="header">' .. words .. '</p>')
        else add(heading(M.escape(matrix.root) .. " · " .. words)) end
        if #matrix.groups == 0 then add('<p>No entries in this matrix.</p>') end
        for g, group in ipairs(matrix.groups) do
            add('<p class="section">' .. M.escape(group.name) .. '</p>')
            for r, row in ipairs(group.rows) do
                add('<p>' .. control("dpd:matrix-row/" .. g .. "/" .. r, M.escape(row.label)) .. " · " .. #row.items .. '</p>')
            end
        end
    end
    if model.matrix_row then
        local row = model.matrix_row
        local Superscript = require("dpd/rootmatrix").superscript
        add(heading((isTitle(row.root) and "" or (M.escape(row.root) .. " · ")) .. M.escape(row.group)
            .. " · <b>" .. M.escape(row.label) .. "</b> · " .. #row.items))
        local items = {}
        for index, item in ipairs(row.items) do
            items[#items + 1] = control("dpd:matrix-item/" .. index, M.escape(Superscript(item.lemma)))
        end
        for _, item in ipairs(items) do add('<p>' .. item .. '</p>') end
    end
    if model.family then
        local family = model.family
        -- The title bar names the list (M.title), so the body starts with it.
        if family.error then add('<p class="note">' .. M.escape(family.error) .. '</p>') end
        for index, item in ipairs(family.items or {}) do
            -- The whole row opens the member; only the word is underlined.
            local lemma = "<b>" .. M.escape(item.lemma) .. "</b>"
            local label = (item.available and ("<u>" .. lemma .. "</u>") or lemma)
                .. (present(item.pos) and (" · <i>" .. M.escape(item.pos) .. "</i>") or "")
                .. (present(item.meaning) and (" · " .. M.inline(item.meaning)) or "")
                .. (present(item.completion) and (" " .. M.escape(item.completion)) or "")
            if item.available then label = control("dpd:family-member/" .. index, label, "plain") end
            add('<p>' .. label .. '</p>')
        end
        local shown, total = #(family.items or {}), family.total or #(family.items or {})
        if shown > 0 or total > 0 then
            add('<p class="more">' .. shown .. "&nbsp;of&nbsp;" .. total .. "&nbsp;entries"
                .. (family.has_more and (" · " .. control("dpd:family-more", "Show more")) or "") .. '</p>')
        elseif not family.error then add('<p>No entries in this family.</p>') end
    end
    if model.paradigm then paradigm(model.paradigm) end
    if model.frequency then frequency(model.frequency) end
    if model.sutta then
        local value = model.sutta
        if not isTitle(value.lemma) then add(heading("<b>" .. M.escape(value.lemma) .. "</b>")) end
        if value.error then add('<p class="note">' .. M.escape(value.error) .. '</p>') end
        for _, record in ipairs(value.records or {}) do
            if #value.records > 1 then add(heading(M.escape(record.name) .. " · " .. M.escape(record.code))) end
            if #value.records == 1 and Normalize.lower(value.lemma) ~= Normalize.lower(record.name) then
                add('<p class="header">DPD record: ' .. M.escape(record.name) .. " · " .. M.escape(record.code) .. '</p>')
            end
            for _, section in ipairs(record.sections) do
                add('<p class="section">' .. M.escape(section.title) .. '</p>')
                for _, field in ipairs(section.fields) do
                    -- Source file paths cannot be opened from the popup.
                    if field.label ~= "File" and field.label ~= "Filename" then
                        local v = M.inline(field.value)
                        if field.italic then v = "<i>" .. v .. "</i>" end
                        add("<p><i>" .. M.escape(field.label) .. ":</i> " .. v .. "</p>")
                    end
                end
            end
        end
    end
    variants()
    if #(model.deconstructions or {}) > 0 then
        local count = #model.deconstructions
        add(heading(count .. (count == 1 and " possible split" or " possible splits")
            .. ' <span class="quiet">· not yet checked by DPD</span>'))
        for index, analysis in ipairs(model.deconstructions) do
            -- An analysis expands to what it adds or to where its respelled
            -- parts are explained; one DPD could not split keeps its raw text.
            local expands = analysis.has_new == true or analysis.same ~= nil
            local open = expands and state.analyses[index]
            local header = {}
            for i, part in ipairs(analysis.parts or {}) do
                local escaped = M.escape(part)
                -- Bold marks what an analysis adds to the one that starts open.
                if analysis.unique[i] and not analysis.starts_open then escaped = "<b>" .. escaped .. "</b>" end
                header[#header + 1] = control("dpd:component/" .. index .. "/" .. i, escaped)
            end
            local breakup = analysis.parts and table.concat(header, " + ") or M.escape(analysis.raw)
            -- The parts name the analysis, so the chevron toggles it alone. Its
            -- tap area is a button's, recorded like the button cells; the parts'
            -- own text still wins a tap on them.
            local chevron = ""
            if expands then
                chevron = toggle("dpd:analysis/" .. index, open, "", control)
                layout.buttons[chevron:match('href="([^"]+)"')] = { width_em = 2.4, height_em = layout.target_em }
            end
            add('<div class="entry"><p class="row' .. (expands and "" or " still") .. '">' .. chevron .. breakup .. '</p>')
            if open then
                add('<div class="components">')
                for i, part in ipairs(analysis.parts) do
                    if analysis.unique[i] then
                        local component = model.components[part]
                        local senses = component and component.senses or {}
                        local total = component and component.total or #senses
                        -- The linked name opens every sense; the count joins that link
                        -- only when senses are left out below.
                        local name = "<b>" .. M.escape(part) .. "</b>"
                        if total > 2 then name = name .. ' <span class="count">·&nbsp;' .. total .. "&nbsp;senses&nbsp;›</span>" end
                        local compact = (analysis.compact or {})[i]
                        -- Its rows repeat headwords or an earlier part: name which senses instead.
                        local only = compact and ' <span class="count">· only ' .. M.escape(senseNames(senses)) .. '</span>' or ""
                        -- Every part keeps its heading, even one that repeats its rows
                        -- (vissajjiya above vissajjiya 1 and 2): it alone marks where
                        -- the previous part's senses end.
                        add('<div class="component"><p>' .. control("dpd:component/" .. index .. "/" .. i, name) .. only .. '</p>')
                        for j = 1, compact and 0 or math.min(2, #senses) do
                            local sense = senses[j]
                            local expansions = ((state.component_expanded or {})[index] or {})[i] or {}
                            local open_sense = expansions[sense.id]
                            local label = brief(sense)
                            if sense.id then
                                label = toggle("dpd:component-sense/" .. index .. "/" .. i .. "/" .. sense.id,
                                    open_sense, label, control)
                            end
                            add('<p class="row">' .. label .. '</p>')
                            if open_sense then
                                local values = (((state.component_details or {})[index] or {})[i] or {})[sense.id] or {}
                                local function componentControl(uri, text)
                                    return control(uri:gsub("^dpd:", "dpd:component-detail/" .. index .. "/" .. i .. "/"), text)
                                end
                                detail(values, sense.id, componentControl, sense.pos)
                            end
                        end
                        if #senses == 0 then
                            local roots = component and component.roots or {}
                            if #roots == 0 and #(component and component.reference_targets or {}) == 0 then
                                -- m has only abbreviations, apari only analyses:
                                -- no definition, but not nothing.
                                add(component and component.has_row
                                    and '<p>No DPD definition; tap the word for what DPD has.</p>'
                                    or '<p>No DPD entry for this component.</p>')
                            end
                            for _, root in ipairs(roots) do add('<p><i>root</i> · ' .. M.inline(root.root_meaning) .. '</p>') end
                        end
                        for _, target in ipairs(component and component.reference_targets or {}) do
                            local label = type(target) == "table" and target.kind == "spelling" and "Incorrect spelling of " or "See "
                            add('<p>' .. label .. M.escape(type(target) == "table" and target.target or target) .. '</p>')
                        end
                        add('</div>')
                    elseif (analysis.same or {})[i] then
                        local earlier = analysis.same[i]
                        local where = earlier.headword
                            and ((#(model.senses or {}) > 1) and "the headwords above" or "the headword above")
                            or (M.escape(earlier.form) .. " above")
                        add('<div class="component"><p>' .. control("dpd:component/" .. index .. "/" .. i,
                            "<b>" .. M.escape(part) .. "</b>") .. ' <span class="count">· same as ' .. where .. '</span></p></div>')
                    end
                end
                add("</div>")
            end
            add("</div>")
        end
    end
    damaged()
    return table.concat(html, "\n")
end

return M
