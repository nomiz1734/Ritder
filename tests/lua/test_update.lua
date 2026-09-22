-- Unit tests for frontend/ritder/update.lua (run by tests/run_lua_tests.py).
local Update = require("ritder/update")
local util = Update.util

local function eq(a, b, msg)
    if a ~= b then error((msg or "") .. " expected " .. tostring(b) .. ", got " .. tostring(a), 2) end
end
local function truthy(v, msg) if not v then error(msg or "expected a true value", 2) end end
local function falsy(v, msg) if v then error(msg or "expected a false value, got " .. tostring(v), 2) end end

local function exists(path) return require("libs/libkoreader-lfs").attributes(path, "mode") ~= nil end

-- A fake app dir + work dir, with Update.unpack replaced by the Python tarfile version.
local function sandbox(files)
    local root = py_tmpdir()
    local app = root .. "/app"
    util.mkdirP(app)
    for rel, content in pairs(files or {}) do
        util.mkdirP((app .. "/" .. rel):match("^(.*)/[^/]+$"))
        util.writeFile(app .. "/" .. rel, content)
    end
    Update.app_dir = app
    Update.work_dir = app .. "/userdata/update"
    util.mkdirP(Update.work_dir)
    Update.unpack = function(archive, dest) return py_unpack(archive, dest) end
    return app, Update.work_dir, root
end

local function package(root, entries)
    local path = root .. "/pkg.tar.gz"
    py_make_tar(path, entries)
    return path
end

local tests = {}

function tests.version_compare()
    truthy(Update.isNewer("0.1.1", "0.1.0"))
    truthy(Update.isNewer("0.10.0", "0.9.9"), "numeric, not lexical")
    truthy(Update.isNewer("v1.0.0", "0.9"))
    truthy(Update.isNewer("1.0.1", "1.0"))
    falsy(Update.isNewer("0.1.0", "0.1.0"), "same version")
    falsy(Update.isNewer("0.0.9", "0.1.0"), "never a downgrade")
    falsy(Update.isNewer("1.0", "1.0.0"))
end

function tests.safe_paths()
    truthy(Update.isSafePath("frontend/ritder/update.lua"))
    truthy(Update.isSafePath("a..b/c"))
    falsy(Update.isSafePath("../etc/passwd"))
    falsy(Update.isSafePath("a/../../b"))
    falsy(Update.isSafePath("/etc/passwd"))
    falsy(Update.isSafePath(""))
end

function tests.arm64_elf_check_on_real_luajit()
    truthy(Update.isArm64Elf(DIST .. "/luajit"), "dist luajit must be ARM64")
    truthy(Update.isArm64Elf(DIST .. "/sys/ld-linux-aarch64.so.1"))
    falsy(Update.isArm64Elf(DIST .. "/reader.lua"))
end

