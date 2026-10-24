local DB = {}
DB.__index = DB

local summary = { "id", "lemma_1", "pos", "meaning_1", "meaning_2", "meaning_lit" }
local detail = { "id", "grammar", "neg", "verb", "trans", "plus_case", "construction",
    "derived_from", "root_key", "compound_type", "compound_construction",
    "example_1", "sutta_1", "source_1", "example_2", "sutta_2", "source_2", "notes",
    "phonetic", "commentary", "root_base", "derivative", "suffix", "antonym", "synonym",
    "variant", "var_phonetic", "var_text", "sanskrit", "cognate", "non_ia", "root_sign",
    "family_root", "family_word", "family_compound", "family_idioms", "family_set",
    "stem", "pattern", "lemma_ipa", "lemma_1", "meaning_1", "link" }
local lookup = { "lookup_key", "headwords", "deconstructor", "grammar", "abbrev",
    "roots", "spelling", "see", "variant", "abbrev_other", "help" }
local root_fields = { "root", "root_group", "root_sign", "root_meaning", "root_example",
    "sanskrit_root", "sanskrit_root_meaning", "note" }
local required = {
    lookup = { "lookup_key", "headwords", "deconstructor" },
    dpd_headwords = { "id", "lemma_1", "pos", "meaning_1", "meaning_2" },
}

-- The one open failure the reader can fix, so the plugin shows it as is.
DB.read_only_message = "DPD cannot read the database in a read-only folder; move it to a writable one: "

function DB.new(path, binding)
    assert(type(path) == "string" and path ~= "", "Choose the DPD database in the DPD menu.")
    local file = assert(io.open(path, "rb"), "DPD database not found or unreadable: " .. path)
    local signature = file:read(16)
    file:close()
    assert(signature == "SQLite format 3\0", "This file is not a SQLite database. Choose the extracted dpd-mobile.db file. If it is damaged, download and extract a fresh copy.")
    local SQ3 = binding or require("lua-ljsqlite3/init")
    -- ro never creates a missing DB or changes the official database contents.
    -- The release is in WAL mode, so SQLite still creates its -shm/-wal files
    -- beside it: the database's folder must be writable.
    local self = setmetatable({ conn = SQ3.open(path, "ro"), path = path,
        statements = {}, columns = {}, query_count = 0, row_count = 0, payload_bytes = 0 }, DB)
    local ok, err = pcall(function()
        self.conn:exec("PRAGMA query_only=1; PRAGMA cache_size=-2048;")
        for table_name, columns in pairs(required) do
            local found = {}
            for _, row in ipairs(self:query("PRAGMA table_info(" .. table_name .. ")")) do found[row.name] = true end
            self.columns[table_name] = found
            for _, column in ipairs(columns) do
                assert(found[column], "Incompatible DPD database: missing " .. table_name .. "." .. column)
            end
        end
        -- Older/minimal databases need not contain the optional root cards.
        self.columns.dpd_roots = {}
        for _, row in ipairs(self:query("PRAGMA table_info(dpd_roots)")) do
            self.columns.dpd_roots[row.name] = true
        end
        self.journal_mode = self:query("PRAGMA journal_mode")[1].journal_mode
        self.info = {}
        local info_ok, rows = pcall(self.query, self, "SELECT key, value FROM db_info")
        if info_ok then for _, row in ipairs(rows) do self.info[row.key] = row.value end end
    end)
    if not ok then
        self:close()
        -- A read-only folder fails as readonly, or as cantopen when a -wal is
        -- already there: SQLite opens the file but not the files beside it.
        local lower = tostring(err):lower()
        if lower:find("readonly", 1, true) or lower:find("cantopen", 1, true) then
            err = DB.read_only_message .. path
        end
        error(err, 0)
    end
    return self
end

