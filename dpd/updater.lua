-- Plugin updates from the GitHub releases. A check reads the latest release;
-- an install downloads its zip, checks it against the release's SHA256SUMS
-- and checks every entry, unpacks it beside the plugin folder, then swaps the
-- two folders by renaming. The old folder stays as <plugin>.previous until
-- the new version has started, so a failed install leaves DPD as it was.
-- Updates never touch the database or the settings.
local VERSION = require("dpd/version")

local Updater = {
    api = "https://api.github.com/repos/digitalpalidictionary/dpd-koreader/releases/latest",
    database_api = "https://api.github.com/repos/digitalpalidictionary/dpd-db/releases/latest",
    page = "https://github.com/digitalpalidictionary/dpd-koreader/releases/latest",
    database_page = "https://github.com/digitalpalidictionary/dpd-db/releases/latest",
    -- Release pages and downloads must come from the plugin's own repository,
    -- and database pages from DPD's.
    page_prefix = "https://github.com/digitalpalidictionary/dpd-koreader/releases/",
    database_page_prefix = "https://github.com/digitalpalidictionary/dpd-db/releases/",
    download_prefix = "https://github.com/digitalpalidictionary/dpd-koreader/releases/download/",
    root = "dpd.koplugin",
    max_api_bytes = 1000000,
    max_zip_bytes = 10000000,
    max_entries = 300,
    max_unpacked_bytes = 30000000,
    max_notes = 3000,
    max_redirects = 5,
    -- KOReader's certificate list, relative to its install folder.
    cafile = "data/ca-bundle.crt",
    check_interval = 7 * 24 * 3600,
    retry_interval = 3600,
    -- Replaced by the native check to make a rename fail or stop at a step.
    rename = os.rename,
    on_stage = nil,
    -- The installed version once an update is in place this session. The old
    -- code is still running, so DPD stays off until KOReader restarts.
    restart_pending = nil,
    -- Set when neither the new folder nor the old one could be put in place:
    -- how to restore DPD by hand. DPD stays off; its files are gone.
    broken = nil,
}

--- @return table|nil { major, minor, patch } for "1.2.3" or "v1.2.3"; nil otherwise
function Updater.parseVersion(text)
    local major, minor, patch = tostring(text or ""):match("^v?(%d+)%.(%d+)%.(%d+)$")
    if major then return { tonumber(major), tonumber(minor), tonumber(patch) } end
end

--- Compares numerically, so 0.10.0 is newer than 0.9.9; malformed versions are never newer.
function Updater.isNewer(candidate, installed)
    local new, old = Updater.parseVersion(candidate), Updater.parseVersion(installed)
    if not (new and old) then return false end
    for i = 1, 3 do
        if new[i] ~= old[i] then return new[i] > old[i] end
    end
    return false
end

