-- From KOReader's directory, using its bundled LuaJIT/SQLite:
-- ./luajit <plugin>/tools/check_budget.lua <plugin> <mobile.db> [--update-baseline] [--baseline <file>]
require("setupkoenv")
local root, path = assert(arg[1], "plugin directory required"), assert(arg[2], "DPD database required")
package.path = root .. "/?.lua;" .. package.path
local DB = require("dpd/db")
local Lookup = require("dpd/lookup")
local Navigation = require("dpd/navigation")
local Popup = require("dpd/popup")
local Render = require("ui/dpd_render")
local Json = require("json")
local sha256 = require("ffi/sha2").sha256
local time = require("ui/time")
local util = require("util")
local repeats = 20
local settings = { dictionaries = require("dpd/dictionaries").defaults, niggahita = "ṃ",
    paradigm_columns = 1, content_em = 30,
    english_edit_search = true, selection_options = Popup.selection_options,
    selection_approximate = Popup.selection_options.approximate ~= false }

-- Expectations are independent of the recorded ceilings. Updating a baseline
-- cannot bless a miss, missing sense or wrong route for one of these cases.
local cases = {
    {word="pacchima", senses=8, grammar=4},
    {word="dhammassa", senses=16, grammar=8, variants=1},
    {word="vajjakammappabhedanti", analyses=5},
    {word="pacchimakattikapuṇṇamā", analyses=1},
    {word="√har", roots=4},
    {word="√gam", roots=1},
    {word="hotī", reference="hotīti", variants=3},
    {word="sajjasīti", reference="sajjesīti", variants=1},
    {word="uyyokhajja", route="dictionary", variants=2},
    {word="kā", senses=7, grammar=19, roots=1, variants=3},
    {word="Buddha", query="buddha", via="ci", senses=2},
    {word="saṁ", query="saṃ", senses=12, grammar=15},
    {word="dhammā", query="dhammā", senses=17, grammar=28},
    {word="bhikkhave’ti", query="bhikkhaveti", senses=2, analyses=1},
    {word="akaṭa-anudhammena", query="akaṭaanudhammena", via="alias", analyses=1},
    {word="indakhile", via="fuzzy", suggestions=1, suggestion="indakhīle"},
    {word="saṃmantayitvā", via="fuzzy", suggestions=2},
    {word="nnāṭṭā", via="fuzzy", suggestions=20},
    {word="dpdtestnomatch", route="dictionary", found=false},
    {word="timing", route="dictionary", found=false},
    {word="timing", mode="english", found=false, total=0},
    {word="mind", mode="english", total=10},
    {word="sanskrit", mode="english", query="Sanskrit", total=1},
}

