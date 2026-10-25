-- Run from a disposable desktop KOReader runtime with a disposable profile:
-- SDL_VIDEODRIVER=dummy KO_MULTIUSER=1 XDG_CONFIG_HOME=<temporary directory> \
-- ./luajit <plugin>/tools/check_updater.lua <plugin> [dpd-mobile.db] [screenshots]
-- The updater against a local server holding fake releases: up to date, a
-- good install, every rejected zip, failed renames, a crash at each step and
-- what KOReader's plugin loader finds afterwards, and the menu, dialogs and
-- background check through main.lua. Needs python3; never contacts GitHub.
require("setupkoenv")
local root = assert(arg[1], "plugin directory required")
package.path = root .. "/?.lua;" .. package.path
G_defaults = require("luadefaults"):open()
G_reader_settings = require("luasettings"):wrap({})
local lfs = require("libs/libkoreader-lfs")

local function sh(command) assert(os.execute(command) == 0, command) end
local function q(path) return "'" .. path:gsub("'", "'\\''") .. "'" end
local function read(path)
    local handle = io.open(path, "rb")
    if not handle then return nil end
    local text = handle:read("*a")
    handle:close()
    return text
end
local function write(path, text)
    local handle = assert(io.open(path, "w"))
    handle:write(text)
    handle:close()
end
local function exists(path) return lfs.attributes(path, "mode") ~= nil end
local function versionOf(dir) return (read(dir .. "/dpd/version.lua") or ""):match('"(.-)"') end

local Updater = require("dpd/updater")
local function configure(base)
    Updater.api = base .. "/api/good"
    Updater.database_api = base .. "/db"
    -- Release pages stay the real ones, so a screenshot's QR code scans.
    Updater.download_prefix = base .. "/download/"
end

-- Child processes: one install stopped at a step, or KOReader's plugin loader.
if arg[2] == "--crash" then
    local step, dir, base, downloads = arg[3], arg[4], arg[5], arg[6]
    configure(base)
    Updater.on_stage = function(name) if name == step then os.exit(3) end end
    Updater.install(assert(Updater.check()), dir, downloads)
    os.exit(0)
elseif arg[2] == "--load" then
    require("document/canvascontext"):init(require("device"))
    G_reader_settings:saveSetting("extra_plugin_paths", { arg[3] })
    local enabled = require("pluginloader"):loadPlugins()
    for _, plugin in ipairs(enabled) do
        if plugin.name == "dpd" then print("LOADED " .. plugin.path) end
    end
    os.exit(0)
end

local db_path, screenshots = arg[2] ~= "" and arg[2] or nil, arg[3]
local VERSION = versionOf(root)
local work = os.getenv("DPD_UPDATE_TMP") or os.tmpname()
os.remove(work)
sh("mkdir -p " .. q(work .. "/plugins") .. " " .. q(work .. "/www") .. " " .. q(work .. "/work"))
local plugins, dir = work .. "/plugins", work .. "/plugins/dpd.koplugin"

-- HTTPS fixtures need a test certificate authority, a certificate for
-- localhost and one for another name; without openssl they are skipped.
local certs = work .. "/certs"
local tls = os.execute("command -v openssl >/dev/null 2>&1") == 0
if tls then
    sh("mkdir -p " .. q(certs))
    local function openssl(args) sh("cd " .. q(certs) .. " && openssl " .. args .. " >/dev/null 2>&1") end
    openssl('req -x509 -newkey rsa:2048 -nodes -keyout ca.key -out ca.crt -days 2 -subj "/CN=DPD test CA" '
        .. '-addext "basicConstraints=critical,CA:TRUE" -addext "keyUsage=critical,keyCertSign"')
    for name, host in pairs({ good = "localhost", wrong = "other.invalid" }) do
        write(certs .. "/" .. name .. ".ext", "subjectAltName=DNS:" .. host .. "\nbasicConstraints=CA:FALSE\n")
        openssl("req -newkey rsa:2048 -nodes -keyout " .. name .. ".key -out " .. name .. ".csr -subj /CN=" .. host)
        openssl("x509 -req -in " .. name .. ".csr -CA ca.crt -CAkey ca.key -CAcreateserial -out " .. name
            .. ".crt -days 2 -extfile " .. name .. ".ext")
    end
end

-- The fixture servers: plain HTTP, HTTPS for localhost and HTTPS with the
-- wrong name. /api/<case> is the case's release JSON; /download/ redirects to
-- /files/ like GitHub's asset links, with a body the sink must never see; the
-- other /download-*/ routes redirect to the wrong name, to plain HTTP or in
-- a loop. Every request is logged.
local server = work .. "/server.py"
write(server, [=[
import http.server, os, ssl, sys, threading, time
root, port_file, log_file, certs = sys.argv[1:5]
root = os.path.realpath(root)
ports = {}
class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args): pass
    def redirect(self, location):
        body = b"redirecting " * 500
        self.send_response(302)
        self.send_header("Location", location)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def do_GET(self):
        with open(log_file, "a") as log:
            log.write(self.path + "\t" + self.headers.get("User-Agent", "") + "\n")
        parts = self.path.strip("/").split("/")
        rest = "/".join(parts[1:])
        if parts[0] == "download": return self.redirect("/files/" + rest)
        if parts[0] == "download-wrong": return self.redirect("https://localhost:%d/files/%s" % (ports["wrong"], rest))
        if parts[0] == "download-plain": return self.redirect("http://127.0.0.1:%d/files/%s" % (ports["http"], rest))
        if parts[0] == "download-loop": return self.redirect("/download-loop/" + rest)
        if parts[0] == "download-stall":
            time.sleep(8)
            return self.redirect("/files/" + rest)
        if parts[:2] == ["api", "headers"]:
            self.wfile.write(b"HTTP/1.1 200 OK\r\n")
            for i in range(50):
                self.wfile.write(("X-Delay-%d: test\r\n" % i).encode())
                self.wfile.flush()
                time.sleep(0.2)
            self.wfile.write(b"Content-Length: 2\r\n\r\n{}")
            return
        if parts[:2] == ["api", "stall"]:
            time.sleep(8)
            parts = ["api", "good"]
        path = None
        if parts[0] == "files": path = os.path.join(root, *parts[1:])
        elif parts[0] == "api" and len(parts) > 1: path = os.path.join(root, parts[1], "release.json")
        elif parts[0].startswith("db"): path = os.path.join(root, parts[0] + ".json")
        # Check the resolved path so neither traversal nor symlinks escape root.
        if path: path = os.path.realpath(path)
        if not path or os.path.commonpath((root, path)) != root or not os.path.isfile(path):
            self.send_response(404); self.end_headers(); return
        with open(path, "rb") as source:
            data = source.read()
        self.send_response(200)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)
def serve(name, cert=None):
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    if cert:
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(os.path.join(certs, cert + ".crt"), os.path.join(certs, cert + ".key"))
        server.socket = context.wrap_socket(server.socket, server_side=True)
    ports[name] = server.server_address[1]
    threading.Thread(target=server.serve_forever, daemon=True).start()
serve("http")
if os.path.isfile(os.path.join(certs, "good.crt")):
    serve("https", "good")
    serve("wrong", "wrong")
open(port_file + ".tmp", "w").write(" ".join(str(ports.get(n, 0)) for n in ("http", "https", "wrong")))
os.rename(port_file + ".tmp", port_file)
threading.Event().wait()
]=])

