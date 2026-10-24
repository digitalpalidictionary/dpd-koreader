-- Check other-dictionary articles for a release: every article over 20 KB
-- and every 50th other entry, read page by page as the popup
-- does. Pages must advance and cover the article exactly; their HTML may
-- hold only the kept tags, balanced, without attributes but for cells'
-- rowspan and colspan, all of which are kept, and the printed-page citation
-- span; no page may end inside a
-- table with a rowspan, which would detach the spanned rows; and the visible
-- text must survive (at least 95% of the source's letters, after the parts
-- deliberately dropped: head, scripts, styles, MW/Apte record IDs and
-- headword-level markers, and superseded corrections). Every dict_entries query must bind dict_id or id.
-- ./luajit <plugin>/tools/check_dictionaries.lua <plugin> <dpd-mobile.db> [all]
-- With "all", every entry of every dictionary (about a minute on desktop).
require("setupkoenv")
local root, path = assert(arg[1]), assert(arg[2])
package.path = root .. "/?.lua;" .. package.path
local db = require("dpd/db").new(path)
local Dictionaries = require("dpd/dictionaries")
local reader = Dictionaries.new(db)

local query = db.query
local unbound = 0
function db.query(self, sql, params)
    if sql:find("dict_entries", 1, true) and not sql:find("PRAGMA", 1, true)
        and not (sql:find("dict_id = ?", 1, true) or sql:find("WHERE id = ?", 1, true)) then unbound = unbound + 1 end
    return query(self, sql, params)
end

local allowed = { p = true, span = true, br = true, b = true, i = true, sup = true, sub = true, ul = true, ol = true, li = true,
    blockquote = true, hr = true, table = true, tr = true, td = true, th = true }
local void = { br = true, hr = true }
local function letters(text)
    return select(2, text:gsub("[%a\194-\244]", ""))
end
local function visible(html, dict_id)
    html = html:gsub("<head>.-</head>", ""):gsub("<script.-</script>", ""):gsub("<style.-</style>", "")
        :gsub("<span class=\"record%-id\">.-</span>", ""):gsub("<old>.-</old>", ""):gsub("<!%-%-.-%-%->", "")
        :gsub("<%?.-%?>", ""):gsub("<![^>]*>", "")
    if dict_id == "mw" or dict_id == "apte" then
        html = html:gsub("<strong>%(H%d%u?%)</strong>", ""):gsub("<strong>%(C%d%)</strong>", "")
    end
    -- Empty quoted attribute values first: a '>' in one (Apte's
    -- note="…equ->equkaH") does not end the tag.
    return (html:gsub('=%s*"[^"]*"', '=""'):gsub("=%s*'[^']*'", "=''"):gsub("<[^>]+>", ""))
end