-- Stable JSON for reviewable baseline diffs and platform-independent semantic
-- fingerprints. Empty tables are objects; case/settings lists are nonempty.
local function encode(value, indent)
    if type(value) ~= "table" then return Json.encode(value) end
    local keys, array = {}, true
    for key in pairs(value) do
        keys[#keys + 1] = key
        if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then array = false end
    end
    table.sort(keys)
    array = array and #keys > 0 and keys[#keys] == #keys
    local parts, depth = {}, indent and indent + 2 or nil
    for _, key in ipairs(keys) do
        parts[#parts + 1] = (depth and string.rep(" ", depth) or "")
            .. (array and "" or Json.encode(key) .. (indent and ": " or ":")) .. encode(value[key], depth)
    end
    local first, last = array and "[" or "{", array and "]" or "}"
    if #parts == 0 then return first .. last end
    return first .. (indent and "\n" or "") .. table.concat(parts, indent and ",\n" or ",")
        .. (indent and "\n" .. string.rep(" ", indent) or "") .. last
end

local function fingerprint(value) return sha256(encode(value)) end
local function stats(values)
    table.sort(values)
    return (values[math.floor((#values + 1) / 2)] + values[math.ceil((#values + 1) / 2)]) / 2,
        values[math.ceil(#values * .95)]
end
local function elapsed(start) return time.to_us(time.monotonic() - start) / 1000 end
local function counters(db)
    return { queries=db.query_count, rows=db.row_count, payload_bytes=db.payload_bytes }
end
local function delta(db, before)
    return { queries=db.query_count-before.queries, rows=db.row_count-before.rows,
        payload_bytes=db.payload_bytes-before.payload_bytes }
end

local summary_columns = {id=true, lemma_1=true, pos=true, meaning_1=true, meaning_2=true, meaning_lit=true}
local root_columns = {root=true, root_group=true, root_sign=true, root_meaning=true, root_example=true,
    sanskrit_root=true, sanskrit_root_meaning=true, note=true}
local function guard(sql)
    local lower = sql:lower()
    assert(not lower:find("from%s+dict_entries") and not lower:find("from%s+sutta_info"),
        "unopened dictionary/sutta payload read: " .. sql)
    -- Initial headword summaries and root cards have a fixed narrow projection.
    -- This also rejects SELECT *, new detail columns and frequency/root payloads
    -- even when an attempted query would happen to return no rows.
    local allowed = lower:find("from%s+dpd_headwords") and summary_columns
        or lower:find("from%s+dpd_roots") and root_columns
    if allowed then
        local projection = assert(lower:match("^select%s+(.-)%s+from"), "unknown initial query: " .. sql)
        for column in projection:gmatch("[^,]+") do
            local name = column:match("^%s*([%w_]+)%s*$") or column:match("^%s*''%s+as%s+([%w_]+)%s*$")
            assert(name and allowed[name], "unopened detail payload read: " .. sql)
        end
    end
end

-- Trace initialization too: moving a feature read into DB.new must not escape
-- the lazy-payload assertions. This wrapper exists only in the check process.
local query = DB.query
function DB:query(sql, params)
    self.budget_violations = self.budget_violations or {}
    local ok, err = pcall(guard, sql)
    if not ok then
        self.budget_violations[#self.budget_violations + 1] = err
        error(err, 0)
    end
    return query(self, sql, params)
end

local function expected(case, model, route, html)
    local function equal(actual, wanted, label)
        assert(actual == wanted, case.word .. ": unexpected " .. label .. " (" .. tostring(actual) .. ")")
    end
    equal(model.query, case.query or case.word, "query")
    equal(route, case.route or "dpd", "popup route")
    equal(model.found, case.found ~= false, "result presence")
    local via = case.mode == "english" and "english" or case.via or "exact"
    if case.found == false and case.mode ~= "english" then via = nil end
    equal(model.matched_via, via, "match type")
    for field, member in pairs({senses="senses", grammar="grammar", analyses="deconstructions",
        roots="roots", variants="variants", suggestions="suggestions"}) do
        if case[field] then equal(#model[member], case[field], field) end
    end
    if case.reference then equal(model.references[1] and model.references[1].target, case.reference, "reference") end
    if case.suggestion then equal(model.suggestions[1] and model.suggestions[1].query, case.suggestion, "suggestion") end
    if case.total then
        equal(model.english.total, case.total, "English total")
        equal(#model.english.items, math.min(case.total, 20), "English first page")
        assert(not model.english.error, "damaged English data")
    end
    if route == "dictionary" then equal(#html, 0, "fallback HTML"); return end
    if case.mode == "english" and not model.found then
        assert(html:find('href="dpd:edit-search"', 1, true), "missing English miss recovery action")
    end
    -- Check initial disclosures and reveal their bodies outside the measured
    -- render. Collapsed candidates must remain reachable, not disappear from
    -- this semantic gate just because the initial HTML is smaller.
    local expanded = Navigation.new(model):current()
    if not model.single_suggestion then
        for index in ipairs(model.suggestions or {}) do
            assert(expanded.suggestions[index].open == (index <= Navigation.open_similar),
                "only the first similar forms should start open")
            assert(html:find('href="dpd:similar/' .. index .. '"', 1, true), "missing candidate disclosure")
            assert(html:find('href="dpd:suggestion/' .. index .. '"', 1, true), "missing candidate navigation")
        end
    end
    local function reveal(frame)
        for _, child in ipairs(frame.suggestions) do child.open = true; reveal(child) end
        for _, child in pairs(frame.references) do reveal(child) end
    end
    reveal(expanded)
    local revealed_html = Render.render(model, expanded)
    -- Check that all preserved data is actually rendered after disclosure.
    local function visible(value, scope)
        for _, sense in ipairs(value.senses or {}) do
            assert(revealed_html:find("sense/" .. sense.id .. '"', 1, true), "missing rendered sense " .. sense.id)
        end
        for _, card in ipairs(value.roots or {}) do
            assert(revealed_html:find(Render.escape(card.root), 1, true), "missing root")
        end
        for index, analysis in ipairs(value.deconstructions or {}) do
            -- Duplicate-only and malformed rows have no disclosure. Respelled
            -- parts can still expand to a "same as" note without new senses.
            local expands = analysis.has_new == true or analysis.same ~= nil
            local toggle = revealed_html:find('href="dpd:' .. scope .. 'analysis/' .. index .. '"', 1, true) ~= nil
            assert(toggle == expands, expands and "missing compound analysis disclosure"
                or "unexpected compound analysis disclosure")
            if analysis.parts then
                for part in ipairs(analysis.parts) do
                    assert(revealed_html:find('href="dpd:' .. scope .. 'component/' .. index .. '/' .. part .. '"', 1, true),
                        "missing compound component link")
                end
            else
                assert(revealed_html:find(index .. ' · ' .. Render.escape(analysis.raw) .. '</p>', 1, true),
                    "missing raw compound analysis")
            end
        end
        for index, item in ipairs(value.suggestions or {}) do visible(item.model, scope .. 'similar/' .. index .. '/') end
        for index, item in ipairs(value.references or {}) do
            if item.model then visible(item.model, scope .. 'reference/' .. index .. '/') end
        end
    end
    visible(model, "")
    for index in ipairs(model.english and model.english.items or {}) do
        assert(html:find('href="dpd:english-item/' .. index .. '"', 1, true), "missing English item")
    end
end

local function main()
    local update, filename = false, root .. "/tools/budget_baseline.json"
    local index = 3
    while index <= #arg do
        if arg[index] == "--update-baseline" then update = true
        elseif arg[index] == "--baseline" then index = index + 1; filename = assert(arg[index], "--baseline needs a file")
        else error("unknown option: " .. arg[index]) end
        index = index + 1
    end
    local open_times, opening = {}, nil
    local function open()
        local start = time.monotonic()
        local db = DB.new(path)
        open_times[#open_times + 1] = elapsed(start)
        assert(#db.budget_violations == 0, table.concat(db.budget_violations, "\n"))
        local cost = counters(db)
        opening = opening or cost
        assert(encode(opening) == encode(cost), "inconsistent database-open costs")
        return db, Lookup.new(db)
    end
    local db = open()
    local database = { release=assert(db.info.dpd_release_version, "missing database release"),
        schema=tostring(assert(db.info.db_schema_version, "missing database schema")) }
    db:close()
    local result = {format_version=1, database=database, settings=settings, opening=opening,
        case_signature=fingerprint(cases), cases={}}
    local baseline
    if not update then
        local file = assert(io.open(filename, "rb"), "missing baseline; record it with --update-baseline")
        baseline = Json.decode(file:read("*a")); file:close()
        assert(baseline.format_version == result.format_version, "unsupported baseline format")
        assert(encode(baseline.database) == encode(database) and encode(baseline.settings) == encode(settings),
            "baseline is for a different DB/settings; review before --update-baseline")
        assert(baseline.case_signature == result.case_signature and #baseline.cases == #cases,
            "baseline is for a different case list; review before --update-baseline")
    end
    print("DPD budget: " .. database.release .. " schema " .. database.schema .. "; " .. #cases
        .. " cases, " .. repeats .. " samples/pass; fresh connection/model and primed cache")
    local failures = {}
    if baseline then
        for _, metric in ipairs({"queries", "rows", "payload_bytes"}) do
            local ceiling = assert(baseline.opening[metric], "missing database-open ceiling")
            if opening[metric] > ceiling then
                failures[#failures + 1] = string.format("DB open: %s %d > %d", metric, opening[metric], ceiling)
            end
        end
    end
    for _, pass in ipairs({"fresh", "cached"}) do
        for number, case in ipairs(cases) do
            local label = (case.mode or "selection") .. ":" .. case.word
            result.cases[number] = result.cases[number] or {name=label, word=case.word, mode=case.mode or "selection"}
            local lookup_times, render_times, first = {}, {}, nil
            local db, lookup
            local function measure()
                local before, start = counters(db), time.monotonic()
                local model
                if case.mode == "english" then model = lookup:english(case.word)
                else
                    local clean = util.cleanupSelectedText(case.word)
                    model = lookup:get(clean, Popup.selection_options)
                    model.original, model.original_clean = case.word, clean
                end
                local lookup_ms = elapsed(start)
                start = time.monotonic()
                local route, html = Popup.route(model), ""
                if route == "dpd" then
                    local frame = Navigation.new(model):current()
                    html = Popup.render(lookup, frame, {
                        dictionaries=settings.dictionaries,
                        niggahita=settings.niggahita, paradigm_columns=settings.paradigm_columns,
                        content_em=settings.content_em, edit_search=case.mode == "english" and settings.english_edit_search,
                    })
                    assert(frame.other_dictionaries == true, "missing dictionary availability")
                end
                local render_ms, cost = elapsed(start), delta(db, before)
                assert(#db.budget_violations == 0, table.concat(db.budget_violations, "\n"))
                cost.html_bytes = #html
                expected(case, model, route, html)
                cost.result_signature = fingerprint(model)
                return cost, lookup_ms, render_ms
            end
            if pass == "cached" then db, lookup = open(); measure() end -- prime model and popup metadata
            for sample = 1, repeats do
                if pass == "fresh" then db, lookup = open() end
                local ok, cost, lookup_ms, render_ms = pcall(measure)
                if pass == "fresh" or not ok then db:close() end
                assert(ok, cost)
                first = first or cost
                assert(encode(first) == encode(cost), label .. ": inconsistent " .. pass .. " costs/results")
                lookup_times[sample], render_times[sample] = lookup_ms, render_ms
            end
            if pass == "cached" then db:close() end
            result.cases[number][pass] = first
            local lookup_median, lookup_p95 = stats(lookup_times)
            local render_median, render_p95 = stats(render_times)
            print(string.format("%-7s %-35s queries=%d rows=%d payload=%d HTML=%d lookup median/p95=%.3f/%.3f ms render median/p95=%.3f/%.3f ms",
                pass, label, first.queries, first.rows, first.payload_bytes, first.html_bytes,
                lookup_median, lookup_p95, render_median, render_p95))
            if baseline then
                local recorded = assert(baseline.cases[number][pass], "missing baseline pass")
                assert(baseline.cases[number].name == label, "baseline case order mismatch")
                assert(recorded.result_signature == first.result_signature, label .. ": result differs from baseline")
                for _, metric in ipairs({"queries", "rows", "payload_bytes", "html_bytes"}) do
                    local ceiling = assert(recorded[metric], "missing baseline metric " .. metric)
                    if first[metric] > ceiling then
                        failures[#failures + 1] = string.format("%s %s: %s %d > %d", pass, label, metric, first[metric], ceiling)
                    end
                end
            elseif pass == "cached" then
                assert(result.cases[number].fresh.result_signature == first.result_signature,
                    label .. ": cached result differs from fresh result")
            end
        end
    end
    local median, p95 = stats(open_times)
    print(string.format("DB open (separate budget): queries=%d rows=%d payload=%d median/p95 %.3f/%.3f ms, %d opens",
        opening.queries, opening.rows, opening.payload_bytes, median, p95, #open_times))
    assert(#failures == 0, table.concat(failures, "\n"))
    if update then
        local temporary = filename .. ".tmp"
        local file = assert(io.open(temporary, "wb")); assert(file:write(encode(result, 0), "\n")); assert(file:close())
        assert(os.rename(temporary, filename))
        print("Updated baseline: " .. filename)
    end
    print("PASS: expected results/routing, lazy payload reads and all four exact budgets")
end

local ok, err = xpcall(main, debug.traceback)
if not ok then io.stderr:write("FAIL: ", tostring(err), "\n"); os.exit(1) end