-- The fake releases, built from this checkout's runtime files.
local fixtures = work .. "/fixtures.py"
write(fixtures, [=[
import hashlib, json, os, pathlib, sys, zipfile
root, www, base, current = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]), sys.argv[3], sys.argv[4]
runtime = [root / "_meta.lua", root / "main.lua"] + sorted((root / "dpd").glob("*.lua")) + sorted((root / "ui").glob("*.lua"))
def put(archive, name, data, mode=0o100644):
    info = zipfile.ZipInfo(name, (1980, 1, 1, 0, 0, 0))
    info.compress_type = zipfile.ZIP_DEFLATED
    info.external_attr = mode << 16
    archive.writestr(info, data)
def build(case, tag="99.0.0", inside=None, prefix="dpd.koplugin/", extra=(), sums=None, size_delta=0,
          assets=True, damage=False):
    folder = www / case
    folder.mkdir(parents=True)
    name = f"dpd-koplugin-{tag}.zip"
    with zipfile.ZipFile(folder / name, "w") as archive:
        for file in runtime:
            rel = file.relative_to(root).as_posix()
            data = file.read_bytes()
            if rel == "dpd/version.lua":
                data = f'return "{inside or tag}"\n'.encode()
            put(archive, prefix + rel, data)
        for entry in extra:
            put(archive, *entry)
    data = (folder / name).read_bytes()
    if damage:
        middle = len(data) // 2
        data = data[:middle] + bytes(b ^ 0xFF for b in data[middle:middle + 64]) + data[middle + 64:]
        (folder / name).write_bytes(data)
    digest = sums or hashlib.sha256(data).hexdigest()
    (folder / "SHA256SUMS").write_text(f"{digest}  {name}\n")
    download = f"{base}/download/{case}/"
    release = {"tag_name": "v" + tag, "html_url": "https://github.com/digitalpalidictionary/dpd-koreader/releases/latest",
               "body": "## What's new\n\n- **Fixture** release for [the check](https://example.com).",
               "assets": [{"name": name, "size": len(data) + size_delta, "browser_download_url": download + name},
                          {"name": "SHA256SUMS", "size": 89, "browser_download_url": download + "SHA256SUMS"}]
                         if assets else []}
    (folder / "release.json").write_text(json.dumps(release))
build("good")
build("uptodate", tag=current)
build("badhash", sums="0" * 64)
build("truncated", size_delta=10)
build("link", extra=[("dpd.koplugin/evil", "/etc/passwd", 0o120777)])
build("traversal", extra=[("dpd.koplugin/../evil.lua", "x")])
build("root", prefix="other.koplugin/")
build("mismatch", inside="98.0.0")
build("damaged", damage=True)
build("nozip", assets=False)
(www / "db.json").write_text(json.dumps({"tag_name": "v0.4.29990101",
                                         "html_url": "https://github.com/digitalpalidictionary/dpd-db/releases/latest"}))
]=])

local port_file, log_file = work .. "/port", work .. "/requests.log"
sh("python3 " .. q(server) .. " " .. q(work .. "/www") .. " " .. q(port_file) .. " " .. q(log_file) .. " "
    .. q(certs) .. " >/dev/null 2>&1 & echo $! > " .. q(work .. "/server.pid"))
