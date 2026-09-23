-- The whole update path: a real check against GitHub, then unpacking the package this
-- working copy builds and the swap install.sh does at the next start.
-- It overwrites dist/emulator/Ritder with the ARM64 package, so it runs last
-- (tools/emulate.py rebuilds that tree on the next run).
local Update = require("ritder/update")
return {
    { "lua", function()
        local manifest, err = Update.check("https://github.com/nomiz1734/Ritder/releases/latest/download/update.json")
        io.stdout:write("EMU check: " .. tostring(manifest and manifest.version or manifest) ..
            " " .. tostring(err and err.version or err) .. "\n")
    end, 2 },
    { "lua", function()
        local package_path = os.getenv("RITDER_EMU_PACKAGE")
        local work = Update.workDir()
        Update.util.mkdirP(work)
        local copy_err = require("ffi/util").copyFile(package_path, work .. "/package.tar.gz")
        io.stdout:write("EMU copy: " .. tostring(copy_err or "ok") .. "\n")
        local count, err = Update.stage(work .. "/package.tar.gz", "9.9.9")
        io.stdout:write("EMU stage: " .. tostring(count) .. " files, err " .. tostring(err) .. "\n")
        io.stdout:write("EMU ready: " .. tostring(Update.readyVersion()) .. "\n")
        local app = Update.appDir()
        io.stdout:write("EMU app untouched: " .. tostring(io.open(app .. "/reader.lua") ~= nil) .. "\n")
    end, 3 },
    { "shot", "01_unpacked" },
    { "lua", function()
        -- What launch.sh runs before the app starts.
        local app, work = Update.appDir(), Update.workDir()
        local cmd = string.format(
            "cd %q && progdir=%q USERDATA=%q UPD=%q sh -c '. ./install.sh; ritder_install_staged' 2>&1",
            app, app, work:gsub("/update$", ""), work)
        local pipe = io.popen(cmd)
        io.stdout:write("EMU install.sh output: " .. (pipe:read("*a") or ""):gsub("\n", " | ") .. "\n")
        pipe:close()
        io.stdout:write("EMU pending: " .. tostring(Update.pendingVersion()) .. "\n")
        local f = io.open(app .. "/install.sh")
        io.stdout:write("EMU install.sh in place: " .. tostring(f ~= nil) .. "\n")
        if f then f:close() end
        local elf = io.open(app .. "/luajit", "rb")
        local head = elf and elf:read(20) or ""
        if elf then elf:close() end
        io.stdout:write("EMU luajit swapped to ARM64: " ..
            tostring(head:sub(1, 4) == "\127ELF" and head:byte(19) == 0xB7) .. "\n")
    end },
}
