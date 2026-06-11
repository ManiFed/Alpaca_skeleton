#!/usr/bin/env python3
"""
Entry point with auto-restart watchdog.

Usage:
    python main.py          # launches dashboard, restarts on crash or file change
    python src/dashboard.py # single run, no auto-restart
"""

import subprocess
import sys
import time
from pathlib import Path

WATCH = [Path(__file__).parent / "src" / "dashboard.py"]


def _mtimes():
    return {p: p.stat().st_mtime for p in WATCH if p.exists()}


def main():
    print("  NODE v1  —  watching for changes (Ctrl-C to quit)\n")
    stamps = _mtimes()

    while True:
        proc = subprocess.Popen([sys.executable, "src/dashboard.py"])
        try:
            while proc.poll() is None:
                time.sleep(1)
                new = _mtimes()
                if new != stamps:
                    stamps = new
                    print("\n  [watchdog] change detected — restarting…\n")
                    proc.terminate()
                    proc.wait()
                    break
            else:
                code = proc.returncode
                if code == 0:
                    break
                print(f"\n  [watchdog] exited with code {code} — restarting in 2 s…\n")
                time.sleep(2)
        except KeyboardInterrupt:
            proc.terminate()
            proc.wait()
            print("\n  Shutting down.")
            break


if __name__ == "__main__":
    main()
