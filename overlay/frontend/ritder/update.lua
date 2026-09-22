--[[--
Ritder over-the-air updates (the device side of docs/OTA-co-che-cap-nhat.md).

Everything here is UI-free so it can run in a forked child process (see
plugins/ritderupdate.koplugin), which keeps the reader responsive during a
download of several tens of MB.

Files, all under the KOReader data dir (`userdata/` next to launch.sh):

    update/package.tar.gz  package being downloaded (removed after install)
    update/staging/        unpack area (removed after install)
    update/backup/         the files the last install replaced (for rollback)
    update/added.txt       files the last install created (removed on rollback)
    update/installing      files are being replaced right now (launch.sh rolls back if it survives)
    update/pending         version waiting for confirmation (the new version ran 10 s)
    update/status          progress of the background job, for the UI

launch.sh reads pending/backup/added.txt to roll back when a fresh update crashes.

@module ritder.update
]]

local ffi = require("ffi")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")

local Update = {
    MAX_REDIRECTS = 8,
    TIMEOUT = 30,
    PACKAGE_NAME = "package.tar.gz",
    -- Paths in a package that must never overwrite the user's data.
    PROTECTED = { "^userdata/", "^userdata$", "^settings%.json$" },
    -- The package must contain these, and `luajit` must be a Linux ARM64 program.
    REQUIRED = { "launch.sh", "reader.lua", "luajit" },
    ARCH_CHECK = "luajit",
}

local build_ok, build_info = pcall(require, "ritder/build_info")
if not build_ok then
    build_info = { version = "0.0.0", update_url = "", koreader_version = "?" }
end
Update.build_info = build_info

-- Paths ------------------------------------------------------------------

function Update.appDir()
    return Update.app_dir or os.getenv("RITDER_DIR") or lfs.currentdir()
end

function Update.workDir()
    if Update.work_dir then return Update.work_dir end
    return require("datastorage"):getDataDir() .. "/update"
end

local function joinPath(a, b) return a .. "/" .. b end

local function exists(path) return lfs.attributes(path, "mode") ~= nil end

local function isDir(path) return lfs.attributes(path, "mode") == "directory" end

local function mkdirP(path)
    if path == "" or isDir(path) then return true end
    local parent = path:match("^(.*)/[^/]+$")
    if parent and parent ~= "" then
        mkdirP(parent)
    end
    return lfs.mkdir(path) or isDir(path)
end

local function rmrf(path)
    local mode = lfs.attributes(path, "mode")
    if not mode then return true end
    if mode == "directory" then
        for name in lfs.dir(path) do
            if name ~= "." and name ~= ".." then
                rmrf(joinPath(path, name))
            end
        end
        return lfs.rmdir(path)
    end
    return os.remove(path)
end

--- Lists regular files under `root` as relative paths ("a/b.lua"), sorted.
local function listFiles(root)
    local out = {}
    local function walk(dir, prefix)
        for name in lfs.dir(dir) do
            if name ~= "." and name ~= ".." then
                local full = joinPath(dir, name)
                local rel = prefix == "" and name or (prefix .. "/" .. name)
                local mode = lfs.attributes(full, "mode")
                if mode == "directory" then
                    walk(full, rel)
                elseif mode == "file" then
                    table.insert(out, rel)
                end
            end
        end
    end
    walk(root, "")
    table.sort(out)
    return out
end

