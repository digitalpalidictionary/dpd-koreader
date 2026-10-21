-- Optional diagnostic log for crash reports from devices. Android KOReader keeps
-- no crash.log, so this appends to <data>/data/dpd/dpd-debug.log and closes the
-- file after every line, keeping the last line when KOReader dies. Off by
-- default; disabled, logging returns at once.
local Diag = { enabled = false, max_bytes = 1000000 }

local sequence = 0

function Diag.path()
    return require("datastorage"):getDataDir() .. "/data/dpd/dpd-debug.log"
end

local function open(path)
    local handle = io.open(path, "a")
    if handle then return handle end
    -- The database may live elsewhere, leaving data/dpd uncreated.
    require("libs/libkoreader-lfs").mkdir(path:match("^(.+)/[^/]+$"))
    return io.open(path, "a")
end

function Diag.log(...)
    if not Diag.enabled then return end
    sequence = sequence + 1
    local parts = { os.date("%Y-%m-%d %H:%M:%S"), "#" .. sequence }
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    pcall(function()
        local path = Diag.path()
        local handle = open(path)
        if not handle then return end
        -- Keep one previous log, so a forgotten setting cannot fill storage.
        if (handle:seek("end") or 0) > Diag.max_bytes then
            handle:close()
            os.remove(path .. ".old")
            os.rename(path, path .. ".old")
            handle = open(path)
            if not handle then return end
        end
        handle:write(table.concat(parts, " "), "\n")
        handle:close()
    end)
end

-- Process memory, available memory and Lua heap, from Linux/Android /proc.
-- With `settled`, collect garbage first (twice, for finalizers), so the Lua
-- heap shows live data instead of garbage the collector hasn't reached yet.
function Diag.memory(settled)
    if settled then collectgarbage("collect"); collectgarbage("collect") end
    local function read(path, pattern)
        local handle = io.open(path, "r")
        if not handle then return "?" end
        local value = tonumber(handle:read("*a"):match(pattern))
        handle:close()
        return value and math.floor(value / 1024) or "?"
    end
    return string.format("rss=%sMB available=%sMB lua=%dKB", read("/proc/self/status", "VmRSS:%s*(%d+)"),
        read("/proc/meminfo", "MemAvailable:%s*(%d+)"), collectgarbage("count"))
end

local function header()
    local parts = { "==== DPD " .. require("dpd/version") }
    pcall(function() parts[#parts + 1] = "KOReader " .. require("version"):getCurrentRevision() end)
    pcall(function()
        local Device = require("device")
        local screen = Device.screen
        parts[#parts + 1] = string.format("device=%s android=%s screen=%dx%d dpi=%s", tostring(Device.model),
            tostring(Device:isAndroid()), screen:getWidth(), screen:getHeight(), tostring(screen:getDPI()))
    end)
    return table.concat(parts, " ")
end

function Diag.setEnabled(enabled)
    Diag.enabled = enabled and true or false
    if Diag.enabled then Diag.log(header()) end
end

-- Production UI boundaries contain failures and always report a traceback to
-- KOReader's logger. Keep the original error/result values, including nils.
-- Optional diagnostic logging and a broken logger must not defeat containment.
function Diag.protect(label, fn, ...)
    return xpcall(fn, function(err)
        local ok, message = pcall(tostring, err)
        local trace = debug.traceback(ok and message or "unprintable error", 2)
        local logger_ok, logger = pcall(require, "logger")
        if logger_ok and type(logger) == "table" and type(logger.warn) == "function" then
            pcall(logger.warn, "DPD " .. label .. ":", trace)
        end
        pcall(Diag.log, "ERROR in " .. label .. ": " .. trace)
        return err
    end, ...)
end

-- The last lines of the log, for viewing on the device.
function Diag.tail(count)
    local handle = io.open(Diag.path(), "r")
    if not handle then return nil end
    local lines = {}
    for line in handle:lines() do
        lines[#lines + 1] = line
        if #lines > count then table.remove(lines, 1) end
    end
    handle:close()
    return table.concat(lines, "\n")
end

return Diag
