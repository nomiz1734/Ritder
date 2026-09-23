"""Runs the shell tests (tests/shell/*.sh) inside the WSL1 distro, on the PC.

    python tools/emulate.py --setup   (once, creates the distro)
    python tests/run_shell_tests.py

They cover package/stock/install.sh, the file swap that launch.sh does before the app
starts. That code cannot be tested from Lua, and it is the part that replaces the running
app's own files, so it is worth exercising.
"""
import glob
import os
import subprocess
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "tools"))
import emulate  # noqa: E402

ROOT = emulate.ROOT
INSTALL_SH = os.path.join(ROOT, "package", "stock", "install.sh")


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8")
    failed = 0
    for path in sorted(glob.glob(os.path.join(ROOT, "tests", "shell", "test_*.sh"))):
        print(f"== {os.path.basename(path)}")
        cmd = f"sh '{emulate.wsl_path(path)}' '{emulate.wsl_path(INSTALL_SH)}'"
        result = subprocess.run(["wsl", "-d", emulate.DISTRO, "--", "/bin/sh", "-c", cmd],
                                capture_output=True, text=True, encoding="utf-8", errors="replace")
        print(result.stdout.rstrip())
        if result.stderr.strip():
            print(result.stderr.rstrip())
        if result.returncode != 0:
            failed += 1
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
