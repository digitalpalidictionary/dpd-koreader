local Json = require("json")
local Normalize = require("dpd/normalize")
local Deconstruct = require("dpd/deconstruct")
local SortKey = require("dpd/sortkey")
local Variant = require("dpd/variant")
local Inflection = require("dpd/inflection")
local Traditional = require("dpd/traditional")
local Lookup = { detail_limit = 100 }
Lookup.__index = Lookup

local function decode(raw, field)
    if raw == nil or raw == "" then return nil end
    local ok, value = pcall(Json.decode, raw)
    assert(ok and value ~= nil, "Invalid DPD JSON in " .. field)
    return value
end

local function arrayValues(values, field, kind)
    if values == nil then return {} end
    assert(type(values) == "table", "Invalid DPD array in " .. field)
    local count = 0
    for key, value in pairs(values) do
        count = count + 1
        assert(type(key) == "number" and key >= 1 and key % 1 == 0, "Invalid DPD array in " .. field)
        if kind == "id" then
            assert(type(value) == "number" and value > 0 and value % 1 == 0, "Invalid DPD headword ID")
        elseif kind then assert(type(value) == kind, "Invalid DPD value in " .. field) end
    end
    assert(count == #values and count <= 1000, "Invalid or oversized DPD array in " .. field)
    return values
end

local function array(raw, field, kind) return arrayValues(decode(raw, field), field, kind) end

local function object(value, field)
    if value == nil then return {} end
    assert(type(value) == "table", "Invalid DPD object in " .. field)
    for key in pairs(value) do assert(type(key) == "string", "Invalid DPD object in " .. field) end
    return value
end

local function stringFields(value, names, field)
    local out = {}
    for _, name in ipairs(names) do
        if value[name] ~= nil and type(value[name]) == "string" and value[name] ~= "" then
            out[name] = value[name]
        end
    end
    return out
end

local function keys(value)
    local out = {}
    for key in pairs(value) do out[#out + 1] = key end
    table.sort(out)
    return out
end

-- Optional channels are decoded independently: damage to one must not discard
-- valid senses or analyses. The failure is logged and named in the model.
local logger_ok, logger = pcall(require, "logger")
local function optional(value, row, name, decoder)
    local ok, err = pcall(decoder)
    if ok then return end
    value.damaged[#value.damaged + 1] = name
    if logger_ok and type(logger) == "table" and logger.warn then
        logger.warn("DPD: damaged", name, "data for", row.lookup_key, err)
    end
end

-- A lookup row is a container of independent channels. Variant readings are
-- source/book/context records; spelling and see are notes with optional navigation.
-- Headword IDs, roots and analyses identify the entry and remain strict.
local function payload(row)
    local value = { ids = array(row.headwords, "headwords", "id"),
        root_keys = array(row.roots, "roots", "string"),
        deconstructions = Deconstruct.analyses(array(row.deconstructor, "deconstructor", "string")),
        grammar = {}, references = {}, variants = {}, abbrev_other = {}, damaged = {} }
    optional(value, row, "grammar", function()
        local grammar = {}
        for _, parse in ipairs(array(row.grammar, "grammar", "table")) do
            assert(type(parse[1]) == "string" and type(parse[2]) == "string" and type(parse[3]) == "string",
                "Invalid DPD grammar record")
            grammar[#grammar + 1] = { headword = parse[1], pos = parse[2], parse = parse[3] }
        end
        value.grammar = grammar
    end)
    optional(value, row, "abbreviation", function()
        local abbreviation = stringFields(object(decode(row.abbrev, "abbrev"), "abbrev"),
            { "meaning", "pāli", "example", "explanation" })
        if next(abbreviation) then value.abbrev = abbreviation end
    end)
    optional(value, row, "other abbreviations", function()
        local others = {}
        for _, entry in ipairs(array(row.abbrev_other, "abbrev_other", "table")) do
            local item = stringFields(entry, { "source", "meaning", "notes" })
            if item.meaning or item.notes then others[#others + 1] = item end
        end
        value.abbrev_other = others
    end)
    for _, kind in ipairs({ "spelling", "see" }) do
        optional(value, row, kind .. " references", function()
            local references = {}
            for _, target in ipairs(array(row[kind], kind, "string")) do
                if Normalize.trim(target) ~= "" then
                    references[#references + 1] = { kind = kind, target = target }
                end
            end
            for _, reference in ipairs(references) do value.references[#value.references + 1] = reference end
        end)
    end
    optional(value, row, "variant readings", function()
        local readings = {}
        local variants = object(decode(row.variant, "variant"), "variant")
        for _, source in ipairs(keys(variants)) do
            local books = object(variants[source], "variant books")
            for _, book in ipairs(keys(books)) do
                for _, reading in ipairs(arrayValues(books[book], "variant readings", "table")) do
                    if type(reading[1]) == "string" and type(reading[2]) == "string" then
                        readings[#readings + 1] = {
                            source = source, book = book, context = reading[1], note = reading[2] }
                    end
                end
            end
        end
        value.variants = readings
    end)
    optional(value, row, "help", function()
        local help = decode(row.help, "help")
        if help ~= nil then
            assert(type(help) == "string", "Invalid DPD help text")
            if help ~= "" then value.help = help end
        end
    end)
    return value
end

-- DPD stores a lone "-" as an empty placeholder (e.g. the prefix ajjha).
local function text(value)
    if type(value) ~= "string" or value:match("^%s*%-?%s*$") then return "" end
    return value
end

local function sense(row)
    local edited = text(row.meaning_1) ~= ""
    local meaning = edited and row.meaning_1 or text(row.meaning_2)
    local literal = text(row.meaning_lit)
    if literal ~= "" and (edited or not meaning:find("; lit.", 1, true)) then
        meaning = meaning ~= "" and (meaning .. "; lit. " .. literal) or ("lit. " .. literal)
    end
    return { id = row.id, lemma_1 = row.lemma_1, pos = row.pos, meaning_combo = meaning,
        edited = edited, sort_key = SortKey(row.lemma_1) }
end

local function sorted(ids, by_id)
    local out, seen = {}, {}
    for _, id in ipairs(ids) do
        if by_id[id] and not seen[id] then out[#out + 1] = by_id[id]; seen[id] = true end
    end
    table.sort(out, function(a, b)
        if a.sort_key == b.sort_key then return a.id < b.id end
        return a.sort_key < b.sort_key
    end)
    return out
end

local function model(original, query, via)
    return { original = original, query = query, matched_via = via,
        senses = {}, roots = {}, deconstructions = {}, components = {}, grammar = {},
        references = {}, variants = {}, abbrev_other = {}, suggestions = {}, damaged = {}, found = false }
end

local function shallow(value)
    local out = {}
    for key, item in pairs(value) do out[key] = item end
    return out
end

-- Cached results are shared. Callers get their own top level and lists, so
-- setting a field or sorting/removing items never changes a later lookup.
-- Entries inside the lists remain shared and must be treated as read-only.
local lists = { "senses", "roots", "deconstructions", "components", "grammar", "references",
    "variants", "abbrev_other", "suggestions", "damaged", "spelling_suggestions" }
local function fresh(value)
    local out = shallow(value)
    for _, name in ipairs(lists) do
        if type(value[name]) == "table" then out[name] = shallow(value[name]) end
    end
    return out
end

local function found(value)
    if #value.senses > 0 or #value.deconstructions > 0 or #value.roots > 0 or #value.grammar > 0
        or value.abbrev or #value.abbrev_other > 0 or #value.variants > 0 or value.help
        or #value.references > 0 or #value.suggestions > 0
        or #(value.spelling_suggestions or {}) > 0 then return true end
    return false
end

local function lexical(value)
    if #value.senses > 0 or #value.deconstructions > 0 or #value.roots > 0 then return true end
    for _, reference in ipairs(value.references) do
        if reference.model and lexical(reference.model) then return true end
    end
    return false
end

-- A miss whose only offer is words one edit away (the did-you-mean card).
function Lookup.isSpellingOnly(value)
    if #(value.spelling_suggestions or {}) == 0 then return false end
    local rest = shallow(value)
    rest.spelling_suggestions = nil
    return not found(rest)
end

-- Contextual readings are useful in manual lookup, but alone do not supply a
-- definition. They must not suppress lexical rescue or intercept long-press.
function Lookup.isVariantOnly(value)
    if not (#(value.senses or {}) == 0 and #(value.deconstructions or {}) == 0
        and #(value.roots or {}) == 0 and #(value.grammar or {}) == 0 and not value.abbrev
        and #(value.abbrev_other or {}) == 0 and not value.help and #(value.suggestions or {}) == 0
        and #(value.references or {}) == 0) then
        return false
    end
    return #(value.variants or {}) > 0
end

function Lookup.directHit(value)
    -- Prefix neighbours can be unrelated words, particularly in English books.
    -- They are offered only through an explicit DPD lookup.
    return value.found and value.matched_via ~= "prefix" and not Lookup.isVariantOnly(value)
end

local function mergeMetadata(result, literal)
    local merged = shallow(result)
    for _, name in ipairs({ "grammar", "variants", "abbrev_other", "references", "damaged" }) do
        merged[name] = shallow(result[name])
        for _, value in ipairs(literal[name]) do merged[name][#merged[name] + 1] = value end
    end
    if not merged.abbrev then merged.abbrev = literal.abbrev
    elseif literal.abbrev then merged.abbrev_extra = { { form = literal.query, value = literal.abbrev } } end
    if literal.help then merged.help = (merged.help and merged.help .. "\n" or "") .. literal.help end
    return merged
end

local function context()
    return { path = {}, depth = 0, budget = { remaining = 32 }, rows = {}, payloads = {}, sense_rows = {} }
end

local function descend(parent, key)
    local child = { path = shallow(parent.path), depth = parent.depth + 1,
        budget = parent.budget, rows = parent.rows, payloads = parent.payloads, sense_rows = parent.sense_rows }
    child.path[key] = true
    return child
end

function Lookup.new(db)
    return setmetatable({ db = db, cache = {}, order = {}, details = {}, detail_order = {} }, Lookup)
end

function Lookup:_row(key, ctx)
    local row = ctx.rows[key]
    if row == nil then row = self.db:lookup(key); ctx.rows[key] = row or false end
    return row or nil
end

function Lookup:_payload(row, ctx)
    local decoded = ctx.payloads[row.lookup_key]
    if not decoded then decoded = payload(row); ctx.payloads[row.lookup_key] = decoded end
    return decoded
end

function Lookup:_senses(ids, ctx)
    local missing, seen = {}, {}
    for _, id in ipairs(ids) do
        if ctx.sense_rows[id] == nil and not seen[id] then
            missing[#missing + 1] = id; seen[id] = true
        end
    end
    if #missing > 0 then
        for _, row in ipairs(self.db:senses(missing)) do ctx.sense_rows[row.id] = row end
        for _, id in ipairs(missing) do if ctx.sense_rows[id] == nil then ctx.sense_rows[id] = false end end
    end
    local rows = {}
    for _, id in ipairs(ids) do
        assert(ctx.sense_rows[id], "Missing DPD headword for ID " .. id)
        rows[#rows + 1] = ctx.sense_rows[id]
    end
    return rows
end

-- Prefetch ordinary candidate/component senses once per suggestion page. Each
-- resolver keeps its own reference guards; only immutable row data is shared.
-- Curated references discovered during resolution can fetch additional IDs.
function Lookup:_prefetchSuggestions(rows, shared)
    local ids, component_keys, seen = {}, {}, {}
    for _, row in ipairs(rows) do shared.rows[row.lookup_key] = row end
    for _, row in ipairs(rows) do
        local decoded = self:_payload(row, shared)
        for _, id in ipairs(decoded.ids) do ids[#ids + 1] = id end
        for _, analysis in ipairs(decoded.deconstructions) do
            for _, part in ipairs(analysis.parts or {}) do
                for _, candidate in ipairs(Normalize.candidates(part)) do
                    if shared.rows[candidate.key] == nil and not seen[candidate.key] then
                        component_keys[#component_keys + 1] = candidate.key; seen[candidate.key] = true
                    end
                end
            end
        end
    end
    if #component_keys > 0 then
        for _, row in ipairs(self.db:lookupMany(component_keys)) do shared.rows[row.lookup_key] = row end
        for _, key in ipairs(component_keys) do
            local row = shared.rows[key]
            if row then
                for _, id in ipairs(self:_payload(row, shared).ids) do ids[#ids + 1] = id end
            else shared.rows[key] = false end
        end
    end
    self:_senses(ids, shared)
end

-- Shared exact candidate resolver: an empty/unsupported row must not shadow a
-- lower-case, abbreviation or corpus-alias candidate with dictionary content.
function Lookup:_exact(original, ctx)
    local query = Normalize.query(original)
    local literal = Normalize.literal(original)
    if query == "" and not literal then return model(original, query) end
    local identity = literal or query
    if ctx.path[identity] then return nil, "cycle" end
    if ctx.depth >= 6 then return nil, "depth_limit" end
    local branch = descend(ctx, identity)
    local first, metadata
    local candidates = literal and Normalize.literalCandidates(literal) or {}
    for _, candidate in ipairs(Normalize.candidates(original)) do candidates[#candidates + 1] = candidate end
    for _, candidate in ipairs(candidates) do
        -- A usable literal hyphenated record wins over its hyphen-free alias.
        if metadata and candidate.via == "alias" then break end
        local row = self:_row(candidate.key, branch)
        if row then
            if candidate.key ~= query and ctx.path[candidate.key] then return nil, "cycle" end
            local row_context = shallow(branch)
            row_context.path = shallow(branch.path)
            row_context.path[candidate.key] = true
            local result = self:_build(row, original, candidate.via, row_context)
            if result.found then
                if candidate.literal then return result end
                if lexical(result) then return metadata and mergeMetadata(result, metadata) or result end
                -- A literal abbreviation/context record must not hide lower-
                -- case lexical content (Sace, Nārada, Kaccāyana). Keep both.
                metadata = metadata or result
            end
            first = first or result
        end
    end
    return metadata or first or model(original, query)
end

function Lookup:_reference(target, ctx)
    if ctx.budget.remaining <= 0 then return nil, "limit" end
    ctx.budget.remaining = ctx.budget.remaining - 1
    local result, status = self:_exact(target, ctx)
    if result and result.found then return result end
    -- See records may point at a numbered lemma without an inflection lookup
    -- row. Resolve that exact identity, never fuzzy-substitute its definition.
    if not status and self.db.sensesByLemma then
        local headword = self:headword(target)
        if headword.found then return headword end
    end
    if not status and result then
        for _, reference in ipairs(result.references) do
            if reference.status then status = reference.status; break end
        end
    end
    return nil, status or "missing"
end

-- Marks which parts of each analysis add something (unique, compact,
-- has_new) and which analysis starts open (starts_open).
function Lookup.markAnalyses(result)
    -- A part with no DPD row has no senses to compare.
    local none = { senses = {}, reference_targets = {} }
    -- A whole entry set already shown by the headword or one earlier part is
    -- a repeat. Subsets and combinations show which reading a part takes
    -- (rakkhatiyā: rakkhanta; chāyā after chāya); new correction notes stay
    -- visible too. A subset of an earlier part leading with the senses that
    -- part shows (the popup shows two) would repeat its rows, so it is
    -- compact: its name and which senses, without their meanings again
    -- (kammā after kamma: only kamma 1, 2, 5–8). Headwords show every
    -- definition, so any strict subset of them can use the same compact form.
    local explained, noted, shown = {}, {}, {}
    local function note(target) return target.kind .. "\0" .. target.target end
    local function senseKey(senses)
        local ids = {}
        -- Senses are already sorted and deduplicated by sorted().
        for i, entry in ipairs(senses) do ids[i] = entry.id end
        return table.concat(ids, ",")
    end
    local headword, headword_noted = senseKey(result.senses), {}
    local headword_ids = {}
    -- Headword spellings, for parts that need no "same as" line.
    local headword_forms = {}
    for _, sense in ipairs(result.senses) do
        headword_ids[sense.id] = true
        local base = tostring(sense.lemma_1 or ""):gsub(" [%d.]+$", "")
        headword_forms[Normalize.lower(Normalize.query(base))] = true
    end
    for _, target in ipairs(result.references or {}) do headword_noted[note(target)] = true end
    local function isHeadword(component, key)
        if key ~= headword then return false end
        for _, target in ipairs(component.reference_targets) do
            if not headword_noted[note(target)] then return false end
        end
        return true
    end
    local function isHeadwordSubset(component)
        if #component.senses >= #result.senses then return false end
        for _, sense in ipairs(component.senses) do
            if not headword_ids[sense.id] then return false end
        end
        for _, target in ipairs(component.reference_targets) do
            if not headword_noted[note(target)] then return false end
        end
        return true
    end
    local function looksRepeated(senses)
        for _, earlier in ipairs(shown) do
            local same = true
            for i = 1, math.min(2, #senses) do
                if not earlier[i] or senses[i].id ~= earlier[i].id then same = false; break end
            end
            if same then
                local ids = {}
                for _, entry in ipairs(earlier) do ids[entry.id] = true end
                for _, entry in ipairs(senses) do
                    if not ids[entry.id] then same = false; break end
                end
            end
            if same then return true end
        end
        return false
    end
    -- Only the first analysis that adds something starts open; the others
    -- are one-line splits. Each compares with the headwords and that
    -- analysis alone, so opening any one shows what it adds even with the
    -- others closed; a word two of them share repeats in both.
    local seen, base = {}, nil
    local function copy(values) local out = {}; for k, v in pairs(values) do out[k] = v end; return out end
    for _, analysis in ipairs(result.deconstructions) do
        analysis.unique, analysis.has_new, analysis.compact, analysis.same = {}, false, nil, nil
        if analysis.parts then
            if base then
                explained, noted, shown, seen = copy(base.explained), copy(base.noted), copy(base.shown), copy(base.seen)
            end
            for j, part in ipairs(analysis.parts) do
                local part_key = Normalize.lower(Normalize.query(part))
                analysis.unique[j] = not seen[part_key]; seen[part_key] = true
                local component = result.components[part] or none
                local senses = component.senses
                local key = senseKey(senses)
                if analysis.unique[j] and #senses > 0 then
                    local repeated, compact = explained[key], looksRepeated(senses)
                    for _, target in ipairs(component.reference_targets) do
                        if not noted[note(target)] then repeated, compact = false, false; break end
                    end
                    if repeated or isHeadword(component, key) then
                        analysis.unique[j] = false
                        -- Name where a respelled part is explained. A repeat
                        -- is always respelled: seen caught identical ones.
                        if repeated or not headword_forms[part_key] then
                            analysis.same = analysis.same or {}
                            analysis.same[j] = repeated or { headword = true }
                        end
                    elseif compact or isHeadwordSubset(component) then
                        analysis.compact = analysis.compact or {}
                        analysis.compact[j] = true
                    end
                end
                if analysis.unique[j] then
                    analysis.has_new = true
                    explained[key] = { form = part }
                    shown[#shown + 1] = senses
                    for _, target in ipairs(component.reference_targets) do noted[note(target)] = true end
                end
            end
            analysis.starts_open = analysis.has_new and not base
            if analysis.starts_open then
                base = { explained = explained, noted = noted, shown = shown, seen = seen }
            end
        end
    end
end

-- Component summaries share the same exact aliases/curated reference rules.
-- Their ordinary rows and senses remain batched; no approximate definitions
-- are inserted for unmatched suffixes or other component words.
function Lookup:_components(result, decoded, ctx)
    local component_keys, seen = {}, {}
    for _, analysis in ipairs(decoded.deconstructions) do
        for _, part in ipairs(analysis.parts or {}) do
            for _, candidate in ipairs(Normalize.candidates(part)) do
                if ctx.rows[candidate.key] == nil and not seen[candidate.key] then
                    component_keys[#component_keys + 1] = candidate.key; seen[candidate.key] = true
                end
            end
        end
    end
    if #component_keys > 0 then
        for _, row in ipairs(self.db:lookupMany(component_keys)) do ctx.rows[row.lookup_key] = row end
        for _, key in ipairs(component_keys) do if ctx.rows[key] == nil then ctx.rows[key] = false end end
    end
    local all_ids, id_set = {}, {}
    local all_roots, root_set = {}, {}
    local function collect(values, out, seen_values)
        for _, key in ipairs(values) do
            if not seen_values[key] then out[#out + 1] = key; seen_values[key] = true end
        end
    end
    collect(decoded.ids, all_ids, id_set)
    collect(decoded.root_keys, all_roots, root_set)
    local components = {}
    for _, analysis in ipairs(decoded.deconstructions) do
        for _, part in ipairs(analysis.parts or {}) do
            if not components[part] then
                local data = { ids = {}, root_keys = {}, reference_targets = {} }
                for _, candidate in ipairs(Normalize.candidates(part)) do
                    local row = self:_row(candidate.key, ctx)
                    if row then
                        data.has_row = true
                        local item = self:_payload(row, ctx)
                        data.ids, data.root_keys = item.ids, item.root_keys
                        for _, reference in ipairs(item.references) do
                            data.reference_targets[#data.reference_targets + 1] = {
                                kind = reference.kind, target = reference.target }
                            local resolved = self:_reference(reference.target, ctx)
                            if resolved then
                                data.ids = shallow(data.ids)
                                data.root_keys = shallow(data.root_keys)
                                local function terminals(value)
                                    for _, entry in ipairs(value.senses) do data.ids[#data.ids + 1] = entry.id end
                                    for _, root in ipairs(value.roots) do data.root_keys[#data.root_keys + 1] = root.root end
                                    for _, target in ipairs(value.references) do
                                        if target.model then terminals(target.model) end
                                    end
                                end
                                terminals(resolved)
                            end
                        end
                        -- Empty rows must not mask a later usable summary.
                        if #data.ids > 0 or #data.root_keys > 0 or #data.reference_targets > 0 then break end
                    end
                end
                components[part] = data
                collect(data.ids, all_ids, id_set)
                collect(data.root_keys, all_roots, root_set)
            end
        end
    end
    local by_id = {}
    for _, row in ipairs(self:_senses(all_ids, ctx)) do by_id[row.id] = sense(row) end
    result.senses = sorted(decoded.ids, by_id)
    local by_root = {}
    if #all_roots > 0 and self.db.roots then
        for _, row in ipairs(self.db:roots(all_roots)) do by_root[row.root] = row end
    end
    local function rootCards(root_keys, include_families)
        local out, used = {}, {}
        for _, key in ipairs(root_keys) do
            if by_root[key] and not used[key] then
                local card = by_root[key]
                -- Compact component rows display only the root's meaning.
                -- Load its family metadata when its actual root card opens.
                if include_families then self:rootFamilies(card) end
                out[#out + 1] = card; used[key] = true
            end
        end
        return out
    end
    result.roots = rootCards(decoded.root_keys, true)
    for part, data in pairs(components) do
        local senses = sorted(data.ids, by_id)
        result.components[part] = { form = part, senses = senses, total = #senses,
            roots = rootCards(data.root_keys), reference_targets = data.reference_targets,
            has_row = data.has_row }
    end
    Lookup.markAnalyses(result)
    for _, parse in ipairs(result.grammar) do
        for _, entry in ipairs(result.senses) do
            if entry.lemma_1 == parse.headword then parse.id = entry.id; break end
        end
    end
end

function Lookup:_build(row, original, via, ctx)
    local decoded = self:_payload(row, ctx)
    local result = model(original, row.lookup_key, via)
    result.deconstructions, result.variants = decoded.deconstructions, decoded.variants
    result.grammar, result.abbrev, result.abbrev_other, result.help = decoded.grammar,
        decoded.abbrev, decoded.abbrev_other, decoded.help
    result.damaged = decoded.damaged
    for _, reference in ipairs(decoded.references) do
        local target_model, status = self:_reference(reference.target, ctx)
        result.references[#result.references + 1] = { kind = reference.kind,
            target = reference.target, model = target_model, status = status }
    end
    self:_components(result, decoded, ctx)
    result.found = found(result)
    return result
end

local function suggestion(result, row, candidate, rank, reason)
    return { query = row.lookup_key,
        attestations = (reason == "prefix" or reason == "ti" or reason == "niggahita")
            and {} or Variant.matches(result.query, candidate.variants),
        source_rank = rank, reason = reason, model = candidate }
end

function Lookup:_suggestions(result)
    local offset, invalid = result.suggestion_offset or 0, result.suggestion_invalid or 0
    local total = result.suggestion_scan_total
    local loaded, scanned, batch = 0, 0, {}
    repeat
        local rows = self.db:fuzzy(result.fuzzy_key, result.query, offset, 20)
        if not total then total = self.db.fuzzyCount and self.db:fuzzyCount(result.fuzzy_key) or #rows end
        local shared = context()
        self:_prefetchSuggestions(rows, shared)
        for index, row in ipairs(rows) do
            local ctx = context()
            ctx.rows, ctx.payloads, ctx.sense_rows = shared.rows, shared.payloads, shared.sense_rows
            local candidate = self:_exact(row.lookup_key, ctx)
            -- A neighbour with only variant readings is another word's reading
            -- notes, not a definition: never offer it as a similar form.
            if candidate and candidate.found and not Lookup.isVariantOnly(candidate)
                and not (result.variant_rescue and
                (row.lookup_key == result.query or not lexical(candidate))) then
                batch[#batch + 1] = suggestion(result, row, candidate, offset + index)
                loaded = loaded + 1
            else invalid = invalid + 1 end
        end
        offset, scanned = offset + #rows, scanned + #rows
        if #rows == 0 then total = offset; break end
        -- Skip wholly unusable pages, but bound work on corrupted/future data.
    until loaded > 0 or offset >= total or scanned >= 200
    result.suggestion_offset, result.suggestion_invalid = offset, invalid
    result.suggestion_scan_total, result.suggestion_total = total, total - invalid
    -- Rank this batch only. Show more must not move cards already displayed,
    -- or open new candidates above the reader's current page.
    table.sort(batch, function(a, b)
        local a_attested, b_attested = #a.attestations > 0, #b.attestations > 0
        if a_attested ~= b_attested then return a_attested end
        return a.source_rank < b.source_rank
    end)
    for _, item in ipairs(batch) do result.suggestions[#result.suggestions + 1] = item end
    -- A page with one result does not establish uniqueness when more rows
    -- remain. Only flatten after the complete candidate set is resolved.
    result.single_suggestion = #result.suggestions == 1 and offset >= total
    if #result.suggestions > 0 then result.matched_via = "fuzzy" end
    result.found = found(result)
end

-- Whether DPD's English index has the word, as typed or lowercased.
function Lookup:_english(query)
    if not self.db.english then return false end
    local lower = Normalize.lower(query)
    return self.db:english(lower == query and { query } or { query, lower })
end

-- After a closing quote, "ti" is often printed fused to the next word
-- (’’tiettha, ’’ntiādinā), so a reader's hold selects "tiettha". On a miss,
-- split it off and look up the rest. Only before a vowel: before a consonant
-- "ti" may be the numeral (tivācāya), and real words (tividha) already hit.
local ti_vowels = { a = true, ["ā"] = true, i = true, ["ī"] = true, u = true, ["ū"] = true, e = true, o = true }

function Lookup:_tiSuggestion(result)
    -- Lowercase, so all-caps headings (TIETTHA) split too; the particle
    -- keeps its printed case.
    local query = Normalize.lower(result.query)
    local particle = query:match("^nti") or query:match("^ti")
    if not particle then return false end
    local rest = query:sub(#particle + 1)
    particle = result.query:sub(1, #particle)
    local first = rest:match("^[%z\1-\127\194-\244][\128-\191]*")
    if not ti_vowels[first] or rest == first then return false end
    if self:_english(result.query) then return false end
    local candidate = self:_exact(rest, context())
    if not (candidate and lexical(candidate)) then return false end
    local item = suggestion(result, { lookup_key = candidate.query }, candidate, 1, "ti")
    item.particle = particle
    result.suggestions, result.single_suggestion = { item }, true
    result.suggestion_total, result.matched_via = 1, "ti"
    return true
end

-- Before ti, ṃ is printed n (saccan’ti). A hold stops at the quote and
-- selects "saccan". On a miss, look up saccaṃ. Not under four letters:
-- English in, run and sin would open DPD's iṃ, ruṃ and siṃ. Chanting books
-- print ṃ as ñ or ṅ before a consonant and split there (dhammañ’ca,
-- Yaṅ’kiñci); no Pāḷi or English word ends in ñ or ṅ, so any length.
function Lookup:_niggahitaSuggestion(result)
    -- Lowercase, so all-caps headings (DHAMMAÑ) match too.
    local query = Normalize.lower(result.query)
    local stem, printed = query:match("^(.+)(ñ)$")
    if not stem then stem, printed = query:match("^(.+)(ṅ)$") end
    if not stem then
        stem, printed = query:match("^(.+)(n)$")
        if not stem then return false end
        local _, letters = stem:gsub("[%z\1-\127\194-\244][\128-\191]*", "")
        if letters < 3 then return false end
    end
    if self:_english(result.query) then return false end
    local candidate = self:_exact(stem .. "ṃ", context())
    if not (candidate and lexical(candidate)) then return false end
    local item = suggestion(result, { lookup_key = candidate.query }, candidate, 1, "niggahita")
    item.printed = printed
    result.suggestions = { item }
    result.single_suggestion, result.suggestion_total, result.matched_via = true, 1, "niggahita"
    return true
end

-- A long Pāḷi word with no entry is usually a compound DPD has not analysed.
-- A miss with known parts opens DPD to offer the longest beginning and ending
-- that are DPD forms; one without parts goes to the normal dictionary.
-- Plain substrings only: no sandhi
-- rules and no generated analyses, so pāsāṇa + ādīnaṃ shows as …pāsāṇādīnaṃ.
-- No DPD lookup key is longer than 260 letters (v0.4.20260926), so longer
-- parts are never found; the cap bounds the keys built from very long text.
Lookup.long_word, Lookup.min_part, Lookup.max_part = 15, 5, 300
local pali_marks = { "ā", "ī", "ū", "ṃ", "ṅ", "ñ", "ṭ", "ḍ", "ṇ", "ḷ" }

function Lookup.isLongPali(query)
    local count = 0
    for char in tostring(query or ""):gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        if not Normalize.isPaliLetter(char) then return false end
        count = count + 1
    end
    if count < Lookup.long_word then return false end
    query = Normalize.lower(query)
    for _, mark in ipairs(pali_marks) do
        if query:find(mark, 1, true) then return true end
    end
    return false
end

function Lookup:_parts(query)
    if not self.db.lookupMany then return {} end
    -- Lookup keys are lowercase; a capitalized sentence-initial word is not.
    query = Normalize.lower(query)
    local chars = {}
    for char in query:gmatch("[%z\1-\127\194-\244][\128-\191]*") do chars[#chars + 1] = char end
    local function part(length, from_start)
        return from_start and table.concat(chars, "", 1, length) or table.concat(chars, "", #chars - length + 1)
    end
    local longest_part = math.min(#chars - 1, Lookup.max_part)
    local keys = {}
    for length = longest_part, Lookup.min_part, -1 do
        keys[#keys + 1], keys[#keys + 2] = part(length, true), part(length, false)
    end
    local present = {}
    for _, row in ipairs(self.db:lookupMany(keys)) do present[row.lookup_key] = true end
    local function longest(from_start)
        for length = longest_part, Lookup.min_part, -1 do
            local key = part(length, from_start)
            if present[key] then
                local candidate = self:_exact(key, context())
                if candidate and lexical(candidate) then return { form = key, model = candidate } end
            end
        end
    end
    return { begins = longest(true), ends = longest(false) }
end

function Lookup:_prefixSuggestions(result)
    if not self.db.prefix then return end
    local prefixes, digits = Normalize.shortenedPrefixes(result.query)
    local shared = context()
    local function resolve(key)
        local ctx = context()
        ctx.rows, ctx.payloads, ctx.sense_rows = shared.rows, shared.payloads, shared.sense_rows
        return self:_exact(key, ctx)
    end
    local function finish(prefix)
        result.shortened_prefix, result.matched_via = prefix, "prefix"
        result.suggestion_total = #result.suggestions
        result.found = found(result)
    end
    -- A complete shortened word at either length outranks continuations of a
    -- longer prefix (dhammatq offers dhamma, not dhammatakka...). These are
    -- primary-key lookups, so checking every length first stays cheap.
    for index, prefix in ipairs(prefixes) do
        local candidate = resolve(prefix)
        if candidate and lexical(candidate) then
            local reason = (digits and index == 1) and "digits" or "prefix"
            result.suggestions = { suggestion(result, { lookup_key = candidate.query }, candidate, 1, reason) }
            result.single_suggestion = true
            return finish(prefix)
        end
    end
    for _, prefix in ipairs(prefixes) do
        local rows = self.db:prefix(prefix, 20)
        for _, row in ipairs(rows) do shared.rows[row.lookup_key] = row end
        self:_prefetchSuggestions(rows, shared)
        for index, row in ipairs(rows) do
            local candidate = resolve(row.lookup_key)
            if candidate and lexical(candidate) then
                result.suggestions[#result.suggestions + 1] = suggestion(result, row, candidate, index, "prefix")
            end
        end
        if #result.suggestions > 0 then
            -- A bounded range isn't a complete candidate set. Keep the chooser
            -- even if only one of the scanned rows was usable.
            result.single_suggestion = false
            result.prefix_limited = #rows == 20
            return finish(prefix)
        end
    end
end

function Lookup:get(original, options)
    local query = Normalize.query(original)
    local approximate = not options or options.approximate ~= false
    local prefix = approximate and (not options or options.prefix ~= false)
    local literal = Normalize.literal(original)
    local spelling = approximate and options and options.spelling
    local cache_key = query .. (literal and "\0literal:" .. literal or "")
        .. (prefix and "\0prefix" or approximate and "\0fuzzy" or "\0exact") .. (spelling and "\0spelling" or "")
    local cached = self.cache[cache_key]
    if cached then
        local result = fresh(cached)
        result.original = original
        return result
    end
    local result = self:_exact(original, context()) or model(original, query)
    -- A typed numbered lemma (kata 5, dhamma 1.01) has no inflection row; use
    -- the exact headword route. A bare number is never treated as an ID.
    if not result.found and query:match("^%S.- %d+[%.%d]*$") then
        local headword = self:headword(query)
        if headword.found then headword.original = original; result = headword end
    end
    if (not result.found or Lookup.isVariantOnly(result)) and query ~= "" and approximate then
        result.variant_rescue = Lookup.isVariantOnly(result)
        result.fuzzy_key = Normalize.fuzzy(query)
        self:_suggestions(result)
        local fuzzy_miss = #result.suggestions == 0
            and (result.suggestion_offset or 0) >= (result.suggestion_scan_total or 0)
        -- Manual lookups only: after fuzzy finds nothing, offer words one
        -- edit away, alongside any prefix results.
        if spelling and fuzzy_miss and not result.variant_rescue then
            if not self.suggester then self.suggester = require("dpd/suggest").new(self.db) end
            local ok, items = pcall(self.suggester.spelling, self.suggester, query)
            result.spelling_suggestions = ok and items or {}
            -- Say the suggestions failed, rather than showing a plain miss.
            if not ok then
                result.damaged = shallow(result.damaged)
                result.damaged[#result.damaged + 1] = "spelling suggestions"
                if logger_ok and type(logger) == "table" and logger.warn then
                    logger.warn("DPD: spelling suggestions failed for", query, items)
                end
            end
        end
        -- Variant readings alone are no definition, so they don't stop these
        -- rescues (seṭṭhan’ti, tievamādīsu); the readings stay on the result.
        local split = fuzzy_miss
            and (self:_tiSuggestion(result) or self:_niggahitaSuggestion(result))
        if prefix and fuzzy_miss and not split then self:_prefixSuggestions(result) end
        result.found = found(result)
        if (not result.found or Lookup.isVariantOnly(result)) and Lookup.isLongPali(query) then
            result.parts = self:_parts(query)
            -- Without a useful part, long-press should fall back just like a
            -- short miss; manual lookup keeps its normal spelling/edit advice.
            if result.parts.begins or result.parts.ends then result.long_miss = true end
        end
    end
    self.cache[cache_key] = result
    self.order[#self.order + 1] = cache_key
    if #self.order > 100 then self.cache[table.remove(self.order, 1)] = nil end
    return fresh(result)
end

function Lookup:more(previous)
    local result = shallow(previous)
    result.suggestions = shallow(previous.suggestions)
    if result.fuzzy_key and (result.suggestion_offset or 0) < (result.suggestion_scan_total or 0) then
        self:_suggestions(result)
    end
    return result
end

-- Typed internal navigation for grammatical headwords/numbered references:
-- exact lemma identity is independent of inflected-form lookup keys.
function Lookup:headword(lemma, existing)
    local result = model(lemma, lemma, "headword")
    local candidates = Normalize.candidates(lemma)
    -- Reuse only exact lemma identities. A clean lemma such as dhamma must
    -- still resolve all numbered homonyms, rather than a subset on this page.
    for _, candidate in ipairs(candidates) do
        for _, entry in ipairs(existing and existing.senses or {}) do
            if entry.lemma_1 == candidate.key then result.senses[#result.senses + 1] = entry end
        end
        if #result.senses > 0 then result.query = candidate.key; result.found = true; return result end
    end
    if self.db.sensesByLemma then
        local lemmas, by_lemma = {}, {}
        for _, candidate in ipairs(candidates) do lemmas[#lemmas + 1] = candidate.key end
        for _, row in ipairs(self.db:sensesByLemma(lemmas)) do
            local entries = by_lemma[row.lemma_1] or {}
            entries[#entries + 1] = row
            by_lemma[row.lemma_1] = entries
        end
        -- One indexed batch preserves candidate precedence without one query
        -- per case/alias spelling, including unresolved reference targets.
        for _, candidate in ipairs(candidates) do
            local ids, by_id = {}, {}
            for _, row in ipairs(by_lemma[candidate.key] or {}) do
                ids[#ids + 1] = row.id; by_id[row.id] = sense(row)
            end
            result.senses = sorted(ids, by_id)
            if #result.senses > 0 then result.query = candidate.key; break end
        end
    end
    if #result.senses == 0 then
        -- Grammar stores clean lemmas (e.g. dhamma), while lemma_1 preserves
        -- homonym identities (dhamma 1.01). Use exact lookup IDs and retain
        -- only senses of that clean lemma; never route through fuzzy search.
        for _, candidate in ipairs(candidates) do
            local row = self.db:lookup(candidate.key)
            if row then
                local ids, by_id = {}, {}
                for _, record in ipairs(self.db:senses(array(row.headwords, "grammar headwords", "id"))) do
                    local clean = record.lemma_1:gsub(" %d[%d%.]*$", "")
                    if record.lemma_1 == candidate.key or clean == candidate.key then
                        ids[#ids + 1] = record.id; by_id[record.id] = sense(record)
                    end
                end
                result.senses = sorted(ids, by_id)
                if #result.senses > 0 then result.query = candidate.key; break end
            end
        end
    end
    result.found = #result.senses > 0
    return result
end

-- Detail links carry a typed, exact identity. They never use fuzzy/prefix
-- substitution, and numbered roots are not widened to their unnumbered family.
function Lookup:target(value, kind)
    local query = Normalize.trim(Normalize.nfc(tostring(value or "")))
    if query == "" or query:match("^%d+[%.%d]*$") then return nil end
    kind = kind or (query:sub(1, 3) == "√" and "root" or "form")
    if kind == "root" then
        if not self.db.roots then return nil end
        local roots = self.db:roots({ query })
        if #roots == 0 then return nil end
        local result = model(value, query, "root")
        result.roots, result.found = roots, true
        for _, root in ipairs(roots) do self:rootFamilies(root) end
        return result
    elseif kind == "headword" then
        local result = self:headword(query)
        return result.found and result or nil
    elseif kind == "form" then
        -- Preserve an explicitly numbered headword before an inflection key.
        local headword = self:headword(query)
        if headword.found then return headword end
        local result = self:get(query, { approximate = false })
        return result.found and not Lookup.isVariantOnly(result) and result or nil
    end
end

function Lookup:_familyReader()
    if not self.families then self.families = require("dpd/families").new(self.db) end
    return self.families
end

function Lookup:rootFamilies(root)
    if type(root) == "table" then
        if not root.families then root.families = self:_familyReader():groupsForRoot(root) end
        return root.families
    end
    return self:_familyReader():groupsForRoot(root)
end

function Lookup:family(kind, key, offset, limit)
    local page = self:_familyReader():page(kind, key, offset, limit)
    local result = model(page.title or key, key, "family")
    result.family = page
    -- An empty/damaged family still needs a view explaining its result.
    result.found = true
    return result
end

function Lookup:moreFamily(previous, limit)
    local result = shallow(previous)
    if not previous.family or not previous.family.has_more then return result end
    local old = previous.family
    local page = self:_familyReader():page(old.kind, old.key,
        old.next_offset or ((old.offset or 0) + #old.items), limit)
    result.family = shallow(page)
    result.family.offset = old.offset or 0
    result.family.items = shallow(old.items)
    for _, item in ipairs(page.items) do result.family.items[#result.family.items + 1] = item end
    return result
end

-- A root's full information (Dhātupāṭha and other references, bases), read
-- only when its "Root details" link is opened.
function Lookup:rootDetails(root)
    if not self.root_info then self.root_info = require("dpd/rootinfo").new(self.db) end
    local result = model(root, root, "root-details")
    result.root_details = self.root_info:details(root)
        or { root = root, rows = {}, error = "DPD has no further information for this root." }
    result.found = true
    return result
end

-- A root's matrix (its headwords by part of speech and derivation), read only
-- when its "Root matrix" link is opened. With `group` and `row`, one row's
-- headwords.
function Lookup:rootMatrix(root, group, row)
    if not self.root_matrix then self.root_matrix = require("dpd/rootmatrix").new(self.db) end
    local matrix = self.root_matrix:matrix(root)
    local result = model(root, root, "root-matrix")
    result.found = true
    if group then
        local g = matrix.groups[group]
        local r = g and g.rows[row]
        if not r then return nil end
        result.matrix_row = { root = root, group = g.name, label = r.label, items = r.items }
    else
        result.root_matrix = matrix
    end
    return result
end

-- English→Pāḷi for the lookup dialog's English mode: Pāḷi headwords whose
-- meaning has the English word, paged.
function Lookup:english(word)
    if not self.english_reader then self.english_reader = require("dpd/english").new(self.db) end
    local page = self.english_reader:page(word)
    local result = model(word, page.query or word, "english")
    result.english = page
    result.found = #page.items > 0
    return result
end

function Lookup:moreEnglish(previous)
    local result = shallow(previous)
    local old = previous.english
    if not old or not old.has_more then return result end
    local page = self.english_reader:page(previous.original, old.next_offset)
    result.english = shallow(page)
    result.english.offset = 0
    result.english.items = shallow(old.items)
    for _, item in ipairs(page.items) do result.english.items[#result.english.items + 1] = item end
    return result
end

-- Entries in the other bundled dictionaries for a result, read only when
-- "Other dictionaries" is opened. Keys: the result's clean headwords
-- (deduplicated across senses and grammar parses), else the looked-up form.
function Lookup:_dictionaries()
    if not self.dictionaries then self.dictionaries = require("dpd/dictionaries").new(self.db) end
    return self.dictionaries
end

function Lookup:hasOtherDictionaries()
    return self:_dictionaries():available()
end

function Lookup:otherDictionaries(previous, enabled)
    self:_dictionaries()
    local keys, seen = {}, {}
    local function add(lemma)
        local clean = tostring(lemma or ""):gsub(" %d[%d.]*$", "")
        if clean ~= "" and not seen[clean] then seen[clean] = true; keys[#keys + 1] = clean end
    end
    -- A single similar form displays its candidate's entry, so search that.
    local shown = previous.single_suggestion and previous.suggestions[1].model or previous
    for _, sense in ipairs(shown.senses or {}) do add(sense.lemma_1) end
    for _, parse in ipairs(shown.grammar or {}) do add(parse.headword) end
    if #keys == 0 then add(previous.query); add(previous.original_clean) end
    -- Only the first few forms are searched; the view says how many are not.
    local searched = {}
    for i = 1, math.min(#keys, self.dictionaries.max_keys) do searched[i] = keys[i] end
    -- The shown senses' Sanskrit equivalents, in sense order, for the
    -- Sanskrit dictionaries (Dictionaries.sanskrit).
    local ids, sanskrit, seen_word = {}, {}, {}
    for _, sense in ipairs(shown.senses or {}) do ids[#ids + 1] = sense.id end
    if #ids > 0 and self.db.sanskrit then
        local Dictionaries, fields = require("dpd/dictionaries"), {}
        for _, row in ipairs(self.db:sanskrit(ids)) do fields[row.id] = row.sanskrit end
        for _, id in ipairs(ids) do
            for _, word in ipairs(Dictionaries.sanskritWords(fields[id])) do
                if not seen_word[word] then seen_word[word] = true; sanskrit[#sanskrit + 1] = word end
            end
        end
    end
    local result = model(previous.query, previous.query, "dictionaries")
    result.dictionaries = { keys = searched, omitted = #keys - #searched,
        groups = self.dictionaries:lookup(searched, enabled, sanskrit) }
    result.found = true
    return result
end

-- Apte lists many nouns in the nominative (dharmaḥ, agniḥ, but ātman), so a
-- typed stem ending in a vowel is also tried with ḥ.
local nominative = { a = true, ["ā"] = true, i = true, ["ī"] = true, u = true, ["ū"] = true,
    e = true, o = true, ["ṛ"] = true, ["ṝ"] = true }
Lookup.max_dictionary_query = 100

--- Typed text searched in the selected other dictionaries, from the DPD menu.
--- Tried literally first, punctuation and all (DPPN's "Accayasutta
--- (Akodhanasutta)", WordNet's "e.g."), then cleaned as a selection is, for
--- pasted text such as “dhamma,”. Each as typed (DPPN's "Mahā Bodhi") and
--- lower-cased (MW's "śāriputra" for "Śāriputra"); after a final vowel the
--- cleaned form also with ḥ, and after a also with ṃ, as Apte lists nouns
--- (dharmaḥ, phalaṃ). The lower-cased literal comes last, so the key limit
--- (Dictionaries.max_keys) drops it first. Always returns a model to show: a
--- miss, or no dictionaries selected, is a result the reader should see.
--- `draft` is the text as typed, before Velthuis input converted it: each
--- dictionary that finds nothing for the converted text tries it as typed,
--- so English vacuum is not lost as vacūm.
function Lookup:searchDictionaries(text, enabled, draft)
    local literal = Normalize.trim(Normalize.nfc(text or "")):gsub("\194\173", "")
        :gsub("ṁ", "ṃ"):gsub("Ṁ", "ṃ"):gsub("ŋ", "ṃ"):gsub("Ŋ", "ṃ")
    if #literal > Lookup.max_dictionary_query then
        local cut = Lookup.max_dictionary_query
        while cut > 0 and literal:byte(cut + 1) >= 0x80 and literal:byte(cut + 1) < 0xC0 do cut = cut - 1 end
        literal = Normalize.trim(literal:sub(1, cut))
    end
    local keys, seen = {}, {}
    local function add(key)
        if key ~= "" and not seen[key] then seen[key] = true; keys[#keys + 1] = key end
    end
    add(literal)
    local cleaned = Normalize.selection(literal)
    add(cleaned)
    local lower = Normalize.lower(cleaned)
    add(lower)
    local last = lower:match("[%z\1-\127\194-\244][\128-\191]*$")
    if last and nominative[last] then add(lower .. "ḥ") end
    if last == "a" then add(lower .. "ṃ") end
    add(Normalize.lower(literal))
    local typed = {}
    draft = Normalize.trim(Normalize.nfc(draft or ""))
    if draft ~= "" and draft ~= literal and #draft <= Lookup.max_dictionary_query then
        typed = { draft, Normalize.lower(draft) }
    end
    local result = model(text, literal, "dictionaries")
    result.dictionary_search = true
    -- The header names only what was typed, not the extra forms tried.
    result.dictionaries = { keys = { literal }, omitted = 0, none_selected = enabled ~= nil and #enabled == 0,
        groups = #keys > 0 and self:_dictionaries():lookup(keys, enabled, nil, typed) or {} }
    result.found = #result.dictionaries.groups > 0
    return result
end

--- Appends a dictionary group's next entries; returns how many.
function Lookup:moreDictionaryEntries(group)
    return self:_dictionaries():more(group)
end

function Lookup:dictionaryPage(id, offset)
    return self:_dictionaries():page(id, offset)
end

-- One headword by its DPD ID, for typed ID searches; nil when there is none.
function Lookup:byId(id)
    id = tonumber(id)
    if not id or id < 1 or id ~= math.floor(id) then return nil end
    local row = self.db:senses({ id })[1]
    if not row then return nil end
    local result = model(tostring(id), row.lemma_1, "id")
    result.senses[1] = sense(row)
    result.found = true
    return result
end

function Lookup:_sutta()
    if not self.sutta_reader then self.sutta_reader = require("dpd/sutta").new(self.db) end
    return self.sutta_reader
end

-- A headword's sutta information, read only when opened.
function Lookup:sutta(id)
    local sense = self.db:senses({ id })[1]
    if not sense then return nil end
    local result = model(sense.lemma_1, sense.lemma_1, "sutta")
    result.sutta = self:_sutta():info(sense.lemma_1)
        or { lemma = sense.lemma_1, records = {}, error = "DPD has no sutta information for this entry." }
    result.found = true
    return result
end

-- A headword's frequency table, read only when opened.
function Lookup:frequency(id)
    local sense = self.db:senses({ id })[1]
    if not sense then return nil end
    if not self.frequency_reader then self.frequency_reader = require("dpd/frequency").new(self.db) end
    local result = model(sense.lemma_1, sense.lemma_1, "frequency")
    result.frequency = self.frequency_reader:table(id)
    result.frequency.lemma = sense.lemma_1
    result.found = true
    return result
end

-- A headword's full declension or conjugation, generated only when opened.
-- `selected` is the looked-up form to highlight; it never widens the
-- headword's own identity.
function Lookup:paradigm(id, selected)
    local detail = self:detail(id)
    local sense = self.db:senses({ id })[1]
    if not sense then return nil end
    if not self.inflection then self.inflection = Inflection.new(self.db) end
    local result = model(sense.lemma_1, sense.lemma_1, "paradigm")
    result.paradigm = self.inflection:paradigm(detail, sense.lemma_1, selected)
    result.found = true
    return result
end

-- Split only field-defined operators, never arbitrary prose. Keep each raw
-- fragment (including DPD's inline emphasis) intact for the safe renderer.
local function fieldSegments(value, separators)
    local parts, start, index, in_tag = {}, 1, 1, false
    while index <= #value do
        local char = value:sub(index, index)
        if char == "<" and value:sub(index):match("^</?%a[^>]*>") then in_tag = true end
        if not in_tag and separators[char] then
            local first, last = index, index
            while first > start and value:sub(first - 1, first - 1):match("[ \t]") do first = first - 1 end
            while last < #value and value:sub(last + 1, last + 1):match("[ \t]") do last = last + 1 end
            if first > start then parts[#parts + 1] = { text = value:sub(start, first - 1) } end
            parts[#parts + 1] = { text = value:sub(first, last), separator = true }
            start, index = last + 1, last
        end
        if char == ">" then in_tag = false end
        index = index + 1
    end
    if start <= #value then parts[#parts + 1] = { text = value:sub(start) } end
    return parts
end

local function targetText(value)
    -- Only supported presentation elements may disappear during resolution;
    -- attributed/unrecognised tags and entities remain unmatched text.
    return Normalize.trim((value:gsub("<[^>]+>", function(tag)
        local permitted = { b=true, strong=true, i=true, em=true, sub=true, sup=true }
        local name = tag:match("^</?([%a]+)%s*>$")
        return name and permitted[name:lower()] and "" or tag
    end)))
end

function Lookup:_detailTargets(row)
    row.field_parts, row.targets = {}, {}
    local fields = { construction = { ["+"]=true, ["\n"]=true },
        compound_construction = { ["+"]=true, ["\n"]=true }, derived_from = {}, root_key = {},
        synonym = { [","]=true }, antonym = { [","]=true } }
    local resolved = {}
    for _, field in ipairs({ "construction", "compound_construction", "derived_from", "root_key", "synonym", "antonym" }) do
        local value = text(row[field])
        if value ~= "" then
            local parts = fieldSegments(value, fields[field])
            for _, part in ipairs(parts) do
                if not part.separator then
                    local word = targetText(part.text)
                    local kind = (field == "root_key" or word:sub(1, 3) == "√") and "root" or "form"
                    local identity = kind .. "\0" .. word
                    if resolved[identity] == nil then
                        local ok, target = pcall(self.target, self, word, kind)
                        resolved[identity] = ok and target or false
                        if not ok and logger_ok and type(logger) == "table" and logger.warn then
                            logger.warn("DPD: unreadable detail target for", row.id, word, target)
                        end
                    end
                    if resolved[identity] then
                        row.targets[#row.targets + 1] = { text = word, kind = kind, model = resolved[identity] }
                        part.target_index = #row.targets
                    end
                end
            end
            row.field_parts[field] = parts
        end
    end
end

function Lookup:detail(id)
    if not self.details[id] then
        local row = self.db:detail(id) or {}
        local grammar = text(row.grammar)
        for _, name in ipairs({ "neg", "verb", "trans" }) do
            local value = text(row[name])
            if value ~= "" then grammar = grammar .. (grammar ~= "" and ", " or "") .. value end
        end
        local plus_case = text(row.plus_case)
        if plus_case ~= "" then grammar = grammar .. " (" .. plus_case .. ")" end
        row.grammar_line = grammar
        local ipa = text(row.lemma_ipa)
        row.ipa_line = ipa ~= "" and ("/" .. ipa .. "/") or nil
        row.traditional_line = Traditional.lemma(row)
        -- DPD's degree of completion (tools/degree_of_completion.py): any
        -- stored value counts, even the "-" the display hides. DPD marks
        -- entries with no source to cite "-" and still calls them complete.
        local function filled(value) return type(value) == "string" and value ~= "" end
        if not filled(row.meaning_1) then row.status_line = "✘ incomplete"
        elseif not filled(row.source_1) then row.status_line = "◑ meaning, no source yet"
        else row.status_line = "✔ complete" end
        -- DPD's own web links (akka 2: Calotropis gigantea), one per line.
        local web = text(row.link):gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s*\n%s*", ", ")
        row.web_line = web ~= "" and web or nil
        row.link_line = tonumber(row.id) and ("dpdict.net/" .. math.floor(tonumber(row.id))) or nil
        self:_detailTargets(row)
        -- The root's meaning beside it, as dpdict.net shows: √i 1 (come, go).
        local root_part = row.field_parts.root_key and row.field_parts.root_key[1]
        local root_target = root_part and root_part.target_index and row.targets[root_part.target_index]
        local root = root_target and root_target.model.roots and root_target.model.roots[1]
        if root and text(root.root_meaning) ~= "" then row.root_meaning = root.root_meaning end
        row.families = self:_familyReader():groupsForDetail(row)
        row.paradigm_kind = Inflection.available(row) and Inflection.kind(row.pattern) or nil
        -- A canonical name uses an indexed probe and a narrow label read;
        -- aliases also need the alias table, built once per database.
        local reader = self:_sutta()
        local ok, kind = pcall(reader.has, reader, row.lemma_1)
        row.sutta_kind = ok and kind or nil
        self.details[id] = row
        -- Bound database-session retention. Navigation frames may still own an
        -- evicted row, and reopening it can fetch a fresh copy safely.
        self.detail_order[#self.detail_order + 1] = id
        if #self.detail_order > self.detail_limit then
            self.details[table.remove(self.detail_order, 1)] = nil
        end
    end
    return self.details[id]
end

return Lookup
