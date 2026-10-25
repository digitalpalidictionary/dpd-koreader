-- Run from a disposable desktop KOReader extraction:
-- KO_MULTIUSER=1 XDG_CONFIG_HOME=<temporary directory> SDL_VIDEODRIVER=dummy \
-- ./luajit <plugin>/tools/check_lifecycle.lua <plugin> <db> "$DPD_BOOK"
-- Use a fresh temporary EPUB copy with no .sdr for each run; see
-- docs/KOREADER_RUNBOOK.md for the DPD_BOOK setup.
assert(os.getenv("KO_MULTIUSER") == "1" and os.getenv("XDG_CONFIG_HOME"), "use an isolated profile")
require("setupkoenv")
local root, path, book = assert(arg[1]), assert(arg[2]), assert(arg[3])
G_defaults = require("luadefaults"):open()
local DataStorage = require("datastorage")
G_reader_settings = require("luasettings"):open(DataStorage:getDataDir() .. "/settings.reader.lua")
local lfs = require("libs/libkoreader-lfs")
-- Exercise a shipped copy: .git deliberately disables obsolete-folder cleanup.
local fixture = DataStorage:getDataDir() .. "/dpd-lifecycle"
assert(lfs.mkdir(fixture), "use a fresh profile for each lifecycle check")
assert(lfs.mkdir(fixture .. "/plugins"))
local installed = fixture .. "/plugins/dpd.koplugin"
assert(lfs.mkdir(installed))
local function q(value) return "'" .. value:gsub("'", "'\\''") .. "'" end
for _, name in ipairs({ "main.lua", "_meta.lua", "dpd", "ui" }) do
    assert(os.execute("cp -R " .. q(root .. "/" .. name) .. " " .. q(installed)) == 0)
end
root = installed
local disabled = {}
for entry in lfs.dir("plugins") do
    if entry:sub(-9) == ".koplugin" then disabled[entry:sub(1,-10)] = true end
end
G_reader_settings:saveSetting("plugins_disabled", disabled)
G_reader_settings:saveSetting("extra_plugin_paths", {assert(root:match("^(.+)/[^/]+$"))})
G_reader_settings:saveSetting("dpd", {db_path=path, direct_lookup=true})
local Device = require("device")
require("document/canvascontext"):init(Device)
require("ui/bidi").setup()
local UIManager = require("ui/uimanager")
local Event = require("ui/event")
local FileManager = require("apps/filemanager/filemanager")
local ReaderUI = require("apps/reader/readerui")
local function flush() UIManager:_checkTasks(); UIManager:_repaint() end

-- ljsqlite pins connections in its native statement registry. Counting that
-- registry catches leaks even after all plugin instances have been collected.
local SQ3 = require("lua-ljsqlite3/init")
local registry
for i = 1, 30 do
    local name, value = debug.getupvalue(SQ3.open, i)
    if name == "connstmt" then registry = value; break end
end
assert(registry, "SQLite connection registry required")
local function countConnections()
    local n = 0
    for _ in pairs(registry) do n = n + 1 end
    return n
end
local base_connections = countConnections()
for i = 1, 3 do
    FileManager:showFiles(assert(book:match("^(.+)/[^/]+$")))
    flush(); flush()
    local manager = assert(FileManager.instance)
    local plugin = assert(manager.dpd, "FileManager must load the plugin")
    local closed = 0
    assert(plugin:showLookup("pacchima", {close_callback=function() closed = closed + 1 end}))
    flush()
    local first = assert(plugin.viewer)
    first:close(); flush()
    assert(closed == 1 and not plugin.stopped and plugin.db,
        "Closing a popup must keep its owning FileManager plugin alive")
    assert(plugin:showLookup("pacchima", {close_callback=function() closed = closed + 1 end}))
    flush()
    local viewer, db = assert(plugin.viewer), assert(plugin.db)
    manager:onClose(); flush()
    assert(not FileManager.instance and plugin.stopped and not plugin.db and not plugin.lookup)
    assert(not db.conn and viewer.closed and not plugin.viewer and closed == 2,
        "FileManager teardown must close the native connection and popup once")
    plugin:onCloseWidget(); plugin:onCloseDocument(); plugin:onExit(); plugin:stopPlugin()
    assert(closed == 2 and not pcall(plugin.ensureLookup, plugin),
        "Repeated teardown must be harmless and retired plugins must not reopen")