local function readFile(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local data = f:read("*a")
    f:close()
    return data
end

local function writeFile(path, data)
    local f, err = io.open(path, "wb")
    if not f then return nil, err end
    f:write(data)
    f:close()
    return true
end

local function copyFile(src, dst)
    local fin, err = io.open(src, "rb")
    if not fin then return nil, err end
    local fout
    fout, err = io.open(dst, "wb")
    if not fout then
        fin:close()
        return nil, err
    end
    while true do
        local chunk = fin:read(256 * 1024)
        if not chunk then break end
        fout:write(chunk)
    end
    fin:close()
    fout:close()
    return true
end

--- Moves a file, falling back to copy + delete (FAT/exFAT do not always rename over files).
local function moveFile(src, dst)
    if exists(dst) then os.remove(dst) end
    if os.rename(src, dst) then return true end
    local ok, err = copyFile(src, dst)
    if not ok then return nil, err end
    os.remove(src)
    return true
end

Update.util = { mkdirP = mkdirP, rmrf = rmrf, listFiles = listFiles, readFile = readFile, writeFile = writeFile }

-- Versions ---------------------------------------------------------------

function Update.currentVersion()
    return build_info.version
end

--- "v0.10.0-rc1" -> {0, 10, 0, 1}. Every part is read as a number (0 if it has none).
function Update.parseVersion(v)
    v = tostring(v or ""):gsub("^%s*[vV]", "")
    local parts = {}
    for part in v:gmatch("[^%.%-%+]+") do
        table.insert(parts, tonumber(part:match("^%d+")) or 0)
    end
    return parts
end

--- True only when `candidate` is strictly newer than `current`: never offers a downgrade.
function Update.isNewer(candidate, current)
    local a, b = Update.parseVersion(candidate), Update.parseVersion(current)
    for i = 1, math.max(#a, #b) do
        local x, y = a[i] or 0, b[i] or 0
        if x ~= y then return x > y end
    end
    return false
end

--- The manifest URL: settings override (an empty string disables OTA), else the one built in.
function Update.manifestUrl()
    if G_reader_settings and G_reader_settings:has("ritder_update_url") then
        return G_reader_settings:readSetting("ritder_update_url") or ""
    end
    return build_info.update_url or ""
end

-- HTTPS ------------------------------------------------------------------

local function caFile()
    local path = joinPath(Update.appDir(), "data/ca-bundle.crt")
    if exists(path) then return path end
end

local function clockLooksWrong()
    return tonumber(os.date("%Y")) < 2026
end

--- GET `url` over HTTPS, following at most MAX_REDIRECTS redirects, each of which must be HTTPS too.
-- `open_sink` is called once per hop and must return one fresh ltn12 sink (so a redirect body never
-- ends up in the downloaded file). Returns true, or nil + a message for the user.
function Update.httpGet(url, open_sink)
    local cafile = caFile()
    for _ = 0, Update.MAX_REDIRECTS do
        if not url:match("^https://") then
            return nil, "chỉ chấp nhận địa chỉ HTTPS: " .. url
        end
        local https = require("ssl.https")
        https.TIMEOUT = Update.TIMEOUT
        local sink = open_sink()
        local ok, code, headers = https.request{
            url = url,
            method = "GET",
            sink = sink,
            redirect = false,
            headers = { ["user-agent"] = "Ritder/" .. build_info.version },
            verify = cafile and "peer" or "none",
            cafile = cafile,
        }
        if not ok then
            local err = tostring(code)
            if err:find("certificate") and clockLooksWrong() then
                return nil, "đồng hồ của máy đang sai (năm " .. os.date("%Y") .. "), không kiểm tra được chứng chỉ HTTPS"
            end
            return nil, "lỗi mạng: " .. err
        end
        if code == 301 or code == 302 or code == 303 or code == 307 or code == 308 then
            local location = headers and (headers.location or headers.Location)
            if not location then
                return nil, "máy chủ chuyển hướng nhưng không cho địa chỉ mới"
            end
            if not location:match("^%a[%w+.-]*://") then
                -- Relative redirect: resolve against the current URL.
                location = require("socket.url").absolute(url, location)
            end
            url = location
        elseif code == 200 then
            return true
        else
            return nil, "máy chủ trả lỗi HTTP " .. tostring(code)
        end
    end
    return nil, "chuyển hướng quá " .. Update.MAX_REDIRECTS .. " lần"
end

local function decodeJson(text)
    local ok, rapidjson = pcall(require, "rapidjson")
    if ok then
        local decoded_ok, value = pcall(rapidjson.decode, text)
        if decoded_ok then return value end
    end
    -- Pure-Lua fallback (dkjson returns nil + message on bad input).
    local json_ok, dkjson = pcall(require, "dkjson")
    if json_ok then
        local decoded_ok, value = pcall(dkjson.decode, text)
        if decoded_ok then return value end
    end
end

--- Downloads and validates update.json. Returns the manifest table, or nil + a message.
-- The table gets an extra `package_url` field.
function Update.fetchManifest(url)
    url = url or Update.manifestUrl()
    if not url or url == "" then
        return nil, "chưa cấu hình địa chỉ cập nhật (update_url)"
    end
    local ltn12 = require("ltn12")
    local chunks
    local ok, err = Update.httpGet(url, function()
        chunks = {}
        local sink = ltn12.sink.table(chunks) -- (also returns the table: keep only the sink)
        return sink
    end)
    if not ok then return nil, err end
    local manifest = decodeJson(table.concat(chunks))
    if type(manifest) ~= "table" then
        return nil, "update.json không đọc được"
    end
    if type(manifest.version) ~= "string" or manifest.version == "" then
        return nil, "update.json thiếu trường version"
    end
    if type(manifest.sha256) ~= "string" or not manifest.sha256:match("^%x+$") or #manifest.sha256 ~= 64 then
        return nil, "update.json thiếu hoặc sai trường sha256"
    end
    manifest.sha256 = manifest.sha256:lower()
    if type(manifest.url) == "string" and manifest.url ~= "" then
        manifest.package_url = manifest.url
    elseif type(manifest.file) == "string" and manifest.file ~= "" and not manifest.file:find("%.%.") then
        manifest.package_url = url:gsub("[?#].*$", ""):gsub("[^/]*$", "") .. manifest.file
    else
        return nil, "update.json thiếu trường file hoặc url"
    end
    if not manifest.package_url:match("^https://") then
        return nil, "gói cập nhật phải tải qua HTTPS"
    end
    manifest.notes = type(manifest.notes) == "string" and manifest.notes or ""
    manifest.size = tonumber(manifest.size)
    return manifest
end

--- Checks for a newer version. Returns manifest (or false when up to date), or nil + message.
function Update.check(url)
    local manifest, err = Update.fetchManifest(url)
    if not manifest then return nil, err end
    if Update.isNewer(manifest.version, Update.currentVersion()) then
        return manifest
    end
    return false, manifest
end

-- SHA-256 ----------------------------------------------------------------

local libcrypto
local function openCrypto()
    if libcrypto ~= nil then return libcrypto end
    libcrypto = false
    local ok = pcall(ffi.cdef, [[
        typedef struct ritder_evp_md_ctx RITDER_EVP_MD_CTX;
        typedef struct ritder_evp_md RITDER_EVP_MD;
        RITDER_EVP_MD_CTX *EVP_MD_CTX_new(void);
        void EVP_MD_CTX_free(RITDER_EVP_MD_CTX *);
        const RITDER_EVP_MD *EVP_sha256(void);
        int EVP_DigestInit_ex(RITDER_EVP_MD_CTX *, const RITDER_EVP_MD *, void *);
        int EVP_DigestUpdate(RITDER_EVP_MD_CTX *, const void *, size_t);
        int EVP_DigestFinal_ex(RITDER_EVP_MD_CTX *, unsigned char *, unsigned int *);
    ]])
    if ok then
        local loaded, lib = pcall(ffi.loadlib, "crypto", "57")
        if loaded then libcrypto = lib end
    end
    return libcrypto
end

--- SHA-256 of a file as lowercase hex (libcrypto, or the pure-Lua ffi/sha2 as a fallback).
function Update.sha256File(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local lib = openCrypto()
    local hex
    if lib then
        local ctx = lib.EVP_MD_CTX_new()
        lib.EVP_DigestInit_ex(ctx, lib.EVP_sha256(), nil)
        while true do
            local chunk = f:read(1024 * 1024)
            if not chunk then break end
            lib.EVP_DigestUpdate(ctx, chunk, #chunk)
        end
        local md = ffi.new("unsigned char[32]")
        local len = ffi.new("unsigned int[1]")
        lib.EVP_DigestFinal_ex(ctx, md, len)
        lib.EVP_MD_CTX_free(ctx)
        local out = {}
        for i = 0, 31 do out[i + 1] = string.format("%02x", md[i]) end
        hex = table.concat(out)
    else
        local append = require("ffi/sha2").sha256()
        while true do
            local chunk = f:read(1024 * 1024)
            if not chunk then break end
            append(chunk)
        end
        hex = append()
    end
    f:close()
    return hex
end

-- Background job status (child writes, UI reads) -------------------------

function Update.setStatus(state, message)
    local dir = Update.workDir()
    mkdirP(dir)
    writeFile(joinPath(dir, "status"), state .. "\n" .. (message or ""))
end

function Update.readStatus()
    local data = readFile(joinPath(Update.workDir(), "status"))
    if not data then return nil end
    local state, message = data:match("^([^\n]*)\n?(.*)$")
    return state, message
end

function Update.packagePath()
    return joinPath(Update.workDir(), Update.PACKAGE_NAME)
end

-- Download ---------------------------------------------------------------

--- Downloads the package of `manifest` to update/package.tar.gz and checks its SHA-256.
function Update.download(manifest)
    local dir = Update.workDir()
    mkdirP(dir)
    local path = Update.packagePath()
    local ltn12 = require("ltn12")
    local ok, err = Update.httpGet(manifest.package_url, function()
        local file = io.open(path, "wb")
        local sink = ltn12.sink.file(file) -- closes the file at the end
        return sink
    end)
    if not ok then
        os.remove(path)
        return nil, err
    end
    local size = lfs.attributes(path, "size") or 0
    if manifest.size and size ~= manifest.size then
        os.remove(path)
        return nil, string.format("file tải về bị thiếu (%d / %d byte)", size, manifest.size)
    end
    if Update.sha256File(path) ~= manifest.sha256 then
        os.remove(path)
        return nil, "file tải về bị hỏng (sai SHA-256)"
    end
    return path
end

-- Install ----------------------------------------------------------------

--- True when `rel` is a safe relative path inside the package (no absolute path, no "..").
function Update.isSafePath(rel)
    if type(rel) ~= "string" or rel == "" then return false end
    if rel:sub(1, 1) == "/" or rel:find("\\", 1, true) or rel:find("%z") then return false end
    for part in rel:gmatch("[^/]+") do
        if part == ".." then return false end
    end
    return true
end

local function isProtected(rel)
    for _, pattern in ipairs(Update.PROTECTED) do
        if rel:match(pattern) then return true end
    end
    return false
end

--- Unpacks a .tar.gz into `dest`, refusing anything that is not a plain file or directory
-- and any path that would land outside `dest`.
function Update.unpack(archive_path, dest)
    require("ffi/libarchive_h")
    local libarchive = ffi.loadlib("archive", "13")
    local ARCHIVE_WARN = -20
    local ar = ffi.gc(libarchive.archive_read_new(), libarchive.archive_free)
    libarchive.archive_read_support_filter_all(ar)
    libarchive.archive_read_support_format_all(ar)
    if libarchive.archive_read_open_filename(ar, archive_path, 65536) ~= libarchive.ARCHIVE_OK then
        return nil, "không mở được gói cập nhật"
    end
    local entry = ffi.gc(libarchive.archive_entry_new(), libarchive.archive_entry_free)
    local buf_size = 256 * 1024
    local buf = ffi.new("char[?]", buf_size)
    local count = 0
    local result, err = true, nil
    while true do
        local r = libarchive.archive_read_next_header2(ar, entry)
        if r == libarchive.ARCHIVE_EOF then break end
        if r ~= libarchive.ARCHIVE_OK and r ~= ARCHIVE_WARN then
            result, err = nil, "gói cập nhật bị hỏng"
            break
        end
        local rel = ffi.string(libarchive.archive_entry_pathname(entry)):gsub("^%./", ""):gsub("/$", "")
        local filetype = libarchive.archive_entry_filetype(entry)
        if rel ~= "" and rel ~= "." then
            if not Update.isSafePath(rel) then
                result, err = nil, "gói cập nhật chứa đường dẫn không hợp lệ: " .. rel
                break
            end
            local target = joinPath(dest, rel)
            if filetype == libarchive.AE_IFDIR then
                mkdirP(target)
            elseif filetype == libarchive.AE_IFREG then
                mkdirP(target:match("^(.*)/[^/]+$"))
                local out = io.open(target, "wb")
                if not out then
                    result, err = nil, "không ghi được " .. rel
                    break
                end
                while true do
                    local n = tonumber(libarchive.archive_read_data(ar, buf, buf_size))
                    if n < 0 then
                        result, err = nil, "gói cập nhật bị hỏng"
                        break
                    end
                    if n == 0 then break end
                    out:write(ffi.string(buf, n))
                end
                out:close()
                if not result then break end
                count = count + 1
            else
                result, err = nil, "gói cập nhật chứa mục không được phép (link/thiết bị): " .. rel
                break
            end
        end
    end
    libarchive.archive_read_close(ar)
    if not result then return nil, err end
    if count == 0 then return nil, "gói cập nhật rỗng" end
    return count
end

--- True when `path` is a 64-bit little-endian ELF for AArch64 (e_machine 0xB7).
function Update.isArm64Elf(path)
    local f = io.open(path, "rb")
    if not f then return false end
    local head = f:read(20)
    f:close()
    if not head or #head < 20 or head:sub(1, 4) ~= "\127ELF" then return false end
    if head:byte(5) ~= 2 or head:byte(6) ~= 1 then return false end -- ELFCLASS64, little endian
    local machine = head:byte(19) + head:byte(20) * 256
    return machine == 0xB7
end

--- Puts the backed-up files back and removes the ones the install added.
function Update.restoreBackup(app_dir, work_dir)
    local backup = joinPath(work_dir, "backup")
    local added = readFile(joinPath(work_dir, "added.txt")) or ""
    for rel in added:gmatch("[^\n]+") do
        if Update.isSafePath(rel) then os.remove(joinPath(app_dir, rel)) end
    end
    if isDir(backup) then
        for _, rel in ipairs(listFiles(backup)) do
            local dst = joinPath(app_dir, rel)
            mkdirP(dst:match("^(.*)/[^/]+$"))
            moveFile(joinPath(backup, rel), dst)
        end
    end
    rmrf(backup)
    os.remove(joinPath(work_dir, "added.txt"))
end

--- Installs a downloaded package over the app directory.
-- Replaced files go to update/backup, new ones are listed in update/added.txt,
-- and update/pending is written last. Never touches userdata/.
function Update.install(package_path, version)
    local app_dir, work_dir = Update.appDir(), Update.workDir()
    local staging = joinPath(work_dir, "staging")
    rmrf(staging)
    mkdirP(staging)

    local count, err = Update.unpack(package_path, staging)
    if not count then
        rmrf(staging)
        return nil, err
    end
    for _, rel in ipairs(Update.REQUIRED) do
        if not exists(joinPath(staging, rel)) then
            rmrf(staging)
            return nil, "gói cập nhật thiếu " .. rel
        end
    end
    if not Update.isArm64Elf(joinPath(staging, Update.ARCH_CHECK)) then
        rmrf(staging)
        return nil, "gói cập nhật không đúng kiến trúc ARM64"
    end

    -- A previous, confirmed install may have left its backup behind: start clean.
    local backup = joinPath(work_dir, "backup")
    rmrf(backup)
    os.remove(joinPath(work_dir, "added.txt"))
    local added = {}
    local ok = true
    -- While this marker exists the app directory is half old, half new: launch.sh restores
    -- the backup if the install is cut short (power loss, crash).
    writeFile(joinPath(work_dir, "installing"), version)
    for i, rel in ipairs(listFiles(staging)) do
        if not isProtected(rel) then
            local src, dst = joinPath(staging, rel), joinPath(app_dir, rel)
            if exists(dst) then
                local bak = joinPath(backup, rel)
                mkdirP(bak:match("^(.*)/[^/]+$"))
                ok, err = moveFile(dst, bak)
            else
                table.insert(added, rel)
                ok, err = mkdirP(dst:match("^(.*)/[^/]+$")), nil
            end
            if ok then
                ok, err = moveFile(src, dst)
            end
            if not ok then
                err = "không chép được " .. rel .. ": " .. tostring(err)
                break
            end
        end
        -- Keep added.txt current, so a failure half-way can still be undone.
        writeFile(joinPath(work_dir, "added.txt"), table.concat(added, "\n"))
    end
    writeFile(joinPath(work_dir, "added.txt"), table.concat(added, "\n"))
    rmrf(staging)
    if not ok then
        logger.warn("Ritder update: install failed, restoring:", err)
        Update.restoreBackup(app_dir, work_dir)
        os.remove(joinPath(work_dir, "installing"))
        return nil, err
    end
    writeFile(joinPath(work_dir, "pending"), version)
    os.remove(joinPath(work_dir, "installing"))
    os.remove(package_path)
    return true
end

--- The whole background job: download, verify, install. Reports through update/status.
function Update.downloadAndInstall(manifest)
    Update.setStatus("downloading")
    local path, err = Update.download(manifest)
    if not path then
        Update.setStatus("failed", err)
        return nil, err
    end
    Update.setStatus("installing")
    local ok
    ok, err = Update.install(path, manifest.version)
    if not ok then
        Update.setStatus("failed", err)
        return nil, err
    end
    Update.setStatus("done", manifest.version)
    return true
end

-- After restart ----------------------------------------------------------

--- Version installed by the last update and not confirmed yet, if any.
function Update.pendingVersion()
    local data = readFile(joinPath(Update.workDir(), "pending"))
    if data then
        data = data:match("^%s*(.-)%s*$")
        if data ~= "" then return data end
    end
end

--- The new version has run long enough: drop the rollback data.
function Update.confirm()
    local work_dir = Update.workDir()
    os.remove(joinPath(work_dir, "pending"))
    rmrf(joinPath(work_dir, "backup"))
    os.remove(joinPath(work_dir, "added.txt"))
    os.remove(joinPath(work_dir, "status"))
end

return Update