local ids = {}
for _, row in ipairs(query(db, "SELECT id FROM dict_entries WHERE length(definition_html) > 20000", {})) do ids[#ids + 1] = row.id end
local large = #ids
local every = arg[3] == "all" and 1 or 50
for _, row in ipairs(query(db, "SELECT id FROM dict_entries WHERE id % ? = 0 AND length(definition_html) <= 20000",
    { every })) do ids[#ids + 1] = row.id end

local failures, pages_total, bytes_total, slowest, slowest_id = {}, 0, 0, 0, nil
local function fail(id, message) failures[#failures + 1] = id .. ": " .. message end
for _, id in ipairs(ids) do
    local source = query(db, "SELECT dict_id, definition_html FROM dict_entries WHERE id = ?", { id })[1]
    local offset, out, ok, spans = 0, {}, true, 0
    repeat
        local started = os.clock()
        local page = reader:page(id, offset)
        local ms = (os.clock() - started) * 1000
        if ms > slowest then slowest, slowest_id = ms, id end
        if not page or page.next_offset <= offset and page.has_more then fail(id, "page does not advance"); ok = false; break end
        local stack = {}
        for slash, name, attributes in page.html:gmatch("<(/?)([%a][%w]*)([^>]*)>") do
            if not allowed[name] then fail(id, "tag " .. name); ok = false end
            local span = (name == "td" or name == "th") and attributes:gsub(' [rc][o][wl]span="%d+"', "") == ""
            local citation = name == "span" and attributes == ' class="src"'
            if attributes ~= "" and not span and not citation then fail(id, "attributes on " .. name); ok = false end
            if span then spans = spans + select(2, attributes:gsub("span=", "")) end
            if not void[name] then
                if slash == "" then stack[#stack + 1] = name
                elseif stack[#stack] == name then stack[#stack] = nil
                else fail(id, "unbalanced " .. name); ok = false end
            end
        end
        if #stack > 0 then fail(id, "unclosed " .. stack[#stack]); ok = false end
        -- Cuts fall right after ">" or a space, or just before "<": never
        -- inside a tag or a character; and outside any comment.
        if page.has_more then
            local c = source.definition_html:byte(page.next_offset)
            local next = source.definition_html:byte(page.next_offset + 1)
            if c ~= 62 and c ~= 32 and next ~= 60 then
                fail(id, "cut at byte " .. page.next_offset .. " is not after > or a space or before <"); ok = false
            end
            local before = source.definition_html:sub(1, page.next_offset)
            local _, opened = before:gsub("<!%-%-", "")
            local _, closed = before:gsub("%-%->", "")
            if opened ~= closed then fail(id, "cut inside a comment"); ok = false end
            local table_start = before:match("^.*()<[tT][aA][bB][lL][eE][%s>]")
            if table_start and not before:find("</[tT][aA][bB][lL][eE]>", table_start) then
                local table_end = source.definition_html:find("</[tT][aA][bB][lL][eE]>", table_start)
                if source.definition_html:sub(table_start, table_end or -1):lower():find("rowspan", 1, true) then
                    fail(id, "cut inside a table with a rowspan"); ok = false
                end
            end
        end
        out[#out + 1] = page.html
        offset = page.next_offset
        pages_total = pages_total + 1
    until not ok or not page.has_more
    if ok then
        if offset ~= #source.definition_html then fail(id, "pages cover " .. offset .. " of " .. #source.definition_html) end
        local want = letters(visible(source.definition_html, source.dict_id))
        local got = letters(table.concat(out):gsub("<[^>]+>", ""))
        local _, want_spans = source.definition_html:lower():gsub('[rc][o][wl]span%s*=%s*"?[2-9]', "")
        if spans ~= want_spans then fail(id, string.format("%d of %d cell spans kept", spans, want_spans)) end
        if got < want * 0.95 then fail(id, string.format("text %d of %d letters", got, want)) end
        bytes_total = bytes_total + #source.definition_html
    end
    if #failures > 20 then break end
end
-- Lookups for a sample of DPD headwords in every dictionary.
local all = {}
for _, d in ipairs(reader:list()) do all[#all + 1] = d.id end
local hits, sampled, lookup_ms = {}, 0, 0
for _, row in ipairs(query(db, "SELECT DISTINCT lemma_1 FROM dpd_headwords WHERE id % 200 = 0", {})) do
    local started = os.clock()
    local groups = reader:lookup({ (row.lemma_1:gsub(" %d[%d.]*$", "")) }, all)
    lookup_ms = math.max(lookup_ms, (os.clock() - started) * 1000)
    for _, group in ipairs(groups) do hits[group.id] = (hits[group.id] or 0) + 1 end
    sampled = sampled + 1
end
local summary = {}
for _, id in ipairs(all) do summary[#summary + 1] = id .. " " .. (hits[id] or 0) end
print(string.format("Lookups: %d sample headwords in all dictionaries, slowest %.1f ms; hits: %s",
    sampled, lookup_ms, table.concat(summary, ", ")))
print(string.format("Release %s: %d articles (%d over 20 KB), %d pages, %.1f MB; slowest page %.1f ms (id %s)",
    tostring(db.info.dpd_release_version), #ids, large, pages_total, bytes_total / 1e6, slowest, tostring(slowest_id)))
for i = 1, math.min(#failures, 20) do print("FAIL " .. failures[i]) end
assert(#failures == 0, #failures .. " failures")
assert(unbound == 0, unbound .. " dict_entries queries without dict_id or id")
print("PASS: dictionary articles page, sanitize and keep their text")