local function within(url, prefix)
    return type(url) == "string" and url:sub(1, #prefix) == prefix and not url:find("%s")
end

--- Release notes are Markdown written for GitHub: keep the words, drop the
--- markup, and cut a long body at a character boundary.
function Updater.plainNotes(body)
    if type(body) ~= "string" then return nil end
    local text = body:gsub("\r\n?", "\n")
        :gsub("%[([^%]\n]*)%]%([^%)\n]*%)", "%1")
        :gsub("%*%*(.-)%*%*", "%1")
        :gsub("`([^`\n]*)`", "%1")
        :gsub("\n#+[ \t]*", "\n"):gsub("^#+[ \t]*", "")
        :gsub("\n[-*] ", "\n• "):gsub("^[-*] ", "• ")
        :gsub("\n%s*\n[%s\n]*", "\n\n")
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    if #text > Updater.max_notes then
        local cut = Updater.max_notes
        while cut > 0 and text:byte(cut + 1) >= 0x80 and text:byte(cut + 1) < 0xC0 do cut = cut - 1 end
        text = text:sub(1, cut) .. "…"
    end
    return text ~= "" and text or nil
end

--- @param data table the decoded releases/latest response
--- @return table|nil { version, zip_name, zip_url, zip_size, sums_url, page, notes }, or nil and a reason
function Updater.parseRelease(data)
    if type(data) ~= "table" or data.draft == true or data.prerelease == true then
        return nil, "GitHub has no published release"
    end
    local version = type(data.tag_name) == "string" and data.tag_name:match("^v(%d+%.%d+%.%d+)$")
    if not version then return nil, "the latest release has an unexpected name" end
    local release = {
        version = version,
        zip_name = "dpd-koplugin-" .. version .. ".zip",
        page = within(data.html_url, Updater.page_prefix) and data.html_url or Updater.page,
        notes = Updater.plainNotes(data.body),
    }
    for _, asset in ipairs(type(data.assets) == "table" and data.assets or {}) do
        local url = type(asset) == "table" and asset.browser_download_url
        if within(url, Updater.download_prefix) then
            if asset.name == release.zip_name then
                release.zip_url, release.zip_size = url, tonumber(asset.size)
            elseif asset.name == "SHA256SUMS" then
                release.sums_url = url
            end
        end
    end
    return release
end

--- @return string|nil the lowercase SHA-256 listed for `name` in a SHA256SUMS file
function Updater.parseSums(text, name)
    for line in tostring(text or ""):gmatch("[^\r\n]+") do
        local hash, file = line:match("^(%x+)%s+%*?(%S+)%s*$")
        if file == name and #hash == 64 then return hash:lower() end
    end
end

--- Every entry must be a plain file or folder inside dpd.koplugin/: no links,
--- absolute paths, "." or "..", no duplicates (also by case, for FAT storage)
--- and within the limits. The plugin's main files must be there.
--- @param entries table { { path, mode, size } } as ffi/archiver lists them
--- @return table|nil the entries with `rel`, their path inside the plugin folder; or nil and a reason
function Updater.checkEntries(entries)
    if #entries == 0 then return nil, "the zip is empty" end
    if #entries > Updater.max_entries then return nil, "the zip has too many files" end
    local prefix = Updater.root .. "/"
    local result, seen, files, total = {}, {}, {}, 0
    for _, entry in ipairs(entries) do
        local path = entry.path
        if type(path) ~= "string" or path:find("[%z\\]") then return nil, "the zip has an unsafe path" end
        if entry.mode ~= "file" and entry.mode ~= "directory" then
            return nil, "the zip has a link or a special file"
        end
        if (path .. "/"):sub(1, #prefix) ~= prefix then return nil, "the zip has files outside " .. prefix end
        local rel = path:sub(#prefix + 1):gsub("/$", "")
        for part in (rel .. "/"):gmatch("([^/]*)/") do
            if rel ~= "" and (part == "" or part == "." or part == "..") then
                return nil, "the zip has an unsafe path"
            end
        end
        local size = tonumber(entry.size) or -1
        if entry.mode == "file" and (rel == "" or size < 0) then return nil, "the zip has an unsafe path" end
        local key = rel:lower()
        if seen[key] then return nil, "the zip lists a file twice" end
        seen[key] = true
        if entry.mode == "file" then
            total = total + size
            if total > Updater.max_unpacked_bytes then return nil, "the zip unpacks too large" end
            files[rel] = true
        end
        if rel ~= "" then result[#result + 1] = { path = path, rel = rel, mode = entry.mode, size = size } end
    end
    for _, required in ipairs({ "main.lua", "_meta.lua", "dpd/version.lua" }) do
        if not files[required] then return nil, "the zip has no " .. required end
    end
    return result
end

-- Network ----------------------------------------------------------------

local function reason(code)
    if code == 403 or code == 429 then return "GitHub is limiting requests; try again in an hour" end
    if code == 404 then return "GitHub didn't find the release" end
    if type(code) == "number" then return "GitHub answered " .. code end
    if code == "too large" then return "the download was larger than expected" end
    if code == "timeout" or code == "sink timeout" or code == "wantread" then return "the connection timed out" end
    if code == "an insecure redirect" then return "GitHub sent the download to an unencrypted address" end
    if code == "too many redirects" then return "GitHub redirected too many times" end
    if tostring(code):find("certificate", 1, true) or tostring(code):find("CA locations", 1, true) then
        return "the connection to GitHub couldn't be verified (" .. tostring(code) .. ")"
    end
    return "no connection (" .. tostring(code) .. ")"
end

--- @param names table the certificate's DNS names; "*." covers exactly one label
function Updater.hostMatches(names, host)
    host = tostring(host or ""):lower()
    for _, name in ipairs(type(names) == "table" and names or {}) do
        name = tostring(name):lower()
        if name == host then return true end
        local suffix = name:match("^%*(%.[^*]+%.[^*]+)$")
        local label = suffix and #host > #suffix and host:sub(-#suffix) == suffix and host:sub(1, -#suffix - 1)
        if label and not label:find(".", 1, true) then return true end
    end
    return false
end

-- KOReader's LuaSec checks no certificate unless asked, and never the host
-- name. Check the chain against KOReader's certificate list and the name here.
local function verifiedConnection()
    local socket = require("socket")
    local make = require("ssl.https").tcp({ verify = "peer", cafile = Updater.cafile })
    return function()
        local conn = make()
        local connect = conn.connect
        function conn:connect(host, port)
            connect(self, host, port)
            local certificate = self.sock:getpeercertificate()
            local extensions = certificate and certificate:extensions()
            local names = extensions and extensions["2.5.29.17"]
            if not Updater.hostMatches(names and names.dNSName, host) then
                socket.try(nil, "certificate not valid for " .. host)
            end
            return 1
        end
        return conn
    end
end

-- Wraps a sink so a response larger than `limit` stops the transfer.
local function limited(sink, limit)
    local bytes = 0
    return function(chunk, err)
        if chunk then
            bytes = bytes + #chunk
            if bytes > limit then return nil, "too large" end
        end
        return sink(chunk, err)
    end
end

local function get(url, accept, sink)
    local socket = require("socket")
    return socket.skip(1, require("socket.http").request{
        url = url,
        method = "GET",
        sink = sink,
        -- Redirects are followed in `request`: LuaSocket's own drop the
        -- certificate checks.
        redirect = false,
        create = url:match("^https:") and verifiedConnection() or nil,
        headers = { ["user-agent"] = "DPD-KOReader/" .. VERSION, accept = accept },
    })
end

-- `make_sink` runs once per redirect, after the timeouts are set (socketutil's
-- sinks read them), and must start the body afresh: a redirect's own body and
-- end reach its sink, and a file sink closes its file at the end.
local function request(url, accept, make_sink, timeouts)
    -- Through KOReader's proxy setting, LuaSocket would check the proxy's
    -- certificate, not GitHub's, and send the request to the proxy unencrypted.
    if require("socket.http").PROXY then
        return nil, "DPD can't update through the proxy in KOReader's network settings; "
            .. "turn it off for the update"
    end
    local socketutil = require("socketutil")
    socketutil:set_timeout(timeouts[1], timeouts[2])
    local ok, code, headers
    for _ = 0, Updater.max_redirects do
        ok, code, headers = pcall(get, url, accept, make_sink(socketutil))
        local location = ok and type(code) == "number" and code >= 300 and code < 400
            and type(headers) == "table" and headers.location
        if not location then break end
        local target = require("socket.url").absolute(url, location)
        if url:match("^https:") and not target:match("^https:") then code = "an insecure redirect"; break end
        url, code = target, "too many redirects"
    end
    socketutil:reset_timeout()
    if not ok then return nil, reason(tostring(code)) end
    if code ~= 200 then return nil, reason(code) end
    return true
end

local function fetchText(url, limit, accept, timeouts)
    local chunks
    local ok, err = request(url, accept, function(socketutil)
        chunks = {}
        return limited(socketutil.table_sink(chunks), limit)
    end, timeouts or { 10, 30 })
    if not ok then return nil, err end
    return table.concat(chunks)
end

local function fetchJSON(url, timeouts)
    local body, err = fetchText(url, Updater.max_api_bytes, "application/vnd.github+json", timeouts)
    if not body then return nil, err end
    local ok, data = pcall(require("json").decode, body)
    if not ok or type(data) ~= "table" then return nil, "GitHub's answer couldn't be read" end
    return data
end

--- @param quick boolean shorter timeouts, for the background check
--- @return table|nil the latest release (see parseRelease), or nil and a reason
function Updater.check(quick)
    local data, err = fetchJSON(Updater.api, quick and { 5, 10 } or nil)
    if not data then return nil, err end
    return Updater.parseRelease(data)
end

--- The background check: runs a quick check in a child process, so a slow
--- network never holds up reading, and calls `on_done(version)` on the UI
--- loop, with nil if the check failed. A child still running after a minute
--- is stopped.
--- @return boolean false when no child process could be started
function Updater.checkInBackground(on_done)
    local ffiutil = require("ffi/util")
    local UIManager = require("ui/uimanager")
    local pid, fd = ffiutil.runInSubProcess(function(_, write_fd)
        local release = Updater.check(true)
        ffiutil.writeToFD(write_fd, release and release.version or "", true)
    end, true)
    if not pid then return false end
    -- KOReader's monotonic clock: the device may set its clock right after
    -- Wi-Fi comes up, and a jump back would keep a hung child alive.
    local time = require("ui/time")
    local started = time.now()
    local function poll()
        local done = ffiutil.isSubProcessDone(pid)
        if not done and time.since(started) > time.s(60) then
            ffiutil.terminateSubProcess(pid)
            done = ffiutil.isSubProcessDone(pid, true)
        end
        if not done then return UIManager:scheduleIn(1, poll) end
        local version = ffiutil.readAllFromFD(fd)
        on_done(Updater.parseVersion(version) and version or nil)
    end
    UIManager:scheduleIn(1, poll)
    return true
end

--- @param data table the decoded releases/latest response of DPD's database
--- @return table|nil { tag = "v0.4.20260926", page }, or nil and a reason
function Updater.parseDatabaseRelease(data)
    local tag = type(data) == "table" and data.tag_name
    if type(tag) ~= "string" or not Updater.parseVersion(tag) then
        return nil, "the latest database release has an unexpected name"
    end
    return { tag = tag,
        page = within(data.html_url, Updater.database_page_prefix) and data.html_url or Updater.database_page }
end

--- @return table|nil the latest DPD database release (see parseDatabaseRelease), or nil and a reason
function Updater.latestDatabase()
    local data, err = fetchJSON(Updater.database_api)
    if not data then return nil, err end
    return Updater.parseDatabaseRelease(data)
end

-- Install ----------------------------------------------------------------

local function stage(name)
    if Updater.on_stage then Updater.on_stage(name) end
end

-- Deletes a folder tree without following links: KOReader's purgeDir would
-- empty whatever a link inside the plugin folder points to.
local function purge(path)
    local lfs = require("libs/libkoreader-lfs")
    local mode = lfs.symlinkattributes(path, "mode")
    if mode == nil then return true end
    if mode == "directory" then
        for name in lfs.dir(path) do
            if name ~= "." and name ~= ".." then
                local ok, err = purge(path .. "/" .. name)
                if not ok then return nil, err end
            end
        end
    end
    return os.remove(path)
end

-- Flush renames and new files to the card before reporting success.
local function sync()
    pcall(os.execute, "sync")
end

local function download(url, path)
    local handle = io.open(path, "wb")
    if not handle then return nil, "DPD couldn't save the download in " .. path end
    local ok, err = request(url, nil, function(socketutil)
        pcall(handle.close, handle)
        handle = io.open(path, "wb")
        return limited(socketutil.file_sink(handle), Updater.max_zip_bytes)
    end, { 15, 120 })
    pcall(handle.close, handle)
    return ok, err
end

local function fileSha256(path)
    local handle = io.open(path, "rb")
    if not handle then return nil end
    local hash = require("ffi/sha2").sha256()
    while true do
        local chunk = handle:read(65536)
        if not chunk then break end
        hash(chunk)
    end
    handle:close()
    return hash()
end

local function listEntries(zip)
    local reader = require("ffi/archiver").Reader:new()
    if not reader:open(zip) then return nil, "the zip couldn't be opened" end
    local entries = {}
    for entry in reader:iterate() do
        entries[#entries + 1] = { path = entry.path, mode = entry.mode, size = tonumber(entry.size) }
        -- checkEntries rejects it; stop reading a hostile archive.
        if #entries > Updater.max_entries then break end
    end
    local err = reader.err
    reader:close()
    if err then return nil, "the zip is damaged" end
    return entries
end

local function unpack(zip, entries, staging)
    local lfs = require("libs/libkoreader-lfs")
    local reader = require("ffi/archiver").Reader:new()
    if not reader:open(zip) then return nil, "the zip couldn't be opened" end
    local wanted = {}
    for _, entry in ipairs(entries) do wanted[entry.path] = entry end
    local ok = true
    for entry in reader:iterate() do
        local item = wanted[entry.path]
        if item and not reader:extractToPath(entry.path, staging .. "/" .. item.rel) then ok = false; break end
    end
    reader:close()
    if not ok then return nil, "unpacking failed; the card may be full" end
    -- A full card or a FAT write error can leave missing or short files.
    for _, entry in ipairs(entries) do
        local attributes = lfs.attributes(staging .. "/" .. entry.rel)
        if not attributes or attributes.mode ~= entry.mode
            or (entry.mode == "file" and attributes.size ~= entry.size) then
            return nil, "unpacking was incomplete; the card may be full"
        end
    end
    return true
end

local function stagedVersion(staging)
    local handle = io.open(staging .. "/dpd/version.lua", "r")
    if not handle then return nil end
    local text = handle:read("*a")
    handle:close()
    return text:match('^return "(%d+%.%d+%.%d+)"%s*$')
end

-- The running plugin's folder, refusing a link or a development checkout:
-- renaming one would move the developer's own working copy.
local function pluginFolder(plugin_dir)
    local lfs = require("libs/libkoreader-lfs")
    if not plugin_dir or lfs.symlinkattributes(plugin_dir, "mode") ~= "directory" then
        return nil, "DPD's folder wasn't found or is a link; update it by hand"
    end
    local dir = require("ffi/util").realpath(plugin_dir)
    if not dir or lfs.attributes(dir .. "/.git") then
        return nil, "this DPD folder is a development copy; update it by hand"
    end
    return dir
end

local function prepare(release, dir, work_dir, run_download)
    if not (within(release.zip_url, Updater.download_prefix) and within(release.sums_url, Updater.download_prefix)) then
        return nil, "the release has no plugin zip"
    end
    if release.zip_size and release.zip_size > Updater.max_zip_bytes then
        return nil, "the release zip is larger than expected"
    end
    local lfs = require("libs/libkoreader-lfs")
    lfs.mkdir(work_dir)
    local zip = work_dir .. "/dpd-update.zip"
    os.remove(zip)
    local function fetch()
        local sums, err = fetchText(release.sums_url, 10000)
        if not sums then return nil, err end
        local expected = Updater.parseSums(sums, release.zip_name)
        if not expected then return nil, "the release's SHA256SUMS doesn't list " .. release.zip_name end
        local ok
        ok, err = download(release.zip_url, zip)
        return ok and expected or nil, err
    end
    local expected, err
    if run_download then expected, err = run_download(fetch)
    else expected, err = fetch() end
    local ok = expected ~= nil
    if ok and release.zip_size and lfs.attributes(zip, "size") ~= release.zip_size then
        ok, err = nil, "the download was incomplete"
    end
    if ok and fileSha256(zip) ~= expected then ok, err = nil, "the download didn't match its checksum" end
    if not ok then os.remove(zip); return nil, err end
    stage("downloaded")
    local entries
    entries, err = listEntries(zip)
    if entries then entries, err = Updater.checkEntries(entries) end
    if not entries then os.remove(zip); return nil, err end
    local staging = dir .. ".update"
    purge(staging)
    if not lfs.mkdir(staging) then
        os.remove(zip)
        return nil, "DPD's plugins folder isn't writable"
    end
    ok, err = unpack(zip, entries, staging)
    os.remove(zip)
    if ok and stagedVersion(staging) ~= release.version then ok, err = nil, "the zip holds a different version" end
    if not ok then purge(staging); return nil, err end
    sync()
    stage("unpacked")
    return staging
end

--- Downloads, checks and unpacks `release`, then puts it in place of the
--- running plugin. Blocks while it works.
--- @param plugin_dir string the running plugin's folder (the plugin's `path`)
--- @param work_dir string a writable folder for the download
--- @param database string|nil the database path: refused inside the plugin
---   folder, which the next start deletes with the old version
--- @param run_download function|nil runs the download task; UI callers use a cancellable child
--- @return boolean|nil true when installed; else nil, a reason and, only when
---   the old folder couldn't be put back either, true
function Updater.install(release, plugin_dir, work_dir, database, run_download)
    if Updater.broken then return nil, Updater.broken end
    if Updater.restart_pending then return nil, "restart KOReader to finish the last update" end
    if Updater.installing then return nil, "an update is already being installed" end
    local dir, err = pluginFolder(plugin_dir)
    if not dir then return nil, err end
    if database then
        -- Both the file and its name: a link inside the folder would vanish too.
        local realpath = require("ffi/util").realpath
        local parent, name = database:match("^(.*)/([^/]+)$")
        local named = parent and realpath(parent ~= "" and parent or "/")
        local inside = function(path) return path and path:sub(1, #dir + 1) == dir .. "/" end
        if inside(realpath(database)) or inside(named and (named .. "/" .. name)) then
            return nil, "the database is inside DPD's folder. Move dpd-mobile.db to koreader/data/dpd/ "
                .. "and choose it again under Database → Choose database file first"
        end
    end
    -- The next start after an update deletes the backup, so one left now
    -- means this version didn't start properly: keep the copy that did.
    if require("libs/libkoreader-lfs").symlinkattributes(dir .. ".previous", "mode") then
        return nil, "the previous version is still kept in " .. dir .. ".previous. Restart KOReader, "
            .. "or delete that folder if DPD works"
    end
    Updater.installing = true
    local ok, staging
    ok, staging, err = pcall(prepare, release, dir, work_dir, run_download)
    if not ok then staging, err = nil, "unexpected error: " .. tostring(staging) end
    if not staging then
        Updater.installing = nil
        return nil, err
    end
    local backup = dir .. ".previous"
    if not Updater.rename(dir, backup) then
        purge(staging)
        Updater.installing = nil
        return nil, "DPD's folder couldn't be renamed"
    end
    stage("moved")
    if not Updater.rename(staging, dir) then
        local restored = Updater.rename(backup, dir)
        if restored then purge(staging) end
        sync()
        Updater.installing = nil
        if restored then return nil, "the new folder couldn't be put in place" end
        Updater.broken = "the new folder couldn't be put in place, and the old one couldn't be put back. "
            .. "To restore plugin " .. VERSION .. ", rename\n" .. backup .. "\nto\n" .. dir .. "\nand restart KOReader"
        return nil, Updater.broken, true
    end
    sync()
    Updater.installing = nil
    Updater.restart_pending = release.version
    stage("installed")
    return true
end

--- Runs once a session after the plugin has started: an update before this
--- start worked, so its backup and any half-unpacked folder can go.
function Updater.cleanUp(plugin_dir)
    if Updater.cleaned or Updater.restart_pending or not plugin_dir then return end
    Updater.cleaned = true
    local dir = pluginFolder(plugin_dir)
    if not dir then return end
    -- Obsolete files must not turn a successful startup into partial initialization.
    for _, suffix in ipairs({ ".previous", ".update" }) do
        local path = dir .. suffix
        local ok, removed, err = pcall(purge, path)
        if not ok or not removed then
            require("logger").warn("DPD update cleanup:", path, ok and err or removed)
        end
    end
end

return Updater