end
collectgarbage("collect"); collectgarbage("collect")
assert(countConnections() == base_connections, "FileManager cycles must not pin SQLite connections")

ReaderUI:showReader(book)
flush(); flush()
local reader = assert(ReaderUI.instance)
local plugin = assert(reader.dpd)
local prior = reader.dictionary.onLookupWord
local outer_calls, outer_args, outer_count = 0
local outer = function(dictionary, ...)
    outer_calls = outer_calls + 1
    outer_args, outer_count = {...}, select("#", ...)
    return prior(dictionary, ...)
end
reader.dictionary.onLookupWord = outer
plugin.settings.direct_lookup = false; plugin:syncDirectMode()
assert(reader.dictionary.onLookupWord == outer)
plugin.settings.direct_lookup = true; plugin:syncDirectMode()
local close_callback = function() end
reader.dictionary:onLookupWord("pacchima", false, nil, reader.highlight, nil, close_callback)
flush()
local viewer = assert(plugin.viewer)
viewer:onLink("dpd:normal"); flush()
assert(viewer.closed and not plugin.viewer and not plugin.stopped,
    "KOReader dictionary must not reenter a retired DPD wrapper")
-- The handoff keeps the selection's is_sane, so KOReader cleans it as it would have.
assert(outer_calls == 1 and outer_count == 6 and outer_args[1] == "pacchima"
    and outer_args[2] == false and outer_args[3] == nil and outer_args[4] == reader.highlight
    and outer_args[5] == nil and outer_args[6] == close_callback,
    "KOReader dictionary must preserve the selection and close callback through other plugins")

UIManager:broadcastEvent(Event:new("Suspend")); flush()
assert(not plugin.db and not plugin.lookup and not plugin.stopped)
-- A lookup dialog left open over Suspend still gets suggestions on wake.
local woken, woken_status = plugin:suggest("dham", "pali")
assert(woken_status == "ready" and #woken > 0 and plugin.db, "Suggestions must reopen the database after Suspend")
UIManager:broadcastEvent(Event:new("Suspend")); flush()
reader.dictionary:onLookupWord("pacchima", false, nil, reader.highlight); flush()
assert(plugin.viewer and plugin.db, "Suspend must allow lazy reopening")
reader:onClose(false); flush()
assert(plugin.stopped and not plugin.db and not plugin.lookup and not plugin.viewer)
assert(reader.dictionary.onLookupWord == outer, "Teardown must preserve another plugin's wrapper")
ReaderUI:showReader(book); flush(); flush()
local reopened = assert(ReaderUI.instance).dpd
assert(reopened ~= plugin and not reopened.stopped)
ReaderUI.instance:onClose(false); flush()
print("PASS: FileManager native connection cleanup, popup/owner lifecycles, retained dictionary wrappers, suspend and reader reopening")

local Updater = require("dpd/updater")
for _, unreadable in ipairs({ ".previous", ".update" }) do
    for _, suffix in ipairs({ ".previous", ".update" }) do
        assert(lfs.mkdir(root .. suffix))
        local marker = assert(io.open(root .. suffix .. "/marker", "w"))
        marker:write("disposable obsolete update folder"); marker:close()
    end
    assert(os.execute("chmod 000 " .. q(root .. unreadable)) == 0)
    Updater.cleaned = nil
    local ok, err = pcall(function()
        ReaderUI:showReader(book); flush(); flush()
        local owner = assert(ReaderUI.instance)
        local plugin = assert(owner.dpd, "obsolete cleanup must not reject plugin initialization")
        assert(lfs.attributes(root .. unreadable, "mode") == "directory")
        local other = unreadable == ".previous" and ".update" or ".previous"
        assert(not lfs.attributes(root .. other), "a failed cleanup must not skip the other folder")
        owner.dictionary:onLookupWord("pacchima", true, nil, owner.highlight); flush()
        local viewer, db = assert(plugin.viewer), assert(plugin.db)
        assert(countConnections() == base_connections + 1)
        owner:onClose(false); flush()
        assert(plugin.stopped and viewer.closed and not db.conn and not plugin.db)
        assert(countConnections() == base_connections, "owner close must retire the popup and native connection")
    end)
    assert(os.execute("chmod 755 " .. q(root .. unreadable)) == 0)
    assert(ok, err)
    assert(os.remove(root .. unreadable .. "/marker"))
    assert(lfs.rmdir(root .. unreadable))
end
print("PASS: unreadable obsolete backup/staging folders preserve ReaderUI ownership and normal teardown")
