-- Lookup runner for tools/check_spelling.py: looks up one typed word per line
-- the way the Look up a word dialog does and writes where the expected word
-- ranks among the "Did you mean" suggestions. Run from a desktop KOReader
-- directory so DPD uses KOReader's own SQLite and JSON:
-- ./luajit <plugin>/tools/spelling_lookup.lua <plugin> <db> <cases.tsv> <results.tsv>
-- Cases are "set<TAB>typed<TAB>expected"; results add the rank (0: not
-- offered, -1: fuzzy matching found the word, so no spelling list), the
-- first five suggestions and milliseconds.
require("setupkoenv")
local root, path, input, output = assert(arg[1]), assert(arg[2]), assert(arg[3]), assert(arg[4])
package.path = root .. "/?.lua;" .. package.path
local DB = require("dpd/db")
local Lookup = require("dpd/lookup")
local time = require("ui/time")

local db = DB.new(path)
local lookup = Lookup.new(db)
local out = assert(io.open(output, "w"))
local count = 0
for line in io.lines(input) do
    local set, typed, expected = line:match("^([^\t]*)\t([^\t]*)\t([^\t]*)$")
    if set then
        local started = time.now()
        local model = lookup:get(typed, { spelling = true })
        local ms = time.to_ms(time.since(started))
        local items, rank, top = model.spelling_suggestions, -1, {}
        if items then
            rank = 0
            for i, item in ipairs(items) do
                if item.text == expected and rank == 0 then rank = i end
                top[#top + 1] = item.text
            end
        end
        out:write(table.concat({ set, typed, expected, rank, table.concat(top, " "), ms }, "\t"), "\n")
        count = count + 1
        if count % 2000 == 0 then lookup = Lookup.new(db) end
    end
end
out:close()
db:close()
print("DONE", count)