function DB:query(sql, params)
    assert(self.conn, "DPD database is closed.")
    local stmt = self.statements[sql]
    if not stmt then stmt = self.conn:prepare(sql); self.statements[sql] = stmt end
    self.query_count = self.query_count + 1
    local ok, rows = pcall(function()
        stmt:reset():clearbind()
        if params and #params > 0 then stmt:bind(unpack(params)) end
        local out, header = {}, {}
        while true do
            local values = stmt:step({}, header)
            if not values then break end
            self.row_count = self.row_count + 1
            local row = {}
            local bytes = 0
            for i, name in ipairs(header) do
                -- lua-ljsqlite3 returns SQLite INTEGERs as int64 cdata. Convert
                -- these before using headword IDs as keys alongside JSON numbers.
                local value = values[i]
                row[name] = type(value) == "cdata" and tonumber(value) or value
                -- Logical result payload, not SQLite page I/O: byte lengths
                -- for text/blobs, eight bytes for numbers, zero for NULL.
                local kind = type(row[name])
                if kind == "string" then bytes = bytes + #row[name]
                elseif kind == "number" then bytes = bytes + 8
                -- lua-ljsqlite3 represents blobs as {pointer, byte_length}.
                elseif kind == "table" and type(value[2]) == "number" then bytes = bytes + value[2] end
            end
            self.payload_bytes = self.payload_bytes + bytes
            out[#out + 1] = row
        end
        return out
    end)
    stmt:reset():clearbind()
    if not ok then error(rows, 0) end
    return rows
end

function DB:selectColumns(table_name, requested)
    local out = {}
    for _, name in ipairs(requested) do
        out[#out + 1] = self.columns[table_name][name] and name or ("'' AS " .. name)
    end
    return table.concat(out, ",")
end

function DB:lookup(key)
    return self:query("SELECT " .. self:selectColumns("lookup", lookup)
        .. " FROM lookup WHERE lookup_key = ?", { key })[1]
end

-- Whether a key is an English word in DPD's English→Pāḷi index.
function DB:english(keys)
    if not self.columns.lookup.epd then return false end
    local marks = string.rep("?,", #keys):sub(1, -2)
    return #self:query("SELECT 1 FROM lookup WHERE lookup_key IN (" .. marks
        .. ") AND epd NOT IN ('', '[]') LIMIT 1", keys) > 0
end

function DB:fuzzyUsablePredicate()
    local predicates = {}
    for _, name in ipairs(lookup) do
        if name ~= "lookup_key" and self.columns.lookup[name] then
            -- The exporter uses both plain text and JSON payloads. Empty JSON
            -- containers (including pretty-printed ones) do not make a hit.
            local value = "lower(replace(replace(replace(replace(coalesce(" .. name
                .. ",''),' ',''),char(9),''),char(10),''),char(13),''))"
            predicates[#predicates + 1] = value .. " NOT IN ('','[]','{}','null','\"\"')"
        end
    end
    return "(" .. table.concat(predicates, " OR ") .. ")"
end

function DB:fuzzy(key, original, offset, limit)
    offset, limit = offset or 0, limit or 20
    assert(type(offset) == "number" and offset >= 0 and offset <= 2147483647
        and offset == math.floor(offset), "Fuzzy offset must be a nonnegative integer.")
    assert(type(limit) == "number" and limit >= 1 and limit <= 200
        and limit == math.floor(limit), "Fuzzy limit must be an integer from 1 to 200.")
    if key == "" or not self.columns.lookup.fuzzy_key then return {} end
    return self:query("SELECT " .. self:selectColumns("lookup", lookup)
        .. " FROM lookup WHERE fuzzy_key = ? AND " .. self:fuzzyUsablePredicate()
        .. " ORDER BY abs(length(lookup_key) - length(?)), lookup_key LIMIT ? OFFSET ?",
        { key, original or key, limit, offset })
end

function DB:fuzzyCount(key)
    if key == "" or not self.columns.lookup.fuzzy_key then return 0 end
    return self:query("SELECT count(*) AS total FROM lookup WHERE fuzzy_key = ? AND "
        .. self:fuzzyUsablePredicate(), { key })[1].total
end

function DB:prefix(key, limit)
    limit = limit or 20
    assert(type(key) == "string" and key ~= "", "Prefix must be nonempty.")
    assert(type(limit) == "number" and limit >= 1 and limit <= 20
        and limit == math.floor(limit), "Prefix limit must be an integer from 1 to 20.")
    -- A byte successor is the exact upper bound for SQLite's BINARY index.
    -- Bound both ends: LIKE, payload predicates, COUNT and length sorting can
    -- turn a common prefix into unbounded work. Filter these raw rows in Lua.
    local upper
    for i = #key, 1, -1 do
        if key:byte(i) < 255 then
            upper = key:sub(1, i - 1) .. string.char(key:byte(i) + 1)
            break
        end
    end
    assert(upper, "Prefix has no upper bound.")
    return self:query("SELECT " .. self:selectColumns("lookup", lookup)
        .. " FROM lookup WHERE lookup_key >= ? AND lookup_key < ?"
        .. " ORDER BY lookup_key LIMIT ?", { key, upper, limit })
end

function DB:batch(table_name, key_column, keys, columns)
    local out = {}
    for start = 1, #keys, 400 do
        local params, placeholders = {}, {}
        for i = start, math.min(start + 399, #keys) do
            params[#params + 1], placeholders[#placeholders + 1] = keys[i], "?"
        end
        local rows = self:query("SELECT " .. self:selectColumns(table_name, columns)
            .. " FROM " .. table_name .. " WHERE " .. key_column .. " IN ("
            .. table.concat(placeholders, ",") .. ")", params)
        for _, row in ipairs(rows) do out[#out + 1] = row end
    end
    return out
end

function DB:lookupMany(keys) return self:batch("lookup", "lookup_key", keys, lookup) end
function DB:senses(ids) return self:batch("dpd_headwords", "id", ids, summary) end
function DB:sensesByLemma(lemmas) return self:batch("dpd_headwords", "lemma_1", lemmas, summary) end
function DB:sanskrit(ids) return self:batch("dpd_headwords", "id", ids, { "id", "sanskrit" }) end
function DB:roots(keys)
    if not self.columns.dpd_roots.root then return {} end
    return self:batch("dpd_roots", "root", keys, root_fields)
end
function DB:detail(id)
    -- Whether frequency data exists, without reading it until it is opened.
    local frequency = self.columns.dpd_headwords.freq_data
        and ",length(freq_data) > 0 AS has_frequency" or ",0 AS has_frequency"
    return self:query("SELECT " .. self:selectColumns("dpd_headwords", detail) .. frequency
        .. " FROM dpd_headwords WHERE id = ?", { id })[1]
end

function DB:close()
    if self.conn then self.conn:close(); self.conn = nil; self.statements = {} end
end

return DB
