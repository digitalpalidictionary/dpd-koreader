local Updater = require("dpd/updater")

local DOWNLOAD = "https://github.com/digitalpalidictionary/dpd-koreader/releases/download/v0.4.0/"

local function release(fields)
    local data = {
        tag_name = "v0.4.0",
        html_url = "https://github.com/digitalpalidictionary/dpd-koreader/releases/tag/v0.4.0",
        body = "## Changes\r\n\r\n- **Faster** lookups",
        assets = {
            { name = "dpd-koplugin-0.4.0.zip", size = 1368594, browser_download_url = DOWNLOAD .. "dpd-koplugin-0.4.0.zip" },
            { name = "SHA256SUMS", size = 89, browser_download_url = DOWNLOAD .. "SHA256SUMS" },
        },
    }
    for key, value in pairs(fields or {}) do data[key] = value end
    return data
end

local function plugin(extra)
    local entries = {
        { path = "dpd.koplugin/", mode = "directory", size = 0 },
        { path = "dpd.koplugin/main.lua", mode = "file", size = 100 },
        { path = "dpd.koplugin/_meta.lua", mode = "file", size = 10 },
        { path = "dpd.koplugin/dpd/version.lua", mode = "file", size = 16 },
    }
    for _, entry in ipairs(extra or {}) do entries[#entries + 1] = entry end
    return entries
end

describe("updater versions", function()
    it("compares numerically and never offers a malformed or older version", function()
        assert.is_true(Updater.isNewer("0.3.1", "0.3.0"))
        assert.is_true(Updater.isNewer("0.10.0", "0.9.9"))
        assert.is_true(Updater.isNewer("v1.0.0", "0.99.99"))
        assert.is_true(Updater.isNewer("v0.4.20261020", "v0.4.20260926"))
        assert.is_false(Updater.isNewer("0.3.0", "0.3.0"))
        assert.is_false(Updater.isNewer("0.2.9", "0.3.0"))
        assert.is_false(Updater.isNewer("0.4", "0.3.0"))
        assert.is_false(Updater.isNewer("0.4.0-beta", "0.3.0"))
        assert.is_false(Updater.isNewer(nil, "0.3.0"))
        assert.is_false(Updater.isNewer("0.4.0", nil))
    end)
end)

describe("updater certificate names", function()
    it("matches exact names and one-label wildcards only", function()
        assert.is_true(Updater.hostMatches({ "github.com", "www.github.com" }, "github.com"))
        assert.is_true(Updater.hostMatches({ "*.github.com" }, "API.GitHub.com"))
        assert.is_true(Updater.hostMatches({ "*.githubusercontent.com" }, "release-assets.githubusercontent.com"))
        assert.is_false(Updater.hostMatches({ "*.github.com" }, "github.com"))
        assert.is_false(Updater.hostMatches({ "*.badssl.com" }, "wrong.host.badssl.com"))
        assert.is_false(Updater.hostMatches({ "*.github.com" }, "evilgithub.com"))
        assert.is_false(Updater.hostMatches({ "*.com" }, "github.com"))
        assert.is_false(Updater.hostMatches({ "github.com.evil.net" }, "github.com"))
        assert.is_false(Updater.hostMatches(nil, "github.com"))
    end)
end)

describe("updater release parsing", function()
    it("finds the exact plugin zip and checksum file of the release", function()
        local parsed = assert(Updater.parseRelease(release()))
        assert.equal("0.4.0", parsed.version)
        assert.equal("dpd-koplugin-0.4.0.zip", parsed.zip_name)
        assert.equal(DOWNLOAD .. "dpd-koplugin-0.4.0.zip", parsed.zip_url)
        assert.equal(1368594, parsed.zip_size)
        assert.equal(DOWNLOAD .. "SHA256SUMS", parsed.sums_url)
        assert.equal("https://github.com/digitalpalidictionary/dpd-koreader/releases/tag/v0.4.0", parsed.page)
        assert.equal("Changes\n\n• Faster lookups", parsed.notes)
    end)

    it("ignores other zips and downloads from anywhere but the plugin's releases", function()
        local parsed = assert(Updater.parseRelease(release{ html_url = "https://example.com/x", assets = {
            { name = "dpd-koplugin-0.3.0.zip", browser_download_url = DOWNLOAD .. "dpd-koplugin-0.3.0.zip" },
            { name = "dpd-koplugin-0.4.0.zip", browser_download_url = "https://example.com/dpd-koplugin-0.4.0.zip" },
            { name = "SHA256SUMS", browser_download_url = DOWNLOAD .. "SHA256SUMS extra" },
        } }))
        assert.is_nil(parsed.zip_url)
        assert.is_nil(parsed.sums_url)
        assert.equal(Updater.page, parsed.page)
    end)

    it("rejects drafts, prereleases and unexpected tags", function()
        assert.is_nil(Updater.parseRelease(release{ draft = true }))
        assert.is_nil(Updater.parseRelease(release{ prerelease = true }))
        assert.is_nil(Updater.parseRelease(release{ tag_name = "0.4.0" }))
        assert.is_nil(Updater.parseRelease(release{ tag_name = "v0.4.0-rc1" }))
        assert.is_nil(Updater.parseRelease("not a table"))
        local parsed, err = Updater.parseRelease(release{ tag_name = 4 })
        assert.is_nil(parsed)
        assert.matches("unexpected name", err)
    end)

    it("keeps the words of the notes and cuts long ones between characters", function()
        assert.equal("See the guide and run it.",
            Updater.plainNotes("See [the guide](https://example.com) and run `it`."))
        assert.is_nil(Updater.plainNotes("  \n "))
        assert.is_nil(Updater.plainNotes(nil))
        local saved = Updater.max_notes
        Updater.max_notes = 4
        assert.equal("abā…", Updater.plainNotes("abāde"))
        Updater.max_notes = 3
        assert.equal("ab…", Updater.plainNotes("abāde"))
        Updater.max_notes = saved
    end)

    it("keeps headings on their own lines and uses bullets only at line starts", function()
        assert.equal("Changes\n• Faster lookups\n• Smaller popup\nFixes\nText - kept * here",
            Updater.plainNotes("## Changes\n- **Faster** lookups\n* Smaller popup\n### Fixes\nText - kept * here"))
        assert.equal("• First\n\n• Second", Updater.plainNotes("* First\n\n- Second"))
        assert.equal("Heading\n\nText", Updater.plainNotes("# Heading\n\nText"))
    end)

    it("reads the database release's tag and keeps its page on DPD's releases", function()
        local page = "https://github.com/digitalpalidictionary/dpd-db/releases/tag/v0.4.20261020"
        assert.same({ tag = "v0.4.20261020", page = page },
            Updater.parseDatabaseRelease({ tag_name = "v0.4.20261020", html_url = page }))
        assert.same({ tag = "v0.4.20261020", page = Updater.database_page },
            Updater.parseDatabaseRelease({ tag_name = "v0.4.20261020", html_url = "https://example.com/x" }))
        local parsed, err = Updater.parseDatabaseRelease({ tag_name = "latest" })
        assert.is_nil(parsed)
        assert.matches("unexpected name", err)
        assert.is_nil(Updater.parseDatabaseRelease(nil))
    end)

    it("reads the zip's line from SHA256SUMS", function()
        local hash = string.rep("A", 64)
        local sums = "0000  other.zip\n" .. hash .. "  dpd-koplugin-0.4.0.zip\n"
        assert.equal(hash:lower(), Updater.parseSums(sums, "dpd-koplugin-0.4.0.zip"))
        assert.equal(hash:lower(), Updater.parseSums(hash .. " *dpd-koplugin-0.4.0.zip\r\n", "dpd-koplugin-0.4.0.zip"))
        assert.is_nil(Updater.parseSums(sums, "dpd-koplugin-0.4.1.zip"))
        assert.is_nil(Updater.parseSums("abcd  dpd-koplugin-0.4.0.zip", "dpd-koplugin-0.4.0.zip"))
        assert.is_nil(Updater.parseSums(nil, "dpd-koplugin-0.4.0.zip"))
    end)
end)

describe("updater zip entries", function()
    it("accepts the plugin's files and folders with paths inside the plugin folder", function()
        local entries = assert(Updater.checkEntries(plugin{ { path = "dpd.koplugin/ui/", mode = "directory", size = 0 } }))
        assert.equal(4, #entries)
        assert.same({ path = "dpd.koplugin/main.lua", rel = "main.lua", mode = "file", size = 100 }, entries[1])
        assert.equal("ui", entries[4].rel)
    end)

    local function rejects(extra, pattern)
        local entries, err = Updater.checkEntries(plugin(extra))
        assert.is_nil(entries)
        assert.matches(pattern, err)
    end

    it("rejects links, special files and unsafe paths", function()
        rejects({ { path = "dpd.koplugin/link", mode = "link", size = 0 } }, "link")
        rejects({ { path = "dpd.koplugin/fifo", mode = "other", size = 0 } }, "special")
        rejects({ { path = "dpd.koplugin/../evil.lua", mode = "file", size = 1 } }, "unsafe")
        rejects({ { path = "dpd.koplugin/dpd/./x.lua", mode = "file", size = 1 } }, "unsafe")
        rejects({ { path = "dpd.koplugin//x.lua", mode = "file", size = 1 } }, "unsafe")
        rejects({ { path = "dpd.koplugin/a\\..\\b", mode = "file", size = 1 } }, "unsafe")
        rejects({ { path = "/dpd.koplugin/x.lua", mode = "file", size = 1 } }, "outside")
        rejects({ { path = "other.koplugin/main.lua", mode = "file", size = 1 } }, "outside")
        rejects({ { path = "dpd.koplugin.evil/x.lua", mode = "file", size = 1 } }, "outside")
        rejects({ { path = "dpd.koplugin", mode = "file", size = 1 } }, "unsafe")
        rejects({ { path = "dpd.koplugin/x.lua", mode = "file", size = -1 } }, "unsafe")
    end)

    it("rejects duplicates, also by case for FAT storage", function()
        rejects({ { path = "dpd.koplugin/main.lua", mode = "file", size = 1 } }, "twice")
        rejects({ { path = "dpd.koplugin/MAIN.lua", mode = "file", size = 1 } }, "twice")
    end)

    it("rejects empty, oversized and incomplete plugins", function()
        local entries, err = Updater.checkEntries({})
        assert.is_nil(entries); assert.matches("empty", err)
        rejects({ { path = "dpd.koplugin/big.bin", mode = "file", size = Updater.max_unpacked_bytes } }, "too large")
        local many = {}
        for i = 1, Updater.max_entries do many[i] = { path = "dpd.koplugin/f" .. i, mode = "file", size = 1 } end
        rejects(many, "too many")
        entries, err = Updater.checkEntries({ { path = "dpd.koplugin/main.lua", mode = "file", size = 1 },
            { path = "dpd.koplugin/_meta.lua", mode = "file", size = 1 } })
        assert.is_nil(entries); assert.matches("dpd/version.lua", err)
        entries, err = Updater.checkEntries({ { path = "dpd.koplugin/main.lua", mode = "directory", size = 0 },
            { path = "dpd.koplugin/_meta.lua", mode = "file", size = 1 },
            { path = "dpd.koplugin/dpd/version.lua", mode = "file", size = 1 } })
        assert.is_nil(entries); assert.matches("main.lua", err)
    end)
end)

describe("updater install", function()
    after_each(function() Updater.restart_pending = nil end)

    it("refuses a second install before the restart", function()
        Updater.restart_pending = "0.4.0"
        local ok, err = Updater.install(assert(Updater.parseRelease(release())), "/nowhere", "/tmp")
        assert.is_nil(ok)
        assert.matches("restart KOReader", err)
    end)
end)
