-- Run from desktop KOReader with ./luajit <plugin>/tools/check_db.lua <plugin> <dpd-mobile.db>.
require("setupkoenv")
local root, official_path = assert(arg[1], "plugin directory required"), assert(arg[2], "DPD database required")
package.path = root .. "/?.lua;" .. package.path
local DB = require("dpd/db")
local SQ3 = require("lua-ljsqlite3/init")
local fixture_path = os.tmpname()
os.remove(fixture_path)
local fixture = SQ3.open(fixture_path)
fixture:exec([[CREATE TABLE lookup(lookup_key TEXT PRIMARY KEY, headwords TEXT, deconstructor TEXT);
CREATE TABLE dpd_headwords(id INTEGER PRIMARY KEY, lemma_1 TEXT, pos TEXT, meaning_1 TEXT, meaning_2 TEXT);
INSERT INTO lookup VALUES('test','[1]','');
INSERT INTO dpd_headwords VALUES(1,'test','adj','checked','');]])
fixture:close()
local minimal = DB.new(fixture_path)
local queries, rows, bytes = minimal.query_count, minimal.row_count, minimal.payload_bytes
local counted = minimal:query("SELECT 7 AS integer_value, 1.5 AS real_value, 'ā' AS text_value, x'0001ff' AS blob_value, NULL AS absent UNION ALL SELECT 8, 2.5, '', x'', NULL")
assert(#counted == 2 and counted[1].absent == nil)
assert(minimal.query_count - queries == 1 and minimal.row_count - rows == 2)
assert(minimal.payload_bytes - bytes == 37, "two numeric values per row plus UTF-8/blob bytes; NULL is zero")
queries, rows, bytes = minimal.query_count, minimal.row_count, minimal.payload_bytes
assert(#minimal:query("SELECT id FROM dpd_headwords WHERE id = ?", {999}) == 0)
assert(minimal.query_count - queries == 1 and minimal.row_count == rows and minimal.payload_bytes == bytes)
assert(not pcall(minimal.query, minimal, "SELECT missing_column FROM dpd_headwords"))
assert(minimal.row_count == rows and minimal.payload_bytes == bytes, "failed reads cannot invent fetched payload")
assert(#minimal:roots({"√test"}) == 0, "missing optional roots table must be supported")
assert(minimal:detail(1).commentary == "" and minimal:lookup("test").roots == "")
assert(#minimal:sensesByLemma({"test"}) == 1)
assert(#minimal:sensesByLemma({"test' OR 1=1"}) == 0, "lemma batch must bind parameters")
assert(minimal:fuzzyCount("test") == 0 and #minimal:fuzzy("test") == 0)
minimal:close()

fixture = SQ3.open(fixture_path)
local payloads = {"headwords", "deconstructor", "grammar", "roots", "spelling", "see",
    "abbrev", "abbrev_other", "variant", "help"}
fixture:exec("ALTER TABLE lookup ADD COLUMN fuzzy_key TEXT; CREATE INDEX fuzzy_idx ON lookup(fuzzy_key)")
for _, name in ipairs(payloads) do
    if name ~= "headwords" and name ~= "deconstructor" then
        fixture:exec("ALTER TABLE lookup ADD COLUMN " .. name .. " TEXT")
    end
end
fixture:exec("ALTER TABLE lookup ADD COLUMN epd TEXT")
-- Empty JSON containers, whitespace, and excluded sections cannot consume a page.
local insert = fixture:prepare("INSERT INTO lookup(lookup_key,fuzzy_key,headwords,deconstructor,grammar,roots,epd) VALUES(?,?,?,?,?,?,?)")
for i = 1, 25 do
    insert:reset():clearbind():bind("empty" .. i, "group", " [ ] ", "{}", "\n[\t]\n", "null", "[1]"):step()
end
insert:close()
for i, name in ipairs(payloads) do
    local stmt = fixture:prepare("INSERT INTO lookup(lookup_key,fuzzy_key," .. name .. ") VALUES(?,?,?)")
    stmt:bind(string.format("word%02d", i), "group", name == "abbrev" and "a definition" or '["payload"]'):step()
    stmt:close()
end
fixture:exec([=[INSERT INTO lookup(lookup_key,fuzzy_key,grammar) VALUES('near','group','[["test","noun","nom sg"]]');
CREATE TABLE dpd_roots(root TEXT PRIMARY KEY, root_meaning TEXT, note TEXT);
INSERT INTO dpd_roots VALUES('√test','to test','root note');]=])
fixture:close()
local db = DB.new(fixture_path)
assert(db:fuzzyCount("group") == 11, "count must include every independent supported payload")
local all = db:fuzzy("group", "near")
assert(#all == 11 and all[1].lookup_key == "near", "rank by original query length before pagination")
local first, second = db:fuzzy("group", "near", 0, 6), db:fuzzy("group", "near", 6, 6)
assert(#first == 6 and #second == 5)
for i, row in ipairs(first) do assert(row.lookup_key == all[i].lookup_key) end
for i, row in ipairs(second) do assert(row.lookup_key == all[i + 6].lookup_key) end
assert(#db:fuzzy("group", "near", 11, 6) == 0)
assert(db:fuzzyCount("group' OR 1=1") == 0)
for i, name in ipairs(payloads) do
    assert(db:lookup(string.format("word%02d", i))[name] ~= "", "missing projection: " .. name)
end
for _, args in ipairs({{-1,20},{0,0},{0,201},{0,1.5},{0.5,20},{0/0,20},{math.huge,20}}) do
    assert(not pcall(db.fuzzy, db, "group", "near", args[1], args[2]), "invalid pagination must fail")
end
local cards = db:roots({"√test", "√absent"})
assert(#cards == 1 and cards[1].root_meaning == "to test" and cards[1].root_group == "")
assert(#db:roots({"√test' OR 1=1"}) == 0)
db:close()
os.remove(fixture_path)

-- Verify every new field against the official schema and stored values.
local official = DB.new(official_path)
local detail_fields = {"phonetic", "commentary", "root_base", "derivative", "suffix", "antonym",
    "synonym", "variant", "var_phonetic", "var_text"}
for _, name in ipairs(detail_fields) do
    assert(official.columns.dpd_headwords[name], "official detail column missing: " .. name)
    local source = official:query("SELECT id," .. name .. " FROM dpd_headwords WHERE coalesce(" .. name
        .. ",'') != '' LIMIT 1")[1]
        or official:query("SELECT id," .. name .. " FROM dpd_headwords LIMIT 1")[1]
    assert(source and official:detail(source.id)[name] == source[name], "detail data mismatch: " .. name)
end
local root_source = official:query("SELECT root,root_meaning FROM dpd_roots LIMIT 1")[1]
assert(official:roots({root_source.root})[1].root_meaning == root_source.root_meaning)
local senses = official:sensesByLemma({"avaharati", "saṃvidāvahāra"})
assert(#senses == 2)
local candidates = official:fuzzy("samantayitva", "saṃmantayitvā", 0, 200)
assert(#candidates == official:fuzzyCount("samantayitva") and #candidates >= 2)
official:close()
print("DB projections, optional roots, bound batches, fuzzy pagination/count and official data checks passed")
