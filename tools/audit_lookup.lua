-- Lookup runner for tools/audit_book.py: looks up one form per line the way a
-- long-press does and writes one tab-separated result per line. Run from a
-- desktop KOReader directory so DPD uses KOReader's own SQLite and JSON:
-- ./luajit <plugin>/tools/audit_lookup.lua <plugin> <db> <forms.txt> <results.tsv>
require("setupkoenv")
local root, path, input, output = assert(arg[1]), assert(arg[2]), assert(arg[3]), assert(arg[4])
package.path = root .. "/?.lua;" .. package.path
local DB = require("dpd/db")
local Lookup = require("dpd/lookup")
local Popup = require("dpd/popup")
local util = require("util")
local time = require("ui/time")

local db = DB.new(path)
local lookup = Lookup.new(db)
local out = assert(io.open(output, "w"))
out:write("release\t", tostring(db.info and db.info.dpd_release_version or ""), "\n")
local function clean(value) return (tostring(value or ""):gsub("[\t\n]", " ")) end
local count = 0
for form in io.lines(input) do
    if form ~= "" then
        local started = time.now()
        local ok, model = pcall(lookup.get, lookup, util.cleanupSelectedText(form), Popup.selection_options)
        local ms = time.to_ms(time.since(started))
        if ok then
            local parts = model.parts or {}
            out:write(table.concat({ form, Popup.route(model), Lookup.directHit(model) and "hit" or "miss",
                clean(model.matched_via), clean(model.query), model.long_miss and "long" or "",
                clean(parts.begins and parts.begins.form), clean(parts.ends and parts.ends.form),
                #(model.senses or {}), #(model.deconstructions or {}),
                clean(model.suggestions and model.suggestions[1] and model.suggestions[1].query), ms, "" }, "\t"), "\n")
        else
            out:write(table.concat({ form, "error", "miss", "", "", "", "", "", 0, 0, "", ms, clean(model) }, "\t"), "\n")
        end
        count = count + 1
        -- The lookup cache holds 100 results; a fresh one keeps memory flat.
        if count % 2000 == 0 then lookup = Lookup.new(db) end
    end
end
out:close()
db:close()
print("DONE", count)
