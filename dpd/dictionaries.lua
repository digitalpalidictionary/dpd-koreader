-- The other dictionaries bundled in the mobile DB (dict_meta, dict_entries),
-- read only when a reader opens "Other dictionaries" on a result.
-- Entry lists load 20 at a time (DPPN has 47 Tissas).
--
-- Every query binds dict_id: the indexes are (dict_id, word) and
-- (dict_id, word_fuzzy); without it a lookup scans 606,003 rows. Keys are
-- DPD's clean headwords for the result, deduplicated, or the typed/selected
-- form when DPD has none. Per dictionary each key is tried as is, then
-- capitalized (DPPN and Nyanatiloka capitalize names: "Buddha"). Only when
-- a dictionary has no exact hit for any key are a few word_fuzzy matches
-- added, marked approximate; those dictionaries follow the exact ones.
--
-- The Sanskrit dictionaries rarely hold a Pāḷi spelling, so their near
-- spellings of dhamma are coincidences (ḍama, dāma). When the result's
-- headwords record a Sanskrit equivalent (dhamma: "dharma [dhṛ]"), MW and
-- Apte look that up before falling back to near spellings. Edgerton's BHS
-- keeps many Pāḷi-like hybrid forms ("thīna = Pali id."), so its near
-- spellings come first and the equivalent only fills an empty section. Such
-- a group is exact and names the Sanskrit words it was found by. Measured on
-- v0.4.20260926 with tools/check_sanskrit.lua.
--
-- Articles are read a page at a time: a byte range of definition_html cut
-- after a closing block tag or line break, then reduced to the popup's
-- markup. The popup holds and lays out one page of one article at a time,
-- so the largest article (CPD's bibliography, 433 KB) is never read or laid
-- out whole. The data has no links between entries; MW and Apte link only to
-- external page scans, which are kept as text.
local Normalize = require("dpd/normalize")
local Dictionaries = {}
Dictionaries.__index = Dictionaries
Dictionaries.order = { "dppn", "cpd", "pts", "nyanatiloka", "peu", "bhs", "mw", "apte", "wordnet" }
Dictionaries.names = {
    dppn = "Dictionary of Pāli Proper Names", cpd = "Critical Pali Dictionary", pts = "PTS Pāḷi-English Dictionary",
    nyanatiloka = "Buddhist Dictionary (Nyanatiloka)", peu = "Pali English Ultimate",
    bhs = "Buddhist Hybrid Sanskrit Dictionary", mw = "Monier-Williams Sanskrit-English",
    apte = "Apte Sanskrit-English", wordnet = "Open English WordNet",
}
-- Lookup headings name the author only where the title alone does not
-- identify the work; the full details are in the menu's hold help.
Dictionaries.headings = {
    dppn = "Malalasekera · Pāli Proper Names", cpd = "Critical Pali Dictionary", pts = "PTS Pāḷi-English Dictionary",
    nyanatiloka = "Nyanatiloka · Buddhist Dictionary", peu = "Pali English Ultimate",
    bhs = "Edgerton · Buddhist Hybrid Sanskrit", mw = "Monier-Williams · Sanskrit–English",
    apte = "Apte · Sanskrit–English", wordnet = "Open English WordNet",
}
-- Title and author as dict_meta gives them (v0.4.20260926; PTS from dpd-db's
-- exporter, a373228c), for when the database is not open.
Dictionaries.bibliography = {
    dppn = { "Dictionary of Pāli Proper Names", "G. P. Malalasekera, revised by Ānandajoti Bhikkhu" },
    cpd = { "Critical Pali Dictionary", "V. Trenckner et al." },
    pts = { "PTS Pāḷi-English Dictionary", "T. W. Rhys Davids & William Stede" },
    nyanatiloka = { "Buddhist Dictionary: Manual of Buddhist Terms and Doctrines",
        "Nyanatiloka Mahathera, ed. Nyanaponika Mahathera" },
    peu = { "Pali English Ultimate", "Pali Myanmar Abhidhan" },
    bhs = { "Edgerton's Buddhist Hybrid Sanskrit Dictionary 1953", "Franklin Edgerton" },
    mw = { "Monier-Williams Sanskrit-English Dictionary", "Monier Monier-Williams" },
    apte = { "Apte Practical Sanskrit-English Dictionary, 1890", "Vaman Shivram Apte" },
    wordnet = { "Open English WordNet", "Open English WordNet (CC BY 4.0)" },
}
-- KOReader bundles no Burmese font, so these characters draw as boxes.
Dictionaries.notes = {
    peu = "Some entries contain Burmese script, which needs a Myanmar font installed in KOReader.",
}
Dictionaries.defaults = { "dppn", "cpd", "pts", "nyanatiloka" }
Dictionaries.article_page = 16000 -- bytes of source HTML per page
Dictionaries.max_keys = 5
Dictionaries.max_entries = 20 -- entries read at a time, per dictionary
Dictionaries.max_approximate = 3
Dictionaries.max_sanskrit = 3 -- Sanskrit words tried per lookup
-- When the Sanskrit equivalent is tried: before near spellings, or only
-- when they find nothing.
Dictionaries.sanskrit = { mw = "before", apte = "before", bhs = "empty" }
-- Apte lists nouns in the nominative: dharmaḥ, phalaṃ.
Dictionaries.sanskrit_endings = { apte = { "", "ḥ", "ṃ" } }

function Dictionaries.new(db) return setmetatable({ db = db }, Dictionaries) end

--- Whether this database has any other dictionary (older releases have the
--- tables but leave them empty).
function Dictionaries:available()
    if self.ready == nil then
        local ok, rows = pcall(self.db.query, self.db, "SELECT 1 FROM dict_meta LIMIT 1")
        if not ok then
            if not tostring(rows):find("no such table: dict_meta", 1, true) then
                return nil, "DPD could not read the other dictionaries. Try a fresh DPD mobile database download."
            end
            self.ready = false
        else self.ready = #rows > 0 end
    end
    return self.ready
end

--- Dictionaries present in this database, in display order.
--- @return table { { id, name, author, count } }
function Dictionaries:list()
    local ready, err = self:available()
    if err then error(err) end
    if not ready then return {} end
    local by_id = {}
    for _, row in ipairs(self.db:query("SELECT dict_id, name, author, entry_count FROM dict_meta")) do
        by_id[row.dict_id] = { id = row.dict_id, name = row.name, author = row.author, count = tonumber(row.entry_count) }
    end
    local out = {}
    for _, id in ipairs(Dictionaries.order) do
        if by_id[id] then out[#out + 1] = by_id[id]; by_id[id] = nil end
    end
    for _, item in pairs(by_id) do out[#out + 1] = item end
    return out
end

local upper = { ["ā"] = "Ā", ["ī"] = "Ī", ["ū"] = "Ū", ["ṭ"] = "Ṭ", ["ḍ"] = "Ḍ", ["ṇ"] = "Ṇ",
    ["ñ"] = "Ñ", ["ṅ"] = "Ṅ", ["ḷ"] = "Ḷ", ["ṃ"] = "Ṃ" }
function Dictionaries.capitalized(word)
    local first = word:match("^[%z\1-\127\194-\244][\128-\191]*") or ""
    return (upper[first] or first:upper()) .. word:sub(#first + 1)
end

local sanskrit_letters = { "ā", "ī", "ū", "ṛ", "ṝ", "ḷ", "ḹ", "ṅ", "ñ", "ṭ", "ḍ", "ṇ", "ś", "ṣ", "ṃ", "ḥ" }

--- Plain Sanskrit words in DPD's sanskrit field, in order: the root in
--- brackets and notes in parentheses are dropped, and a field with an
--- analysis (+) or a doubt (?) gives none. "dharma [dhṛ]" gives dharma;
--- "atyaya + sūkta, sūtra (bsk)" gives nothing, rather than sūtra for every
--- sutta. Words need three letters: "a [praṇidhā]" gives nothing.
function Dictionaries.sanskritWords(field)
    local text = tostring(field or ""):gsub("%b[]", " "):gsub("%b()", " ")
    local words = {}
    if text:find("[+?]") then return words end
    for part in text:gmatch("[^,]+") do
        part = Normalize.lower(Normalize.nfc(Normalize.trim(part)))
        -- One ASCII letter per diacritic letter, to check and count letters.
        local ascii = part
        for _, letter in ipairs(sanskrit_letters) do ascii = ascii:gsub(letter, "a") end
        if ascii:match("^%l+$") and #ascii >= 3 then words[#words + 1] = part end
    end
    return words
end

-- Runs of Burmese script (Myanmar and its extensions) become one space.
local function withoutBurmese(text)
    return (text:gsub("\225[\128-\130][\128-\191]", function(c)
        return c < "\225\130\160" and "\1" or c
    end):gsub("\234\167[\160-\191]", "\1"):gsub("\234\169[\160-\191]", "\1"):gsub("\1[\1%s%p]*", " "))
end

local function startsWith(text, prefix) return prefix ~= "" and text:sub(1, #prefix) == prefix end

-- The article's opening headword (the row's word), with any homonym number
-- printed with it, as in CPD's "¹kamma" or MW's "1. kāya". The entry row
-- already shows the word in bold, so the preview starts after it.
local function afterHeadword(text, word)
    local digits, rest = text:match("^(%d+)%.?%s*(.*)$")
    local candidates = { text }
    if digits then candidates[2] = rest end
    for i, candidate in ipairs(candidates) do
        for _, form in ipairs({ word, Dictionaries.capitalized(word) }) do
            if startsWith(candidate, form) then
                local after = candidate:sub(#form + 1)
                if after == "" or after:match("^[%s,;:%(]") then
                    after = after:gsub("^[%s,;:]+", "")
                    if after ~= "" then return after, i == 2 and tostring(tonumber(digits)) or nil end
                end
            end
        end
    end
    return text
end

-- The next tag from `pos`: its start, end, "/" or "", name and attributes.
-- A ">" inside a quoted value does not end it (Apte's note="equ->equkaH").
-- A quote left open runs to the end of a `truncated` chunk; otherwise the
-- first ">" ends the tag, as before.
local function nextTag(html, pos, truncated)
    local s, after, slash, name = html:find("<(/?)([%a][%w]*)", pos)
    if not s then return nil end
    local i = after + 1
    while true do
        local c = html:find("[>\"']", i)
        if not c then
            if truncated then return s, #html, slash, name, html:sub(after + 1) end
            return nil
        end
        if html:byte(c) == 62 then return s, c, slash, name, html:sub(after + 1, c - 1) end
        -- Only a quote opening a value (name="…") is one.
        local j = c - 1
        while j > after and html:sub(j, j):match("%s") do j = j - 1 end
        local close = html:byte(j) == 61 and html:find(html:sub(c, c), c + 1, true)
        if close then
            i = close + 1
        elseif html:byte(j) == 61 then
            if truncated then return s, #html, slash, name, html:sub(after + 1) end
            local e = html:find(">", after + 1, true)
            if not e then return nil end
            return s, e, slash, name, html:sub(after + 1, e - 1)
        else
            i = c + 1
        end
    end
end

local named = { amp = "&", lt = "<", gt = ">", quot = '"', apos = "'", nbsp = " " }

local function utf8char(code)
    if code < 0x80 then return string.char(code) end
    if code < 0x800 then return string.char(0xC0 + math.floor(code / 0x40), 0x80 + code % 0x40) end
    if code < 0x10000 then
        return string.char(0xE0 + math.floor(code / 0x1000), 0x80 + math.floor(code / 0x40) % 0x40, 0x80 + code % 0x40)
    end
    return string.char(0xF0 + math.floor(code / 0x40000), 0x80 + math.floor(code / 0x1000) % 0x40,
        0x80 + math.floor(code / 0x40) % 0x40, 0x80 + code % 0x40)
end

-- Entities in plain text, decoded once: "&amp;lt;" is the text "&lt;".
-- Escaped punctuation is text (WordNet's "‘&lt;’", CPD's "&lt; *dvahihaka");
-- an unknown entity is dropped, as before.
local function decodeEntities(text)
    return (text:gsub("&(#?)(%w+);", function(hash, name)
        if hash == "" then return named[name] or "" end
        local code = name:match("^[xX](%x+)$") and tonumber(name:sub(2), 16) or name:match("^%d+$") and tonumber(name)
        if not code or code == 0 or code > 0x10FFFF or (code >= 0xD800 and code < 0xE000) then return "" end
        return utf8char(code)
    end))
end

-- Plain text from the start of an article, for telling entries apart, and
-- the homonym number the article gives its headword.
local function preview(html, dict_id, word)
    if dict_id == "cpd" then html = html:gsub("%-<br%s*/?>", "") end
    -- PTS gives a homonym only its number: "<p><sup>2</sup> (neuter) …".
    local numbered
    if dict_id == "pts" then
        numbered = html:match("^%s*<p>%s*<sup>(%d+)</sup>")
        if numbered then html = html:gsub("^%s*<p>%s*<sup>%d+</sup>", "<p>", 1) end
    end
    -- Declarations, comments and processing instructions are not tags.
    html = html:gsub("<%?.-%?>", ""):gsub("<!%-%-.-%-%->", ""):gsub("<![^>]*>", "")
        :gsub("<head>.-</head>", ""):gsub("<span class=\"record%-id\">.-</span>", "")
        :gsub("<span class=\"record%-id\">.*$", "")
        -- As the article does, show an amendment's current reading only; a
        -- chunk ending inside an old reading loses the rest.
        :gsub("<old>.-</old>", ""):gsub("<old>.*$", "")
    -- Line breaks and blocks separate words; inline tags do not. The chunk
    -- may end inside a tag.
    local parts, pos = {}, 1
    while true do
        local s, e, _, name = nextTag(html, pos, true)
        parts[#parts + 1] = html:sub(pos, (s or #html + 1) - 1)
        if not s then break end
        name = name:lower()
        if name == "br" or name == "p" or name == "li" then parts[#parts + 1] = " " end
        pos = e + 1
    end
    local text = decodeEntities(table.concat(parts):gsub("<[^>]*$", ""):gsub("&[#%w]*$", ""))
        :gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    -- MW and Apte open with a headword level and a link to the printed page.
    text = text:gsub("^%(H%d+%a?%)%s*", ""):gsub("^%[Printed book page [^%]]*%]%s*", "")
    text = withoutBurmese(text):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    local homonym
    if word then text, homonym = afterHeadword(text, word) end
    if numbered then homonym = tostring(tonumber(numbered)) end
    if #text > 110 then
        local cut = 110
        while cut > 0 and text:byte(cut + 1) and text:byte(cut + 1) >= 0x80 and text:byte(cut + 1) < 0xC0 do cut = cut - 1 end
        text = text:sub(1, cut) .. "…"
    end
    return text, homonym
end

local SELECT = "SELECT id, word, CAST(substr(CAST(definition_html AS BLOB), 1, 600) AS TEXT) AS head"
    .. " FROM dict_entries WHERE dict_id = ? AND "

-- The chunk without a last character the byte limit split (ā is C4 81).
local function wholeCharacters(chunk)
    local last = #chunk
    local lead = last
    while lead > 0 and lead > last - 3 and chunk:byte(lead) >= 0x80 and chunk:byte(lead) < 0xC0 do lead = lead - 1 end
    local byte = lead > 0 and chunk:byte(lead) or 0
    local size = byte >= 0xF0 and 4 or byte >= 0xE0 and 3 or byte >= 0xC0 and 2 or 1
    if last - lead + 1 < size then return chunk:sub(1, lead - 1) end
    return chunk
end

local function entry(row, dict_id, approximate, db)
    local raw = row.head or ""
    local head = wholeCharacters(raw)
    local text, homonym = preview(head, dict_id, row.word)
    -- An amendment's old reading or note can fill the chunk (Apte eḍukaḥ,
    -- uparatāti): read a longer one for just this entry.
    if text == "" and #raw >= 600 and db then
        local longer = db:query("SELECT CAST(substr(CAST(definition_html AS BLOB), 1, 4096) AS TEXT) AS head"
            .. " FROM dict_entries WHERE id = ?", { row.id })[1]
        if longer and longer.head then
            raw = longer.head
            head = wholeCharacters(raw)
            text, homonym = preview(head, dict_id, row.word)
        end
    end
    -- A word cut short there still reads as cut.
    if #head < #raw and text ~= "" and not text:find("…$") then text = text .. "…" end
    return { id = row.id, word = row.word, preview = text, homonym = homonym, approximate = approximate }
end

--- Entries for the keys in the enabled dictionaries: per dictionary the first
--- `max_entries` exact matches, in key order then by ID, with the total; the
--- rest are read by `more`. Only the first `max_keys` keys are searched.
--- `sanskrit` lists the result's Sanskrit equivalents (sanskritWords);
--- `typed`, keys tried only in a dictionary where `keys` found nothing.
--- @return table { { id, name, author, heading, total, words, via, entries = { { id, word, preview, homonym, approximate } } } }
function Dictionaries:lookup(keys, enabled, sanskrit, typed)
    local wanted = {}
    for _, id in ipairs(enabled or Dictionaries.defaults) do wanted[id] = true end
    local unique, seen = {}, {}
    for _, key in ipairs(keys) do
        key = tostring(key or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if key ~= "" and not seen[key] and #unique < Dictionaries.max_keys then seen[key] = true; unique[#unique + 1] = key end
    end
    local groups = {}
    for _, dictionary in ipairs(self:list()) do
        if wanted[dictionary.id] then
            local group = { id = dictionary.id, name = dictionary.name, author = dictionary.author,
                heading = Dictionaries.headings[dictionary.id],
                entries = {}, words = {}, total = 0, cursor = { word = 1, offset = 0 } }
            local used = {}
            local function count(word)
                return tonumber(self.db:query("SELECT count(*) AS n FROM dict_entries WHERE dict_id = ? AND word = ?",
                    { dictionary.id, word })[1].n) or 0
            end
            local function add(key)
                -- As is, else capitalized (DPPN and Nyanatiloka capitalize names).
                local word, n = key, count(key)
                if n == 0 then
                    local capital = Dictionaries.capitalized(key)
                    if capital ~= key then word, n = capital, count(capital) end
                end
                if n > 0 and not used[word] then
                    used[word] = true
                    group.words[#group.words + 1] = { word = word, count = n }
                    group.total = group.total + n
                    return true
                end
            end
            for _, key in ipairs(unique) do add(key) end
            -- The text as typed, when Velthuis input changed it and found nothing here.
            if group.total == 0 then
                for _, key in ipairs(typed or {}) do add(key) end
            end
            local function bySanskrit()
                local via = {}
                for i = 1, math.min(#(sanskrit or {}), Dictionaries.max_sanskrit) do
                    for _, ending in ipairs(Dictionaries.sanskrit_endings[dictionary.id] or { "" }) do
                        if add(sanskrit[i] .. ending) and via[#via] ~= sanskrit[i] then via[#via + 1] = sanskrit[i] end
                    end
                end
                if group.total > 0 then group.via = via end
            end
            local sanskrit_when = sanskrit and Dictionaries.sanskrit[dictionary.id]
            if group.total == 0 and sanskrit_when == "before" then bySanskrit() end
            if group.total == 0 then
                local ids = {}
                for _, key in ipairs(unique) do
                    local folded = Normalize.fuzzy(key)
                    if folded ~= "" then
                        for _, row in ipairs(self.db:query(SELECT .. "word_fuzzy = ? ORDER BY id LIMIT ?",
                            { dictionary.id, folded, Dictionaries.max_approximate })) do
                            if #group.entries < Dictionaries.max_approximate and not ids[row.id] then
                                ids[row.id] = true
                                group.entries[#group.entries + 1] = entry(row, dictionary.id, true, self.db)
                            end
                        end
                    end
                    if #group.entries >= Dictionaries.max_approximate then break end
                end
                group.total = #group.entries
            end
            if group.total == 0 and sanskrit_when == "empty" then bySanskrit() end
            if #group.words > 0 then self:more(group) end
            if #group.entries > 0 then groups[#groups + 1] = group end
        end
    end
    -- Exact entries first: an approximate-only dictionary early in the fixed
    -- order must not push exact entries further down (or onto a later page).
    local ordered = {}
    for _, approximate in ipairs({ false, true }) do
        for _, group in ipairs(groups) do
            if (group.entries[1].approximate == true) == approximate then ordered[#ordered + 1] = group end
        end
    end
    return ordered
end

--- Appends the group's next `max_entries` exact matches; returns how many.
function Dictionaries:more(group)
    local added, cursor = 0, group.cursor
    while cursor and added < Dictionaries.max_entries and group.words[cursor.word] do
        local word = group.words[cursor.word]
        local rows = self.db:query(SELECT .. "word = ? ORDER BY id LIMIT ? OFFSET ?",
            { group.id, word.word, Dictionaries.max_entries - added, cursor.offset })
        for _, row in ipairs(rows) do group.entries[#group.entries + 1] = entry(row, group.id, false, self.db) end
        added, cursor.offset = added + #rows, cursor.offset + #rows
        if #rows == 0 or cursor.offset >= word.count then cursor.word, cursor.offset = cursor.word + 1, 0 end
    end
    return added
end

-- Tags kept (attributes removed, but for cell spans) and renamed; others are dropped with their
-- content kept, except `drop` ones whose content goes too.
local keep = { p = "p", br = "br", b = "b", strong = "b", i = "i", em = "i", sup = "sup", sub = "sub",
    ul = "ul", ol = "ol", li = "li", blockquote = "blockquote", hr = "hr",
    h2 = "b", h3 = "b", h4 = "b", table = "table", tr = "tr", td = "td", th = "th" }
local void = { br = true, hr = true }
local drop = { script = true, style = true, head = true, title = true, old = true }

-- A cell's rowspan and colspan, which place the cells after it, when they
-- are small whole numbers (the data uses 2).
local function spans(tag, attributes)
    if tag ~= "td" and tag ~= "th" then return "" end
    local out = ""
    for _, name in ipairs({ "rowspan", "colspan" }) do
        local n = tonumber(attributes:lower():match(name .. "%s*=%s*[\"']?(%d+)"))
        if n and n >= 2 and n <= 50 then out = out .. " " .. name .. '="' .. n .. '"' end
    end
    return out
end

-- A span's class names, padded with spaces for whole-word matching.
local function classes(attributes)
    return " " .. (attributes:match("[Cc][Ll][Aa][Ss][Ss]%s*=%s*\"([^\"]*)\"")
        or attributes:match("[Cc][Ll][Aa][Ss][Ss]%s*=%s*'([^']*)'") or "") .. " "
end

--- Reduces dictionary HTML to the popup's markup, balanced: text and
--- b/i/sup/sub, paragraphs, lists, quotes and tables, whose cells keep
--- rowspan and colspan. Colours,
--- styles, classes, links and scripts go; MW/Apte Sanskrit spans become
--- italic and their record IDs are dropped. CPD's printed line breaks are
--- joined. Printed-page citations (MW/Apte pcol-ref, CPD page) stay as muted
--- `span class="src"` text without their scan links; as in DPD's app, MW/Apte
--- headword-level markers such as (H1) go.
function Dictionaries.sanitize(html, dict_id)
    html = tostring(html or "")
        :gsub("<%?.-%?>", ""):gsub("<!%-%-.-%-%->", ""):gsub("<![^>]*>", "")
    if dict_id == "cpd" then
        html = html:gsub("%-<br%s*/?>", ""):gsub("<br%s*/?>", " ")
    elseif dict_id == "mw" or dict_id == "apte" then
        html = html:gsub("<strong>%(H%d%u?%)</strong>%s*", ""):gsub("<strong>%(C%d%)</strong>%s*", "")
    end
    -- Apte separates senses with empty divs.
    html = html:gsub("<div class=\"div%-sep\">%s*</div>", "<br>")
    local out, stack, pos, skipping = {}, {}, 1, nil
    local function close(name)
        for i = #stack, 1, -1 do
            if stack[i].name == name then
                for j = #stack, i, -1 do
                    if stack[j].out then out[#out + 1] = "</" .. stack[j].out .. ">" end
                    stack[j] = nil
                end
                return true
            end
        end
    end
    while pos <= #html do
        local s, e, slash, name, attributes = nextTag(html, pos)
        local text = html:sub(pos, (s or #html + 1) - 1)
        if not skipping and text ~= "" then out[#out + 1] = (text:gsub("<", "&lt;")) end
        if not s then break end
        pos = e + 1
        name = name:lower()
        if skipping then
            if slash == "/" and name == skipping.name then
                skipping.depth = skipping.depth - 1
                if skipping.depth == 0 then skipping = nil end
            elseif slash == "" and name == skipping.name and not attributes:match("/%s*$") then
                skipping.depth = skipping.depth + 1
            end
        elseif drop[name] or (name == "span" and attributes:find("record%-id")) then
            if slash == "" and not attributes:match("/%s*$") then skipping = { name = name, depth = 1 } end
        elseif slash == "/" then
            close(name)
        else
            local mapped, opening = keep[name], nil
            if name == "span" and attributes:find("sdata") then mapped = "i" end
            if name == "span" and (classes(attributes):find(" pcol-ref ", 1, true)
                or classes(attributes):find(" page ", 1, true)) then
                mapped, opening = "span", 'span class="src"'
            end
            if mapped and void[mapped] then
                out[#out + 1] = "<" .. mapped .. ">"
            elseif not attributes:match("/%s*$") then
                -- A page may start inside a table: reopen what a row or cell needs.
                local function open(tag)
                    stack[#stack + 1] = { name = tag, out = tag }
                    out[#out + 1] = "<" .. tag .. ">"
                end
                local function within(tag)
                    for i = #stack, 1, -1 do if stack[i].name == tag then return true end end
                end
                if (mapped == "tr" or mapped == "td" or mapped == "th") and not within("table") then open("table") end
                if (mapped == "td" or mapped == "th") and not within("tr") then open("tr") end
                -- Bold or italic inside the same (h2 → b around b) adds nothing.
                if (mapped == "b" or mapped == "i") then
                    for i = #stack, 1, -1 do if stack[i].out == mapped then mapped = nil; break end end
                end
                -- Containers that are not kept still track nesting so their
                -- closing tag closes what they opened.
                stack[#stack + 1] = { name = name, out = mapped }
                if mapped then out[#out + 1] = "<" .. (opening or mapped) .. spans(mapped, attributes) .. ">" end
            end
        end
    end
    for i = #stack, 1, -1 do
        if stack[i].out then out[#out + 1] = "</" .. stack[i].out .. ">" end
    end
    return table.concat(out)
end

-- The end of the last closing block tag or line break in the first `limit`
-- bytes, else the last tag end or space; nil when the chunk has neither.
function Dictionaries.cut(chunk, limit)
    -- Never cut inside a comment: blank comments out (keeping positions),
    -- including one the window ends inside.
    local window = chunk:sub(1, limit)
        :gsub("<!%-%-.-%-%->", function(c) return string.rep(" ", #c) end)
        :gsub("<!%-%-.*$", function(c) return string.rep("\0", #c) end)
    local best
    for _, pattern in ipairs({ "</p>", "</li>", "</blockquote>", "</div>", "</ul>", "</ol>", "</tr>", "</table>", "<br%s*/?>" }) do
        local from = 1
        while true do
            local s, e = window:find(pattern, from)
            if not s then break end
            if not best or e > best then best = e end
            from = e + 1
        end
    end
    if best and best >= limit / 2 then return best end
    -- Otherwise cut outside a tag: after the last space following the last
    -- complete tag, or just before a tag the window ends inside.
    local lt, gt = window:match("^.*()<") or 0, window:match("^.*()>") or 0
    if lt > gt then
        if lt - 1 >= limit / 2 then return lt - 1 end
    else
        local space = window:match("^.*() ")
        if space and space > gt and space >= limit / 2 then return space end
        if gt >= limit / 2 then return gt end
    end
    return best
end

--- One page of an article: the HTML from byte `offset` (0-based) to the next
--- structural cut after about `article_page` bytes.
--- @return table { html, offset, next_offset, total, has_more } or nil
function Dictionaries:page(id, offset)
    offset = offset or 0
    local size = Dictionaries.article_page
    local row = self.db:query("SELECT dict_id, length(CAST(definition_html AS BLOB)) AS total,"
        .. " CAST(substr(CAST(definition_html AS BLOB), ?, ?) AS TEXT) AS chunk FROM dict_entries WHERE id = ?",
        { offset + 1, math.floor(size * 1.5), id })[1]
    if not row then return nil end
    local total, chunk = tonumber(row.total) or 0, row.chunk or ""
    local length = #chunk
    if offset + length < total then
        length = Dictionaries.cut(chunk, size) or Dictionaries.cut(chunk, #chunk)
            or #wholeCharacters(chunk)
    end
    return { html = Dictionaries.sanitize(chunk:sub(1, length), row.dict_id), offset = offset,
        next_offset = offset + length, total = total, has_more = offset + length < total }
end

return Dictionaries
