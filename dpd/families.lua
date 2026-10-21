local Json = require("json")
local Families = {}
Families.__index = Families

-- SQL identifiers are fixed here. Keys and pagination values are always bound.
local kinds = {
    root = { table_name="family_root", key="root_family_key", label="Root family" },
    word = { table_name="family_word", key="word_family", label="Word family" },
    compound = { table_name="family_compound", key="compound_family", label="Compounds" },
    idiom = { table_name="family_idiom", key="idiom", label="Idioms" },
    -- "set" is an SQL keyword, so its column needs quoting in statements.
    set = { table_name="family_set", key="set", column='"set"', label="Thematic set" },
}
local MAX_KEY, MAX_DATA, MAX_MEMBERS = 1024, 1048576, 10000
local DAMAGE = "Unreadable DPD family data. Choose another family or replace the database with a fresh DPD mobile download."

local function validKey(key)
    return type(key) == "string" and key ~= "" and #key <= MAX_KEY and not key:find("\0",1,true)
end

local function count(value)
    value = tonumber(value)
    return value and value >= 0 and value == math.floor(value) and value <= MAX_MEMBERS and value or 0
end

local function title(kind,key)
    return kinds[kind].label .. ": " .. key
end

local function remember(cache,order,key,value,limit)
    if cache[key] == nil then
        order[#order+1] = key
        if #order > limit then cache[table.remove(order,1)] = nil end
    end
    cache[key] = value
    return value
end

function Families.new(db)
    return setmetatable({ db=db, schemas={}, metadata={}, metadata_order={},
        decoded={}, decoded_order={} },Families)
end

function Families:_schema(kind)
    if self.schemas[kind] ~= nil then return self.schemas[kind] end
    local config = kinds[kind]
    local columns = {}
    if type(self.db.query) == "function" then
        local ok,rows = pcall(self.db.query,self.db,"PRAGMA table_info(" .. config.table_name .. ")")
        if ok then for _,row in ipairs(rows) do columns[row.name] = true end end
    end
    local usable = columns[config.key] and columns.data and columns.count
    if kind == "root" then usable = usable and columns.root_key and columns.root_family end
    self.schemas[kind] = usable and true or false
    return self.schemas[kind]
end

function Families:_metadata(kind,key)
    if not validKey(key) or not self:_schema(kind) then return nil end
    local cache_key = kind .. "\0" .. key
    if self.metadata[cache_key] ~= nil then return self.metadata[cache_key] or nil end
    local config = kinds[kind]
    local extra = kind == "root" and ",root_family" or ""
    local column = config.column or config.key
    local ok,rows = pcall(self.db.query,self.db,"SELECT " .. column .. " AS family_key,count"
        .. extra .. " FROM " .. config.table_name .. " WHERE " .. column .. " = ? LIMIT 1",{key})
    local row = ok and rows[1]
    local group = row and {kind=kind,key=key,
        title=title(kind,validKey(row.root_family) and row.root_family or key),count=count(row.count)}
    remember(self.metadata,self.metadata_order,cache_key,group or false,128)
    return group
end

function Families:groupsForDetail(row)
    local out,seen = {},{}
    if type(row) ~= "table" then return out end
    local function add(kind,key)
        local identity = kind .. "\0" .. key
        if seen[identity] then return end
        seen[identity] = true
        local group = self:_metadata(kind,key)
        if group and group.count > 0 then out[#out+1] = group end
    end
    if validKey(row.root_key) and validKey(row.family_root) then
        add("root",row.root_key .. " " .. row.family_root)
    end
    if validKey(row.family_word) then add("word",row.family_word) end
    -- Unlike root/word family names, these exporter fields contain space-separated
    -- group keys, not one multiword group. Resolve every token independently.
    for _,field in ipairs({{name="family_compound",kind="compound"},{name="family_idioms",kind="idiom"}}) do
        if validKey(row[field.name]) then
            for key in row[field.name]:gmatch("%S+") do add(field.kind,key) end
        end
    end
    -- Set names contain spaces ("names of monks"); several are joined by "; ".
    if validKey(row.family_set) then
        for name in (row.family_set .. ";"):gmatch("([^;]*);") do
            name = name:match("^%s*(.-)%s*$")
            if name ~= "" then add("set",name) end
        end
    end
    return out
end

-- Cached and shared: callers must not change the returned list.
function Families:groupsForRoot(root)
    local key = type(root) == "table" and root.root or root
    if not validKey(key) or not self:_schema("root") then return {} end
    local cache_key = "root-card\0" .. key
    if self.metadata[cache_key] ~= nil then return self.metadata[cache_key] end
    local ok,rows = pcall(self.db.query,self.db,
        "SELECT root_family_key AS family_key,root_family,count FROM family_root WHERE root_key = ?"
        .. " ORDER BY root_family_key LIMIT 1000",{key})
    local out = {}
    if ok then
        for _,row in ipairs(rows) do
            if validKey(row.family_key) and count(row.count) > 0 then
                out[#out+1] = {kind="root",key=row.family_key,
                    title=title("root",validKey(row.root_family) and row.root_family or row.family_key),count=count(row.count)}
            end
        end
    end
    return remember(self.metadata,self.metadata_order,cache_key,out,128)
end

local function array(value)
    assert(type(value) == "table","Family data must be an array")
    local n = 0
    for key in pairs(value) do
        assert(type(key) == "number" and key >= 1 and key == math.floor(key),"Family data must be an array")
        n = n+1
    end
    assert(n == #value and n <= MAX_MEMBERS,"Invalid or oversized family array")
    return value
end

function Families:_members(kind,key)
    local cache_key = kind .. "\0" .. key
    if self.decoded[cache_key] then return self.decoded[cache_key] end
    local config = kinds[kind]
    local ok,value = pcall(function()
        local rows = self.db:query("SELECT data FROM " .. config.table_name .. " WHERE "
            .. (config.column or config.key) .. " = ? LIMIT 1",{key})
        if not rows[1] or rows[1].data == nil or rows[1].data == "" then return {items={}} end
        local raw = rows[1].data
        assert(type(raw) == "string" and #raw <= MAX_DATA and raw:match("^%s*%["),"Invalid family JSON")
        local decoded,position,decode_error = Json.decode(raw)
        assert(not decode_error and (type(position) ~= "number" or raw:sub(position):match("^%s*$")),"Invalid family JSON")
        local members = array(decoded)
        local items = {}
        for _,member in ipairs(members) do
            array(member)
            assert(#member >= 3 and #member <= 4,"Invalid family member")
            assert(validKey(member[1]) and type(member[2]) == "string" and type(member[3]) == "string"
                and (member[4] == nil or type(member[4]) == "string"),"Invalid family member")
            items[#items+1] = {lemma=member[1],pos=member[2],meaning=member[3],completion=member[4]}
        end
        return {items=items}
    end)
    return remember(self.decoded,self.decoded_order,cache_key,ok and value or {items={},error=DAMAGE},4)
end

function Families:page(kind,key,offset,limit)
    assert(kinds[kind],"Unknown DPD family kind")
    assert(validKey(key),"Family key must be a nonempty string of at most 1024 bytes")
    offset,limit = offset or 0,limit or 20
    assert(type(offset) == "number" and offset >= 0 and offset <= 2147483647 and offset == math.floor(offset),
        "Family offset must be a nonnegative integer")
    assert(type(limit) == "number" and limit >= 1 and limit <= 100 and limit == math.floor(limit),
        "Family page size must be an integer from 1 to 100")
    local result = {kind=kind,key=key,title=title(kind,key),total=0,offset=offset,items={},has_more=false,next_offset=offset}
    if not self:_schema(kind) then return result end
    local group = self:_metadata(kind,key)
    if not group then return result end
    result.title = group.title
    local members = self:_members(kind,key)
    result.total,result.error = #members.items,members.error
    local lemmas,seen = {},{}
    for i = offset+1,math.min(offset+limit,result.total) do
        local member = members.items[i]
        result.items[#result.items+1] = {lemma=member.lemma,pos=member.pos,meaning=member.meaning,
            completion=member.completion,available=false}
        if not seen[member.lemma] then seen[member.lemma] = true;lemmas[#lemmas+1] = member.lemma end
    end
    if #lemmas > 0 and type(self.db.sensesByLemma) == "function" then
        local ok,rows = pcall(self.db.sensesByLemma,self.db,lemmas)
        if ok then
            local ids = {}
            for _,row in ipairs(rows) do
                local id = tonumber(row.id)
                if seen[row.lemma_1] and id and id > 0 and id == math.floor(id)
                    and (not ids[row.lemma_1] or id < ids[row.lemma_1]) then ids[row.lemma_1] = id end
            end
            for _,item in ipairs(result.items) do item.id=ids[item.lemma];item.available=item.id ~= nil end
        end
    end
    result.next_offset = offset+#result.items
    result.has_more = result.next_offset < result.total
    return result
end

return Families
