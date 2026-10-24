-- Run from a disposable desktop KOReader extraction with its bundled LuaJIT:
-- SDL_VIDEODRIVER=dummy KO_MULTIUSER=1 XDG_CONFIG_HOME=<temporary directory> \
-- ./luajit <plugin>/tools/check_failure_containment.lua <plugin>
-- Uses the real UIManager, MuPDF popup trees and SQLite binding. Small models
-- and a temporary DB avoid needing official data; this is not a parity gate.
require("setupkoenv")
local root = assert(arg[1], "plugin directory required")
package.path = root .. "/?.lua;" .. package.path
G_defaults = require("luadefaults"):open()
G_reader_settings = require("luasettings"):wrap({})
local Device = require("device")
require("document/canvascontext"):init(Device)
require("ui/bidi").setup()
assert(#require("dpd/compat").missing() == 0, "supported KOReader required")
local UIManager = require("ui/uimanager")
local Viewer = require("ui/dpd_viewer")
local Diag = require("dpd/diag")
local lookup = {detail=function() return {} end}
local function model()
    return {query="test",original="test",found=true,senses={{id=7,lemma_1="test",meaning_combo="example"}},
        grammar={},deconstructions={},suggestions={},references={},roots={},variants={}}
end
local function shown(widget)
    for _, window in ipairs(UIManager._window_stack) do if window.widget == widget then return true end end
    return false
end
local function flush() UIManager:_checkTasks(); UIManager:_repaint() end
local function clearMessages()
    for i = #UIManager._window_stack, 1, -1 do
        local widget = UIManager._window_stack[i].widget
        if type(widget.text) == "string" and widget.text:find("DPD could not open this view",1,true) then
            UIManager:close(widget)
        end
    end
    flush()
end
local function popup(options)
    options = options or {}
    options.model, options.lookup = model(), lookup
    local viewer = Viewer:new(options)
    UIManager:show(viewer); flush()
    assert(shown(viewer))
    return viewer
end

for _, diagnostics in ipairs({false, true}) do
    Diag.setEnabled(diagnostics)
    local parent = popup()
    local closes = 0
    local child = popup({parent_viewer=parent,close_callback=function() closes = closes + 1 end})
    child.navigation.toggleSense = function() error("injected native navigation failure") end
    child:onLink("dpd:sense/7"); flush()
    assert(child.closed and not shown(child) and shown(parent) and not parent.closed)
    assert(closes == 1 and child._pending_update == nil)
    child:close(); assert(closes == 1)
    clearMessages()
    parent:close(); flush()

    local releases, handoffs = 0, 0
    local handoff = popup({normal_callback=function()
        handoffs = handoffs + 1; error("injected native handoff failure")
    end,release_selection_callback=function() releases = releases + 1 end})
    handoff:onLink("dpd:normal"); handoff:onLink("dpd:normal"); flush()
    assert(handoff.closed and not shown(handoff) and releases == 1 and handoffs == 1)
    clearMessages()

    local edits = 0
    local edit = popup({edit_callback=function() edits = edits + 1; error("injected native edit failure") end})
    edit:onLink("dpd:edit-search"); flush()
    assert(edit.closed and not shown(edit) and edits == 1)
    clearMessages()

    local tap = popup()
    tap.linkAt = function() error("injected native hit-test failure") end
    assert(tap.scroll.htmlbox_widget:onTapText(nil,{pos={x=1,y=1}}))
    flush(); assert(tap.closed and not shown(tap))
    clearMessages()

    local before, owner = 0, 0
    local cleanup = popup({before_close_callback=function()
        before = before + 1; error("injected native child cleanup failure")
    end,close_callback=function() owner = owner + 1; error("injected native owner cleanup failure") end})
    cleanup:update()
    cleanup:close(); cleanup:close(); flush()
    assert(cleanup.closed and not shown(cleanup) and before == 1 and owner == 1)
    assert(cleanup._pending_update == nil)
    clearMessages()
    print("Native containment passed, diagnostics=" .. tostring(diagnostics))
end
Diag.setEnabled(false)
assert(#UIManager._window_stack == 0, "no popup/message should remain registered")

local DPD = require("main")
local plugin = setmetatable({settings={},ui={}}, {__index=DPD})
plugin.ensureLookup = function() error("About must not open a database") end
plugin:showHelp(); flush()
local help = UIManager._window_stack[#UIManager._window_stack].widget
assert(help.title == "DPD help" and help.buttons_table[1][1].text == "About & licenses")
help.buttons_table[1][1].callback(); flush()
local about = UIManager._window_stack[#UIManager._window_stack].widget
assert(about.title == "About & licenses" and about.text:find("not opened / unknown",1,true))
UIManager:close(about); flush()
assert(shown(help), "closing About returns to the help screen")
UIManager:close(help); flush()
plugin.db = {info={dpd_release_version="native-test-version"}}
plugin:aboutLicenses(); flush()
about = UIManager._window_stack[#UIManager._window_stack].widget
assert(about.text:find("Database version: native-test-version",1,true))
UIManager:close(about); flush()
print("Native About screen passed with missing and available database metadata")

-- Exercise actual DB.new with native SQLite rather than a synthetic binding.
local SQ3 = require("lua-ljsqlite3/init")
local path = os.tmpname()
os.remove(path)
local connection = SQ3.open(path)
connection:exec([[CREATE TABLE lookup(lookup_key TEXT PRIMARY KEY,headwords TEXT,deconstructor TEXT);
CREATE TABLE dpd_headwords(id INTEGER PRIMARY KEY,lemma_1 TEXT,pos TEXT,meaning_1 TEXT,meaning_2 TEXT);
CREATE TABLE db_info(key TEXT PRIMARY KEY,value TEXT);
INSERT INTO db_info VALUES('db_schema_version','999'),('dpd_release_version','future-test');]])
connection:close()
local DB = require("dpd/db")
local db = DB.new(path)
assert(db.info.db_schema_version == "999", "a newer schema with the core columns opens")
assert(not pcall(db.query,db,"INSERT INTO lookup VALUES('test','[]','[]')"), "native connection stays read-only")
db:close(); os.remove(path)
print("Native newer-schema and read-only check passed")

-- A database in a read-only folder fails with the message the reader can act
-- on, whether it is a fresh copy or has a -wal beside it, and the recovery
-- dialog shows that message.
local lfs = require("libs/libkoreader-lfs")
local base = os.tmpname()
os.remove(base); lfs.mkdir(base)
local fresh, copied = base .. "/fresh", base .. "/copied"
lfs.mkdir(fresh); lfs.mkdir(copied)
local schema = [[PRAGMA journal_mode=WAL;
CREATE TABLE lookup(lookup_key TEXT PRIMARY KEY,headwords TEXT,deconstructor TEXT);
CREATE TABLE dpd_headwords(id INTEGER PRIMARY KEY,lemma_1 TEXT,pos TEXT,meaning_1 TEXT,meaning_2 TEXT);]]
connection = SQ3.open(fresh .. "/dpd-mobile.db"); connection:exec(schema); connection:close()
-- Copy while rows are still only in the -wal, as from a reader that was open.
connection = SQ3.open(base .. "/dpd-mobile.db")
connection:exec(schema .. "PRAGMA wal_autocheckpoint=0; INSERT INTO lookup VALUES('a','[1]','[]');")
os.execute(string.format("cp '%s/dpd-mobile.db' '%s/dpd-mobile.db-wal' '%s/'", base, base, copied))
connection:close()
assert((lfs.attributes(copied .. "/dpd-mobile.db-wal", "size") or 0) > 0, "copied database keeps its -wal")
os.execute(string.format("chmod 555 '%s' '%s'", fresh, copied))
local writable = io.open(fresh .. "/probe", "w")
if writable then
    writable:close(); os.remove(fresh .. "/probe")
    print("Native read-only folder check skipped: this user can write to read-only folders")
else
    for _, dir in ipairs({fresh, copied}) do
        local opened, err = pcall(DB.new, dir .. "/dpd-mobile.db")
        assert(not opened and err == DB.read_only_message .. dir .. "/dpd-mobile.db", tostring(err))
        plugin:recoverDatabase(err, "dhamma", "pali"); flush()
        local dialog = UIManager._window_stack[#UIManager._window_stack].widget
        assert(dialog.title == err, "recovery dialog shows the read-only message")
        UIManager:close(dialog); flush()
    end
    print("Native read-only folder check passed for a fresh copy and one with a -wal")
end
os.execute(string.format("chmod 755 '%s' '%s'; rm -rf '%s'", fresh, copied, base))