local function stopServer() os.execute("kill $(cat " .. q(work .. "/server.pid") .. ") 2>/dev/null") end
local ok, failure = xpcall(function()
for _ = 1, 100 do
    if exists(port_file) then break end
    require("ffi/util").usleep(50000)
end
local http_port, https_port = assert(read(port_file), "fixture server didn't start"):match("^(%d+) (%d+)")
local base = "http://127.0.0.1:" .. http_port
sh("python3 " .. q(fixtures) .. " " .. q(root) .. " " .. q(work .. "/www") .. " " .. q(base) .. " " .. q(VERSION))
configure(base)

local function fresh()
    sh("rm -rf " .. q(dir) .. " " .. q(dir .. ".previous") .. " " .. q(dir .. ".update") .. " " .. q(work .. "/work"))
    sh("mkdir -p " .. q(dir) .. " " .. q(work .. "/work") .. " && cp " .. q(root .. "/main.lua") .. " "
        .. q(root .. "/_meta.lua") .. " " .. q(dir) .. " && cp -R " .. q(root .. "/dpd") .. " " .. q(root .. "/ui")
        .. " " .. q(dir))
    Updater.restart_pending, Updater.cleaned, Updater.installing, Updater.broken = nil, nil, nil, nil
end
local function release(case)
    Updater.api = base .. "/api/" .. case
    return assert(Updater.check())
end
local function untouched(label)
    assert(versionOf(dir) == VERSION, label .. ": the running plugin changed")
    assert(not exists(dir .. ".update") and not exists(dir .. ".previous"), label .. ": left a folder behind")
    assert(not exists(work .. "/work/dpd-update.zip"), label .. ": left the download behind")
end
local function loaded()
    local handle = io.popen("./luajit " .. q(root .. "/tools/check_updater.lua") .. " " .. q(root) .. " --load "
        .. q(plugins) .. " 2>/dev/null")
    local output = handle:read("*a")
    handle:close()
    return output:match("LOADED ([^\n]+)")
end

-- Up to date, and the newer database.
local current = release("uptodate")
assert(current.version == VERSION and not Updater.isNewer(current.version, VERSION))
local database = assert(Updater.latestDatabase())
local DATABASE_PAGE = "https://github.com/digitalpalidictionary/dpd-db/releases/latest"
local PLUGIN_PAGE = "https://github.com/digitalpalidictionary/dpd-koreader/releases/latest"
assert(database.tag == "v0.4.29990101" and database.page == DATABASE_PAGE)
local agents = read(log_file)
assert(agents:find("\tDPD%-KOReader/" .. VERSION:gsub("%.", "%%.")) and not agents:find("KOReader/v"),
    "requests name DPD and its version only")

-- A good install swaps the folders, then the next start removes the backup.
fresh()
local good = release("good")
assert(good.version == "99.0.0" and good.notes:find("Fixture release for the check", 1, true))
assert(Updater.install(good, dir, work .. "/work"))
assert(versionOf(dir) == "99.0.0" and versionOf(dir .. ".previous") == VERSION and not exists(dir .. ".update"))
assert(not exists(work .. "/work/dpd-update.zip"))
assert(Updater.restart_pending == "99.0.0")
local again, again_err = Updater.install(good, dir, work .. "/work")
assert(not again and again_err:find("restart KOReader", 1, true))
Updater.cleanUp(dir)
assert(exists(dir .. ".previous"), "no clean-up before the restart")
Updater.restart_pending, Updater.cleaned = nil, nil
Updater.cleanUp(dir)
assert(not exists(dir .. ".previous") and versionOf(dir) == "99.0.0")
assert(loaded() == plugins .. "/dpd.koplugin", "KOReader loads the installed update")
print("PASS install")

-- Every rejected release leaves the plugin as it was.
local rejected = {
    badhash = "checksum", truncated = "incomplete", link = "link", traversal = "unsafe",
    root = "outside", mismatch = "different version", damaged = "unpacking", nozip = "no plugin zip",
}
for case, expected in pairs(rejected) do
    fresh()
    local done, err = Updater.install(release(case), dir, work .. "/work")
    assert(not done and err:find(expected, 1, true), case .. ": " .. tostring(err))
    untouched(case)
    print("PASS rejects " .. case .. ": " .. err)
end
fresh()
Updater.max_zip_bytes = 1000
local done, err = Updater.install(release("good"), dir, work .. "/work")
Updater.max_zip_bytes = 10000000
assert(not done and err:find("larger", 1, true), tostring(err))
untouched("oversized")
print("PASS rejects an oversized zip: " .. err)
local saved_size = Updater.max_zip_bytes
Updater.max_zip_bytes = 1000
local sized = release("good")
sized.zip_size = nil
done, err = Updater.install(sized, dir, work .. "/work")
Updater.max_zip_bytes = saved_size
assert(not done and err:find("larger than expected", 1, true), tostring(err))
untouched("streamed oversize")
print("PASS stops a download past the limit: " .. err)

-- Failed renames put the old folder back.
for _, failing in ipairs({ "aside", "into place" }) do
    fresh()
    Updater.rename = function(from, to)
        if (failing == "aside" and to:match("%.previous$")) or (failing == "into place" and from:match("%.update$")) then
            return nil, "injected"
        end
        return os.rename(from, to)
    end
    done, err = Updater.install(release("good"), dir, work .. "/work")
    Updater.rename = os.rename
    assert(not done and err:find("couldn't be", 1, true), tostring(err))
    untouched("rename " .. failing)
    print("PASS restores after a failed rename " .. failing .. ": " .. err)
end
fresh()
Updater.rename = function(from, to)
    if from:match("%.update$") or from:match("%.previous$") then return nil, "injected" end
    return os.rename(from, to)
end
local broken
done, err, broken = Updater.install(release("good"), dir, work .. "/work")
Updater.rename = os.rename
local real = require("ffi/util").realpath(plugins) .. "/dpd.koplugin"
assert(not done and broken and err:find("To restore plugin " .. VERSION .. ", rename\n"
    .. real .. ".previous\nto\n" .. real .. "\nand restart KOReader", 1, true), tostring(err))
print("PASS explains a restore that also failed")

-- Development copies and links are never moved.
fresh()
sh("mkdir " .. q(dir .. "/.git"))
done, err = Updater.install(release("good"), dir, work .. "/work")
assert(not done and err:find("development copy", 1, true))
fresh()
sh("mv " .. q(dir) .. " " .. q(work .. "/elsewhere") .. " && ln -s " .. q(work .. "/elsewhere") .. " " .. q(dir))
done, err = Updater.install(release("good"), dir, work .. "/work")
assert(not done and err:find("link", 1, true))
sh("rm -f " .. q(dir) .. " && rm -rf " .. q(work .. "/elsewhere"))
print("PASS refuses development copies and links")

-- Clean-up never follows links, inside the old folder or as the backup itself.
local outside = work .. "/outside"
local function outsideIntact() return read(outside .. "/keep.txt") == "keep" end
sh("rm -rf " .. q(outside) .. " && mkdir -p " .. q(outside))
write(outside .. "/keep.txt", "keep")
fresh()
sh("ln -s " .. q(outside) .. " " .. q(dir .. "/linked"))
assert(Updater.install(release("good"), dir, work .. "/work"))
Updater.restart_pending, Updater.cleaned = nil, nil
Updater.cleanUp(dir)
assert(not exists(dir .. ".previous") and outsideIntact(), "a link in the old folder")
fresh()
sh("ln -s " .. q(outside) .. " " .. q(dir .. ".previous"))
done, err = Updater.install(release("good"), dir, work .. "/work")
assert(not done and err:find("previous version is still kept", 1, true), tostring(err))
Updater.cleanUp(dir)
assert(lfs.symlinkattributes(dir .. ".previous", "mode") == nil and outsideIntact(), "a linked backup")
print("PASS clean-up leaves linked folders alone")

-- A backup left by a version that didn't start properly is kept.
fresh()
sh("cp -R " .. q(dir) .. " " .. q(dir .. ".previous"))
done, err = Updater.install(release("good"), dir, work .. "/work")
assert(not done and err:find("previous version is still kept", 1, true), tostring(err))
assert(versionOf(dir .. ".previous") == VERSION and not exists(dir .. ".update"))
print("PASS keeps an earlier backup")

-- A database inside the plugin folder would go with the old version.
fresh()
write(dir .. "/dpd-mobile.db", "db")
done, err = Updater.install(release("good"), dir, work .. "/work", dir .. "/dpd-mobile.db")
assert(not done and err:find("database is inside DPD's folder", 1, true), tostring(err))
os.remove(dir .. "/dpd-mobile.db")
untouched("database inside")
print("PASS refuses a database inside the plugin folder")

-- A crash at each step: what KOReader loads next, and what the next start removes.
for _, step in ipairs({ "downloaded", "unpacked", "moved", "installed" }) do
    fresh()
    local status = os.execute("./luajit " .. q(root .. "/tools/check_updater.lua") .. " " .. q(root) .. " --crash "
        .. step .. " " .. q(dir) .. " " .. q(base) .. " " .. q(work .. "/work") .. " >/dev/null 2>&1")
    assert(status == 3 * 256 or status == 3, step .. ": the child didn't stop at the step")
    local path = loaded()
    if step == "moved" then
        -- The one window with no plugin: the README explains the rename back.
        assert(not path and not exists(dir) and versionOf(dir .. ".previous") == VERSION
            and versionOf(dir .. ".update") == "99.0.0")
    else
        assert(path == plugins .. "/dpd.koplugin", step .. ": KOReader didn't load DPD")
        Updater.restart_pending, Updater.cleaned = nil, nil
        Updater.cleanUp(dir)
        assert(not exists(dir .. ".previous") and not exists(dir .. ".update"), step .. ": clean-up")
        assert(versionOf(dir) == (step == "installed" and "99.0.0" or VERSION), step)
    end
    print("PASS crash after " .. step)
end

-- Nothing listening.
Updater.api = "http://127.0.0.1:9/api/good"
local none, none_err = Updater.check()
assert(not none and none_err:find("no connection", 1, true), tostring(none_err))
print("PASS reports no connection: " .. none_err)

-- KOReader's proxy setting would put the proxy's certificate in GitHub's place.
local http = require("socket.http")
http.PROXY = "http://127.0.0.1:9"
Updater.api = base .. "/api/good"
none, none_err = Updater.check()
http.PROXY = nil
assert(not none and none_err:find("proxy", 1, true), tostring(none_err))
print("PASS refuses a proxy")

-- A database reached through a link inside the plugin folder.
fresh()
write(work .. "/outside/dpd-mobile.db", "db")
sh("ln -s " .. q(work .. "/outside/dpd-mobile.db") .. " " .. q(dir .. "/dpd-mobile.db"))
done, err = Updater.install(release("good"), dir, work .. "/work", dir .. "/dpd-mobile.db")
assert(not done and err:find("database is inside DPD's folder", 1, true), tostring(err))
os.remove(dir .. "/dpd-mobile.db")
untouched("database link inside")
print("PASS refuses a database linked inside the plugin folder")

-- HTTPS: every hop verified against the test CA, wrong names, downgrades and
-- loops refused, and an untrusted certificate authority rejected.
if tls and https_port ~= "0" then
    local secure = "https://localhost:" .. https_port
    Updater.cafile = certs .. "/ca.crt"
    Updater.api = secure .. "/api/good"
    assert(Updater.check(), "a check over HTTPS")
    Updater.download_prefix = secure .. "/"
    local function over(route)
        Updater.api = base .. "/api/good"
        local secured = assert(Updater.check())
        secured.zip_url = secure .. "/" .. route .. "/good/" .. secured.zip_name
        secured.sums_url = secure .. "/" .. route .. "/good/SHA256SUMS"
        return secured
    end
    fresh()
    assert(Updater.install(over("download"), dir, work .. "/work"))
    assert(versionOf(dir) == "99.0.0", "installed over HTTPS through a redirect")
    for route, expected in pairs({ ["download-wrong"] = "certificate not valid for localhost",
            ["download-plain"] = "unencrypted", ["download-loop"] = "too many" }) do
        fresh()
        done, err = Updater.install(over(route), dir, work .. "/work")
        assert(not done and err:find(expected, 1, true), route .. ": " .. tostring(err))
        untouched(route)
        print("PASS refuses " .. route .. ": " .. err)
    end
    Updater.cafile = "data/ca-bundle.crt"
    Updater.api = secure .. "/api/good"
    none, none_err = Updater.check()
    assert(not none and none_err:find("couldn't be verified", 1, true), tostring(none_err))
    configure(base)
    print("PASS https")
else
    print("SKIP https: no openssl")
end

-- The menu, dialogs and background check through main.lua.
local Device = require("device")
require("document/canvascontext"):init(Device)
require("ui/bidi").setup()
local UIManager = require("ui/uimanager")
local TextBoxWidget = require("ui/widget/textboxwidget")
Device:setEventHandlers(UIManager)
local function flush() UIManager:_checkTasks(); UIManager:_repaint() end
local function top() return UIManager._window_stack[#UIManager._window_stack].widget end
local function closeAll()
    for i = #UIManager._window_stack, 1, -1 do UIManager:close(UIManager._window_stack[i].widget) end
    flush()
end
local function screenshot(name)
    if screenshots then Device.screen.bb:writePNG(screenshots .. "/" .. name .. ".png") end
end
local function button(widget, text)
    for _, row in ipairs(widget.buttons_layout or (widget.button_table and widget.button_table.buttons_layout) or {}) do
        for _, b in ipairs(row) do if b.text == text then return b end end
    end
    for _, child in ipairs(widget) do
        local found = button(child, text)
        if found then return found end
    end
end
local function shown(widget)
    for _, window in ipairs(UIManager._window_stack) do if window.widget == widget then return true end end
    return false
end
local function textOf(widget) return widget.text or (widget.text_widget and widget.text_widget.text) or "" end
local function waitUpdate()
    local ffiutil, time = require("ffi/util"), require("ui/time")
    local started = time.now()
    while #UIManager._window_stack > 0 do
        local text = textOf(top())
        if text ~= "Checking for updates…" and not text:find("^Installing plugin ") then break end
        assert(time.to_s(time.since(started)) < 25, "the manual update task finished")
        ffiutil.usleep(50000)
        flush()
    end
    flush()
end
local function verdict(text)
    return TextBoxWidget.PTF_HEADER .. TextBoxWidget.PTF_BOLD_START .. text .. TextBoxWidget.PTF_BOLD_END
end

local DPD = dofile(root .. "/main.lua")
local function plugin(settings)
    return setmetatable({ settings = settings, path = dir, ui = { menu = { registerToMainMenu = function() end } } },
        { __index = DPD })
end
local can_open = Device.canOpenLink
Device.canOpenLink = function() return false end

-- Up to date: the check always says how the database stands, and offers
-- its release page when it is out of date or missing.
fresh()
Updater.api = base .. "/api/uptodate"
local settings = { font_size = 16, db_path = db_path }
local instance = plugin(settings)
assert(instance:helpMenu().text_func() == "Help", "Help has no update marker before a check")
instance:runUpdateCheck(); waitUpdate()
local box = top()
local installed = db_path and instance.db.info.dpd_release_version
local database_line = installed and ("Database " .. installed .. " · v0.4.29990101 is out")
    or "Database · not installed"
local missing_database_advice = "Download dpd-mobile-db.zip from DPD's latest release, extract it and copy dpd-mobile.db to koreader/data/dpd/."
local database_advice = installed and "Download dpd-mobile-db.zip from its release page, extract it and replace dpd-mobile.db."
    or missing_database_advice
assert(textOf(box):find(verdict(installed and "Database update available" or "No database installed")
    .. "\nPlugin " .. VERSION .. " · up to date\n" .. database_line .. "\n\n", 1, true) == 1, textOf(box))
assert(box.icon == "notice-info", "a result with a release link uses the information icon")
if installed then
    assert(textOf(box):find("Download dpd-mobile-db.zip from its release page, extract it and replace dpd-mobile.db.",
        1, true), textOf(box))
end
screenshot("update-uptodate")
button(box, "Database QR code").callback(); flush()
assert(top().text == DATABASE_PAGE, "the QR code holds the database release page")
screenshot("update-qr-database")
closeAll()
if db_path then
    write(work .. "/www/db-current.json", '{"tag_name": "' .. installed .. '"}')
    local checks = {
        { api = "/db-current", verdict = "Up to date", says = "Database " .. installed .. " · up to date" },
        { api = "/db-missing", verdict = "Plugin up to date", says = "Database " .. installed
            .. " · couldn't check: GitHub didn't find the release" },
    }
    for i, case in ipairs(checks) do
        Updater.database_api = base .. case.api
        instance:runUpdateCheck(); waitUpdate()
        assert(textOf(top()) == verdict(case.verdict) .. "\nPlugin " .. VERSION .. " · up to date\n" .. case.says
            and not button(top(), "Database QR code"), textOf(top()))
        screenshot("update-database-" .. i)
        closeAll()
    end
    configure(base)
end
Updater.api = base .. "/api/uptodate"
plugin({ font_size = 16 }):runUpdateCheck(); waitUpdate()
assert(textOf(top()):find(verdict("No database installed") .. "\nPlugin " .. VERSION
    .. " · up to date\nDatabase · not installed\n\nDownload dpd-mobile-db.zip from DPD's latest release, "
    .. "extract it and copy dpd-mobile.db to koreader/data/dpd/.", 1, true) == 1, textOf(top()))
assert(top().icon == "notice-info" and button(top(), "Database QR code"))
closeAll()
write(work .. "/not-a-database.db", "not SQLite")
plugin({ font_size = 16, db_path = work .. "/not-a-database.db" }):runUpdateCheck(); waitUpdate()
assert(textOf(top()) == verdict("Plugin up to date") .. "\nPlugin " .. VERSION
    .. " · up to date\nDatabase · couldn't open it to check its version\n\nSee Database status.", textOf(top()))
closeAll()
print("PASS database status")

-- A plugin update must retain repair advice even when its database cannot open.
Updater.api = base .. "/api/badhash"
for _, case in ipairs({
    { name = "no-database", line = "Database · not installed", advice = missing_database_advice,
        path = nil, link = true },
    { name = "unreadable-database", line = "Database · couldn't open it to check its version",
        advice = "See Database status.", path = work .. "/not-a-database.db" },
}) do
    plugin({ font_size = 16, db_path = case.path }):runUpdateCheck(); waitUpdate()
    assert(textOf(top()):find(case.line .. "\n\n" .. case.advice .. "\n\nWhat's new", 1, true), textOf(top()))
    assert(button(top(), "Install") and button(top(), "Plugin QR code") and button(top(), "Close"))
    assert((button(top(), "Database QR code") ~= nil) == (case.link == true))
    screenshot("plugin-update-" .. case.name)
    closeAll()
end
print("PASS plugin update retains database repair advice")

-- A failed install says what happened and offers the link.
Updater.api = base .. "/api/badhash"
instance:runUpdateCheck(); waitUpdate()
assert(settings.update_available == "99.0.0")
assert(instance:helpMenu().text_func() == "Help · 99.0.0 available", "Help shows a pending update")
local viewer = top()
assert(viewer.title == "Plugin 99.0.0 is available", tostring(viewer.title))
assert(button(viewer, "Install") and button(viewer, "Plugin QR code") and button(viewer, "Database QR code")
    and button(viewer, "Close"))
assert(#viewer.buttons_table == 2 and #viewer.buttons_table[1] == 2 and #viewer.buttons_table[2] == 2
    and viewer.buttons_table[1][1].text == "Plugin QR code" and viewer.buttons_table[1][2].text == "Database QR code"
    and viewer.buttons_table[2][1].text == "Close" and viewer.buttons_table[2][2].text == "Install",
    "release links occupy the first row; Close and Install occupy the second")
assert(textOf(viewer):find("Plugin " .. VERSION .. " → 99.0.0\n" .. database_line
    .. (installed and ", installed by hand" or "") .. "\n\n" .. database_advice
    .. "\n\nWhat's new\n\n• Fixture release for the check.",
    1, true) == 1, textOf(viewer))
assert(textOf(viewer):find("Install keeps your settings and database. KOReader then needs a restart.\n\n"
    .. "To install by hand, download dpd-koplugin-99.0.0.zip from the release page (Plugin QR code) and replace "
    .. "koreader/plugins/dpd.koplugin with the folder inside it.", 1, true), textOf(viewer))
assert(not textOf(viewer):find(PLUGIN_PAGE, 1, true), "the plugin URL is only in the link button")
screenshot("update-available")
button(viewer, "Plugin QR code").callback(); flush()
assert(top().text == PLUGIN_PAGE, "the QR code holds the plugin's release page")
screenshot("update-qr-plugin")
UIManager:close(top()); flush()
button(viewer, "Install").callback(); waitUpdate()
assert(not shown(viewer), "Install closes the release notes")
local failure = top()
assert(textOf(failure):find(verdict("Couldn't install 99.0.0") .. "\nThe download didn't match its checksum. "
    .. "Plugin " .. VERSION .. " is unchanged.\n\n", 1, true) == 1, textOf(failure))
assert(textOf(failure):find("To install by hand, download dpd-koplugin-99.0.0.zip from the release page and replace "
    .. "koreader/plugins/dpd.koplugin with the folder inside it. Your settings and database are kept.", 1, true),
    textOf(failure))
assert(failure.icon == "notice-warning" and button(failure, "Plugin QR code"))
assert(not textOf(failure):find(PLUGIN_PAGE, 1, true), "the failure text leaves the URL to the button")
screenshot("update-failed")
button(failure, "Plugin QR code").callback(); flush()
assert(top().text == PLUGIN_PAGE, "the QR code holds the release page")
closeAll()
untouched("badhash through the menu")

-- A release without its zip can't be installed, only downloaded by hand.
Updater.api = base .. "/api/nozip"
instance:runUpdateCheck(); waitUpdate()
assert(button(top(), "Install").enabled == false)
assert(not textOf(top()):find("Install keeps", 1, true), "manual installs leave out the Install paragraph")
closeAll()

-- A current database needs no release link, while the plugin keeps its name.
if db_path then
    Updater.database_api = base .. "/db-current"
    instance:runUpdateCheck(); waitUpdate()
    viewer = top()
    assert(#viewer.buttons_table == 2 and #viewer.buttons_table[1] == 1
        and viewer.buttons_table[1][1].text == "Plugin QR code"
        and viewer.buttons_table[2][1].text == "Close" and viewer.buttons_table[2][2].text == "Install")
    assert(not button(viewer, "Database QR code") and not textOf(viewer):find("installed by hand", 1, true))
    closeAll()
    configure(base)
end

-- A good install stops DPD and asks for a restart; a reader opened before it
-- shows only the restart item.
Updater.api = base .. "/api/good"
instance:runUpdateCheck(); waitUpdate()
viewer = top()
button(viewer, "Install").callback(); waitUpdate()
assert(not shown(viewer) and #UIManager._window_stack == 1, "only the restart message is left")
assert(instance.stopped and Updater.restart_pending == "99.0.0" and versionOf(dir) == "99.0.0")
assert(textOf(top()):find(verdict("Plugin 99.0.0 installed") .. "\n", 1, true) == 1, textOf(top()))
assert(textOf(top()):find(Device:canRestart() and "DPD lookups are off until KOReader restarts."
    or "Close KOReader and open it again to use it. DPD lookups are off until then.", 1, true), textOf(top()))
assert(settings.update_available == nil)
assert(instance:helpMenu().text_func() == "Help", "Help clears its update marker after installing")
screenshot("update-installed")
closeAll()
local items = {}
instance:addToMainMenu(items)
assert(#items.dpd.sub_item_table == 1 and items.dpd.sub_item_table[1].text == "Restart KOReader to finish the update",
    "the installing instance's menu shows only the restart item")
local later = plugin(settings)
later:init()
assert(later.restart_pending and not later.direct)
items = {}
later:addToMainMenu(items)
assert(#items.dpd.sub_item_table == 1 and items.dpd.sub_item_table[1].text == "Restart KOReader to finish the update")
items.dpd.sub_item_table[1].callback(); flush()
assert(textOf(top()):find("Plugin 99.0.0 installed", 1, true))
closeAll()
instance:inputLookup(); flush()
assert(textOf(top()):find("Plugin 99.0.0 installed", 1, true), "a stopped DPD points to the restart")
closeAll()
print("PASS menu flow")

-- The backup goes only after a fully supported start.
fresh()
sh("cp -R " .. q(dir) .. " " .. q(dir .. ".previous"))
local Compat = require("dpd/compat")
local supported = Compat.missing
Compat.missing = function() return { "a newer feature" } end
plugin({}):init(); flush(); closeAll()
Compat.missing = supported
assert(exists(dir .. ".previous"), "an unsupported start keeps the backup")
plugin({}):init()
assert(not exists(dir .. ".previous"), "a supported start removes it")
print("PASS backup kept until a supported start")

-- Installing from one instance stops every other running instance too.
fresh()
Updater.api = base .. "/api/good"
local file_manager = plugin({})
file_manager:init()
local reader = plugin({})
reader:init()
assert(not reader.stopped)
file_manager:runUpdateCheck(); waitUpdate()
button(top(), "Install").callback(); waitUpdate()
assert(Updater.restart_pending == "99.0.0" and reader.stopped, "every running DPD stops")
closeAll()
print("PASS stops every running instance")

-- A failed restore stops every DPD and only explains how to restore it.
fresh()
Updater.api = base .. "/api/good"
local first = plugin({})
first:init()
Updater.rename = function(from, to)
    if from:match("%.update$") or from:match("%.previous$") then return nil, "injected" end
    return os.rename(from, to)
end
first:runUpdateCheck(); waitUpdate()
button(top(), "Install").callback(); waitUpdate()
Updater.rename = os.rename
assert(first.stopped and Updater.broken, "a failed restore stops DPD")
assert(textOf(top()):find(verdict("Update not finished") .. "\n", 1, true) == 1
    and textOf(top()):find("rename\n" .. real .. ".previous\nto\n" .. real .. "\nand restart KOReader.", 1, true)
    and not textOf(top()):find("unchanged", 1, true), textOf(top()))
assert(top().icon == "notice-warning")
closeAll()
local after = plugin({})
after:init()
items = {}
after:addToMainMenu(items)
assert(#items.dpd.sub_item_table == 1 and items.dpd.sub_item_table[1].text == "Restore DPD after the failed update")
for _, open in ipairs({ function() items.dpd.sub_item_table[1].callback() end,
        function() first:inputLookup() end, function() first:aboutLicenses() end }) do
    open(); flush()
    assert(textOf(top()):find(verdict("Update not finished") .. "\nThe new folder", 1, true) == 1
        and textOf(top()):find("rename\n" .. real .. ".previous\nto\n" .. real .. "\nand restart KOReader.", 1, true)
        and not textOf(top()):find("KOReader..", 1, true), textOf(top()))
    closeAll()
end
print("PASS a failed restore")

-- A manual request waiting for Wi-Fi must not outlive its File Manager.
fresh()
local NetworkMgr = require("ui/network/manager")
local saved_connected, saved_wifi, saved_turn_on, saved_network = NetworkMgr.isConnected,
    NetworkMgr.isWifiOn, NetworkMgr.turnOnWifi, NetworkMgr.getCurrentNetwork
local connected = false
NetworkMgr.isConnected = function() return connected end
NetworkMgr.isWifiOn = function() return connected end
NetworkMgr.turnOnWifi = function(_, callback) callback(); return true end
NetworkMgr.getCurrentNetwork = function() return nil end
G_reader_settings:saveSetting("wifi_enable_action", "turn_on")
local retired = plugin({ font_size = 16, db_path = db_path })
retired:init()
local requests_before = read(log_file)
retired:checkForUpdates(); flush()
assert(NetworkMgr.pending_connectivity_check and textOf(top()) == "Connecting to Wi-Fi…")
top():onTapClose(); flush()
retired:onCloseWidget()
connected = true
local ffiutil, time = require("ffi/util"), require("ui/time")
local began = time.now()
while NetworkMgr.pending_connectivity_check and time.to_s(time.since(began)) < 3 do
    ffiutil.usleep(50000); flush()
end
assert(not NetworkMgr.pending_connectivity_check and #UIManager._window_stack == 0
    and read(log_file) == requests_before, "a retired owner's deferred check does nothing")
NetworkMgr.isConnected, NetworkMgr.isWifiOn, NetworkMgr.turnOnWifi, NetworkMgr.getCurrentNetwork =
    saved_connected, saved_wifi, saved_turn_on, saved_network
print("PASS retired manual update callback")

-- Headers can arrive forever without reaching LuaSocket's body-sink timeout.
-- Shorten only our deadline; the real child request and UI timers still run.
local real_schedule = UIManager.scheduleIn
local function shortDeadline(action)
    UIManager.scheduleIn = function(self, seconds, callback, ...)
        return real_schedule(self, (seconds == 30 or seconds == 180) and 0.7 or seconds, callback, ...)
    end
    action()
    UIManager.scheduleIn = real_schedule
end
Updater.api = base .. "/api/headers"
local manual = plugin({ font_size = 16 })
local ticked
began = time.now()
UIManager:scheduleIn(0.05, function() ticked = time.now() end)
shortDeadline(function() manual:runUpdateCheck() end)
local returned_after = time.to_s(time.since(began))
assert(returned_after < 0.5, "manual checks return control to the UI")
waitUpdate()
assert(ticked and time.to_s(ticked - began) < 0.6, "the UI ran during slow headers")
assert(time.to_s(time.since(began)) < 2 and textOf(top()):find("connection timed out", 1, true),
    "the manual deadline bounds the entire request")
print(string.format("PASS slow-header manual check: returned %.3fs, UI timer %.3fs, deadline %.3fs",
    returned_after, time.to_s(ticked - began), time.to_s(time.since(began))))
closeAll()

manual = plugin({ font_size = 16 })
began = time.now()
UIManager:scheduleIn(0.2, function() top():onTapClose() end)
manual:runUpdateCheck(); waitUpdate()
assert(time.to_s(time.since(began)) < 1 and not manual.settings.update_checked and #UIManager._window_stack == 0,
    "cancelling a slow manual check closes it without a result")
print(string.format("PASS slow-header manual check cancelled in %.3fs", time.to_s(time.since(began))))

-- Cancelling a download leaves the old plugin intact and unlocks a retry.
fresh()
local stalled_release = release("good")
Updater.download_prefix = base .. "/"
stalled_release.zip_url = base .. "/download-stall/good/" .. stalled_release.zip_name
manual = plugin({ font_size = 16 })
UIManager:scheduleIn(0.2, function() top():onTapClose() end)
manual:installUpdate(stalled_release)
assert(Updater.installing, "the parent reserves the install before yielding")
local concurrent, concurrent_err = Updater.install(stalled_release, dir, work .. "/work")
assert(not concurrent and concurrent_err:find("already being installed", 1, true))
waitUpdate()
assert(not Updater.installing and not Updater.restart_pending and #UIManager._window_stack == 0)
untouched("cancelled install")
configure(base)

-- Stopping an owner during a successful fetch must also prevent the swap.
local good_release = release("good")
local real_check = Updater.check
Updater.check = function() ffiutil.usleep(400000); return good_release end
manual = plugin({ font_size = 16 })
UIManager:scheduleIn(0.1, function() manual:onCloseDocument() end)
manual:runUpdateCheck(); waitUpdate()
Updater.check = real_check
assert(manual.stopped and not manual.settings.update_checked and #UIManager._window_stack == 0)
if db_path then
    local cancelled, cancel_err = plugin({ db_path = db_path }):databaseCheck(function() return nil, "cancelled" end)
    assert(not cancelled and cancel_err == "cancelled", "cancelling the database check dismisses the whole result")
end
Updater.check = function() error("injected update child failure") end
plugin({ font_size = 16 }):runUpdateCheck(); waitUpdate()
Updater.check = real_check
assert(textOf(top()):find("update task failed", 1, true), "a failed child reports an error")
closeAll()
local actual_download = manual.updateTask
manual = plugin({ font_size = 16 })
manual.updateTask = function(self, task, busy, timeout)
    return actual_download(self, function() ffiutil.usleep(400000); return task() end, busy, timeout)
end
UIManager:scheduleIn(0.1, function() manual:onCloseDocument() end)
manual:installUpdate(good_release); waitUpdate()
assert(manual.stopped and not Updater.installing and not Updater.restart_pending)
untouched("stopped install")
assert(not exists(require("datastorage"):getDataDir() .. "/data/dpd/dpd-update.zip"),
    "cancelled and stopped installs remove their download")
print("PASS manual deadlines, responsive UI, cancellation, and stopped owners")

-- The background check: opt-in, weekly, retryable, announced once, and
-- in a child process, so a stalled server never holds up the UI.
fresh()
local real_walltime, elapsed = os.time, 0
os.time = function() return real_walltime() + elapsed end
local ffiutil, time = require("ffi/util"), require("ui/time")
local NetworkMgr = require("ui/network/manager")
local connected = true
NetworkMgr.isConnected = function() return connected end
local launched, finished, real_background = 0, 0, Updater.checkInBackground
Updater.checkInBackground = function(on_done)
    launched = launched + 1
    return real_background(function(version) on_done(version); finished = finished + 1 end)
end
local function pump(condition, seconds)
    local deadline = os.time() + seconds
    while not condition() and os.time() <= deadline do UIManager:_checkTasks(); ffiutil.usleep(50000) end
    flush()
    return condition()
end
local real_schedule = UIManager.scheduleIn
-- Start the delayed check at once, then let the real timers poll the child.
local function delay(action)
    local scheduled
    UIManager.scheduleIn = function(_, seconds, fn)
        assert(seconds == 15 and not scheduled, "only one delayed update check")
        scheduled = fn
    end
    action()
    UIManager.scheduleIn = real_schedule
    return scheduled
end
local function start(state)
    local scheduled = delay(function() plugin(state):scheduleUpdateCheck() end)
    if scheduled then scheduled() end
end
local function background(state)
    start(state)
    assert(pump(function() return finished == launched end, 30), "the background check finished")
end
Updater.api = base .. "/api/good"
local auto = { font_size = 16 }
background(auto)
assert(launched == 0, "off by default")
local automatic = plugin(auto)
local toggle
for _, item in ipairs(automatic:helpMenu().sub_item_table) do
    if item.text == "Check for updates automatically" then toggle = item.callback end
end
assert(toggle, "automatic update checkbox exists")
local skipped = assert(delay(toggle), "enabling the checkbox schedules a check immediately")
assert(not Updater.auto_checking, "a pending check has not started a request")
assert(not delay(function() automatic:onNetworkConnected(); automatic:onResume() end), "events share the pending check")
connected = false
skipped()
assert(not Updater.auto_checking and not Updater.auto_pending, "Wi-Fi lost during delay leaves retry available")
background(auto)
assert(launched == 0, "never without a connection")
connected = true
local reconnected = assert(delay(function() automatic:onNetworkConnected() end), "reconnect schedules a retry")
automatic:onSuspend()
assert(not Updater.auto_pending, "suspending cancels the delayed check")
local resumed = assert(delay(function() automatic:onResume() end), "resuming schedules a retry")
reconnected()
assert(launched == 0, "a canceled callback cannot start a duplicate request")
toggle()
resumed()
assert(launched == 0 and not Updater.auto_pending, "disabling cancels a pending check")
local enabled = assert(delay(toggle), "re-enabling still schedules a check")
enabled()
assert(pump(function() return finished == launched end, 30), "the automatic check finished")
assert(launched == 1 and auto.update_available == "99.0.0" and auto.update_notified == "99.0.0")
assert(textOf(top()) == "DPD plugin 99.0.0 is available: see Help.", "announced as a one-line notification")
assert(automatic:helpMenu().text_func() == "Help · 99.0.0 available", "Help shows the background result")
screenshot("update-notification")
closeAll()
background(auto)
assert(launched == 1 and not Updater.auto_checking, "completed check releases the in-flight guard")
elapsed = elapsed + Updater.check_interval - 60
background(auto)
assert(launched == 1, "at most weekly")
elapsed = elapsed + 61
background(auto)
assert(launched == 2 and #UIManager._window_stack == 0, "weekly recheck in the same session, announced once per version")

-- Disabling while the child is running suppresses its notification and
-- leaves no saved check date. Re-enabling can check again in this session.
local disabled = { font_size = 16, update_auto = true }
start(disabled)
disabled.update_auto = nil
assert(pump(function() return finished == launched end, 30), "the disabled check finished")
assert(launched == 3 and disabled.update_checked == nil and #UIManager._window_stack == 0,
    "no notification or saved result after disabling")
assert(not Updater.auto_checking, "a disabled in-flight result does not block re-enabling")
print("PASS automatic setting, reconnect, resume, and cancellation")

-- A server that stalls past the timeout: UI timers keep running meanwhile.
Updater.api = base .. "/api/stall"
local retry_interval = Updater.retry_interval
assert(retry_interval == 3600, "failed requests have a one-hour cooldown")
Updater.retry_interval = 1
local stalled = { font_size = 16, update_auto = true }
local began = time.now()
start(stalled)
assert(launched == 4 and time.to_s(time.since(began)) < 1, "starting the check doesn't wait for the network")
local ticked
UIManager:scheduleIn(0.2, function() ticked = time.now() end)
assert(pump(function() return ticked ~= nil end, 3) and time.to_s(ticked - began) < 1.5, "a UI timer ran on time")
assert(finished < launched, "the check was still waiting on the server")
start(stalled)
assert(launched == 4, "an in-flight check blocks duplicate requests")
assert(pump(function() return finished == launched end, 30), "the stalled check gave up")
assert(stalled.update_available == nil and stalled.update_checked == nil, "a failed check changes nothing")
assert(not Updater.auto_checking and Updater.auto_retry_at > time.now(), "failure releases the guard with a retry cooldown")
local retry_owner = plugin(stalled)
assert(not delay(function() retry_owner:onNetworkConnected(); retry_owner:onResume() end),
    "reconnect and resume respect the failed-request cooldown")
ffiutil.usleep(1100000)
Updater.api = base .. "/api/good"
local retry = assert(delay(function() retry_owner:onNetworkConnected() end), "reconnect after cooldown schedules retry")
retry()
assert(pump(function() return finished == launched end, 30), "the retry finished")
assert(launched == 5 and stalled.update_checked and stalled.update_available == "99.0.0"
    and not Updater.auto_retry_at, "failed started request can later succeed without restart")
closeAll()
Updater.retry_interval = retry_interval
os.time = real_walltime
Updater.checkInBackground, Device.canOpenLink = real_background, can_open
print("PASS background check, in a child process")

-- Optional, with DPD_UPDATE_LIVE=1: real certificates. GitHub verifies;
-- self-signed, untrusted, expired and wrong-host certificates don't.
if os.getenv("DPD_UPDATE_LIVE") then
    package.loaded["dpd/updater"] = nil
    local Live = require("dpd/updater")
    local latest = assert(Live.check())
    assert(Live.parseVersion(latest.version) and Live.latestDatabase())
    for _, host in ipairs({ "self-signed", "untrusted-root", "expired", "wrong.host" }) do
        Live.api = "https://" .. host .. ".badssl.com/"
        local bad, why = Live.check()
        assert(not bad and why:find("couldn't be verified", 1, true), host .. ": " .. tostring(why))
        print("PASS rejects " .. host .. ": " .. why)
    end
    print("PASS live certificates")
end
end, debug.traceback)
stopServer()
if not ok then
    io.stderr:write(failure, "\n")
    os.exit(1)
end
os.execute("rm -rf " .. q(work))
print("ALL PASS")
os.exit(0)
