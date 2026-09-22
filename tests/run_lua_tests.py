"""Runs the Lua unit tests in tests/lua against dist/Ritder, on the PC.

    pip install lupa          (embeds LuaJIT; no Linux or device needed)
    python tools/build.py     (tests use the assembled tree)
    python tests/run_lua_tests.py

KOReader's C modules do not exist here, so the few the tested code needs are stubbed:
`libs/libkoreader-lfs` is backed by Python's os module, `logger` just records.
libarchive is not available either: the tests replace Update.unpack with a tarfile-based
implementation that applies the same path rules.
"""
import glob
import os
import sys
import tarfile

from lupa import luajit21

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIST = os.path.join(ROOT, "dist", "Ritder")


def lfs_attributes(path, key=None):
    try:
        st = os.stat(path)
    except OSError:
        return None
    attrs = {"mode": "directory" if os.path.isdir(path) else "file", "size": st.st_size}
    return attrs[key] if key else attrs


def py_unpack(archive, dest):
    """Same contract as Update.unpack: returns count, or (None, message)."""
    count = 0
    with tarfile.open(archive, "r:*") as tar:
        for m in tar.getmembers():
            rel = m.name[2:] if m.name.startswith("./") else m.name
            rel = rel.rstrip("/")
            if not rel or rel == ".":
                continue
            if rel.startswith("/") or ".." in rel.split("/"):
                return None, "gói cập nhật chứa đường dẫn không hợp lệ: " + rel
            target = os.path.join(dest, rel)
            if m.isdir():
                os.makedirs(target, exist_ok=True)
            elif m.isfile():
                os.makedirs(os.path.dirname(target), exist_ok=True)
                with tar.extractfile(m) as src, open(target, "wb") as out:
                    out.write(src.read())
                count += 1
            else:
                return None, "gói cập nhật chứa mục không được phép (link/thiết bị): " + rel
    if count == 0:
        return None, "gói cập nhật rỗng"
    return count


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8")
    if not os.path.isdir(DIST):
        print("dist/Ritder is missing: run python tools/build.py first")
        return 1
    lua = luajit21.LuaRuntime(unpack_returned_tuples=True)
    g = lua.globals()
    g.py_lfs_attributes = lfs_attributes
    g.py_listdir = lambda path: lua.table_from([".", ".."] + sorted(os.listdir(path)))
    g.py_mkdir = lambda path: (os.mkdir(path) or True) if not os.path.exists(path) else None
    g.py_rmdir = lambda path: (os.rmdir(path) or True)
    g.py_cwd = os.getcwd
    g.py_unpack = py_unpack
    g.py_tmpdir = lambda: __import__("tempfile").mkdtemp(prefix="ritder-test-").replace("\\", "/")
    g.py_make_tar = make_tar
    g.DIST = DIST.replace("\\", "/")
    g.TESTS = os.path.join(ROOT, "tests", "lua").replace("\\", "/")

    lua.execute(r"""
        package.path = TESTS .. "/?.lua;" .. DIST .. "/frontend/?.lua;" .. DIST .. "/?.lua;"
            .. DIST .. "/common/?.lua;" .. package.path
        package.preload["libs/libkoreader-lfs"] = function()
            return {
                attributes = function(path, key) return py_lfs_attributes(path, key) end,
                dir = function(path)
                    local names, i = py_listdir(path), 0
                    return function() i = i + 1; return names[i] end
                end,
                mkdir = function(path) return py_mkdir(path) end,
                rmdir = function(path) return py_rmdir(path) end,
                currentdir = function() return py_cwd() end,
            }
        end
        -- KOReader's FFI headers refuse to load on Windows: declare just what the tested code uses.
        package.preload["ffi/posix_h"] = function()
            require("ffi").cdef[[
                struct timeval { long long tv_sec; long long tv_usec; };
                struct pollfd { int fd; short events; short revents; };
            ]]
        end
        package.preload["ffi/linux_input_h"] = function()
            require("ffi").cdef[[
                struct input_event { struct timeval time; uint16_t type; uint16_t code; int32_t value; };
            ]]
        end
        LOG = {}
        package.preload["logger"] = function()
            local function rec(...) table.insert(LOG, table.concat({...}, " ")) end
            return { info = rec, warn = rec, dbg = function() end, err = rec }
        end
    """)
    failures = 0
    total = 0
    for path in sorted(glob.glob(os.path.join(ROOT, "tests", "lua", "test_*.lua"))):
        name = os.path.basename(path)
        with open(path, encoding="utf-8") as f:
            suite = lua.execute(f.read())
        for test_name in sorted(suite.keys()):
            total += 1
            try:
                suite[test_name]()
                print(f"  ok    {name}: {test_name}")
            except Exception as e:  # noqa: BLE001 - report and continue
                failures += 1
                print(f"  FAIL  {name}: {test_name}\n        {e}")
    print(f"{total - failures}/{total} passed")
    return 1 if failures else 0


def elf_stub(machine: int) -> bytes:
    head = bytearray(64)
    head[0:4] = b"ELF"
    head[4], head[5], head[6] = 2, 1, 1  # 64-bit, little endian, version 1
    head[18] = machine & 0xFF
    head[19] = machine >> 8
    return bytes(head)


# Placeholders the Lua tests use for binary content (Lua strings cross over as UTF-8 text).
ELF_STUBS = {"@ELF_ARM64": elf_stub(0xB7), "@ELF_X86_64": elf_stub(0x3E)}


def make_tar(path, entries):
    """entries: Lua table {name = content | {link = target}}."""
    import io

    with tarfile.open(path, "w:gz") as tar:
        for name in sorted(entries.keys()):
            value = entries[name]
            info = tarfile.TarInfo(name)
            if isinstance(value, str):
                data = ELF_STUBS.get(value) or value.encode("utf-8")
                info.size = len(data)
                tar.addfile(info, io.BytesIO(data))
            else:
                info.type = tarfile.SYMTYPE
                info.linkname = value["link"]
                tar.addfile(info)


if __name__ == "__main__":
    sys.exit(main())