function tests.sha256_matches_known_value()
    local root = py_tmpdir()
    util.writeFile(root .. "/abc", "abc")
    eq(Update.sha256File(root .. "/abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
end

function tests.install_replaces_files_keeps_userdata_and_backs_up()
    local app, work, root = sandbox{
        ["luajit"] = "old luajit",
        ["reader.lua"] = "old reader",
        ["launch.sh"] = "old launch",
        ["frontend/a.lua"] = "old a",
        ["userdata/settings.reader.lua"] = "my settings",
    }
    local pkg = package(root, {
        ["luajit"] = "@ELF_ARM64",
        ["reader.lua"] = "new reader",
        ["launch.sh"] = "new launch",
        ["frontend/a.lua"] = "new a",
        ["frontend/b.lua"] = "brand new b",
        ["userdata/settings.reader.lua"] = "must not win",
    })
    local ok, err = Update.install(pkg, "0.2.0")
    truthy(ok, err)
    eq(util.readFile(app .. "/frontend/a.lua"), "new a")
    eq(util.readFile(app .. "/frontend/b.lua"), "brand new b")
    eq(util.readFile(app .. "/userdata/settings.reader.lua"), "my settings", "userdata is protected")
    eq(util.readFile(work .. "/backup/frontend/a.lua"), "old a", "replaced file is backed up")
    eq(util.readFile(work .. "/pending"), "0.2.0")
    truthy(util.readFile(work .. "/added.txt"):find("frontend/b.lua", 1, true))
    falsy(exists(work .. "/installing"), "marker removed after success")
    falsy(exists(work .. "/staging"), "staging cleaned up")
    falsy(exists(pkg), "package removed after install")
    eq(Update.pendingVersion(), "0.2.0")
end

function tests.restore_backup_undoes_an_install()
    local app, work, root = sandbox{
        ["luajit"] = "old luajit", ["reader.lua"] = "old reader", ["launch.sh"] = "old launch",
    }
    local pkg = package(root, {
        ["luajit"] = "@ELF_ARM64", ["reader.lua"] = "new reader", ["launch.sh"] = "new launch",
        ["extra/new.lua"] = "added",
    })
    truthy(Update.install(pkg, "0.2.0"))
    Update.restoreBackup(app, work)
    eq(util.readFile(app .. "/reader.lua"), "old reader")
    eq(util.readFile(app .. "/luajit"), "old luajit")
    falsy(exists(app .. "/extra/new.lua"), "added file removed")
    falsy(exists(work .. "/backup"))
end

function tests.confirm_drops_rollback_data()
    local _, work, root = sandbox{ ["luajit"] = "x", ["reader.lua"] = "x", ["launch.sh"] = "x" }
    local pkg = package(root, { ["luajit"] = "@ELF_ARM64", ["reader.lua"] = "y", ["launch.sh"] = "y" })
    truthy(Update.install(pkg, "0.2.0"))
    Update.confirm()
    falsy(exists(work .. "/pending"))
    falsy(exists(work .. "/backup"))
    eq(Update.pendingVersion(), nil)
end

function tests.install_rejects_wrong_architecture()
    local app, work, root = sandbox{ ["reader.lua"] = "old reader" }
    local pkg = package(root, { ["luajit"] = "@ELF_X86_64", ["reader.lua"] = "new", ["launch.sh"] = "new" })
    local ok, err = Update.install(pkg, "0.2.0")
    falsy(ok)
    truthy(err:find("ARM64", 1, true), err)
    eq(util.readFile(app .. "/reader.lua"), "old reader", "nothing touched")
    falsy(exists(work .. "/pending"))
end

function tests.install_rejects_path_traversal_and_links()
    local _, _, root = sandbox{}
    local ok, err = Update.install(package(root, { ["../evil"] = "x", ["luajit"] = "@ELF_ARM64" }), "0.2.0")
    falsy(ok)
    truthy(err:find("không hợp lệ", 1, true), err)
    ok, err = Update.install(package(root, { ["luajit"] = { link = "/bin/sh" } }), "0.2.0")
    falsy(ok)
    truthy(err:find("không được phép", 1, true), err)
end

function tests.install_requires_core_files()
    local _, _, root = sandbox{}
    local ok, err = Update.install(package(root, { ["luajit"] = "@ELF_ARM64", ["launch.sh"] = "x" }), "0.2.0")
    falsy(ok)
    truthy(err:find("reader.lua", 1, true), err)
end

-- Manifest parsing with the network replaced by a canned response.
local function withResponse(body, fn)
    local real = Update.httpGet
    Update.httpGet = function(_, open_sink)
        local sink = open_sink()
        sink(body)
        sink(nil)
        return true
    end
    local ok, err = pcall(fn)
    Update.httpGet = real
    if not ok then error(err, 0) end
end

local SHA = string.rep("ab", 32)

function tests.manifest_relative_file_resolves_next_to_update_json()
    withResponse('{"version":"0.2.0","file":"ritder-update.tar.gz","sha256":"' .. SHA:upper() .. '","size":10}', function()
        local m = assert(Update.fetchManifest("https://github.com/nomiz1734/Ritder/releases/latest/download/update.json"))
        eq(m.package_url, "https://github.com/nomiz1734/Ritder/releases/latest/download/ritder-update.tar.gz")
        eq(m.sha256, SHA, "sha256 lowercased")
        eq(m.size, 10)
    end)
end

function tests.manifest_validation()
    local url = "https://example.com/update.json"
    withResponse('{"file":"x.tar.gz","sha256":"' .. SHA .. '"}', function()
        local m, err = Update.fetchManifest(url)
        falsy(m); truthy(err:find("version", 1, true), err)
    end)
    withResponse('{"version":"1","file":"x.tar.gz","sha256":"abc"}', function()
        local m, err = Update.fetchManifest(url)
        falsy(m); truthy(err:find("sha256", 1, true), err)
    end)
    withResponse('{"version":"1","url":"http://example.com/x.tar.gz","sha256":"' .. SHA .. '"}', function()
        local m, err = Update.fetchManifest(url)
        falsy(m); truthy(err:find("HTTPS", 1, true), err)
    end)
    withResponse('not json', function()
        local m = Update.fetchManifest(url)
        falsy(m)
    end)
end

function tests.check_offers_only_newer_versions()
    local current = Update.currentVersion()
    eq(current, "0.1.0", "build_info version")
    withResponse('{"version":"0.1.0","file":"x.tar.gz","sha256":"' .. SHA .. '"}', function()
        eq(Update.check("https://example.com/update.json"), false)
    end)
    withResponse('{"version":"0.1.1","file":"x.tar.gz","sha256":"' .. SHA .. '"}', function()
        local m = Update.check("https://example.com/update.json")
        eq(m.version, "0.1.1")
    end)
end

function tests.http_refuses_plain_http()
    local ok, err = Update.httpGet("http://example.com/update.json", function() return function() return 1 end end)
    falsy(ok)
    truthy(err:find("HTTPS", 1, true), err)
end

return tests
