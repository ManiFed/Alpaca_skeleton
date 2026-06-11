#!/usr/bin/env python3
"""
Boundless Skies Node Agent — cross-platform build script.

Builds the PyInstaller bundle and the platform installer.
Run from the repo root.

Usage:
    python build/build.py                    # build for current platform
    python build/build.py --platform windows # cross-build hints only
    python build/build.py --version 1.2.0
    python build/build.py --clean            # remove dist/ and build cache first

Output:
    Windows  → dist/BoundlessSkiesNode-Setup.exe  (via NSIS)
    macOS    → dist/BoundlessSkiesNode-X.Y.Z-macOS.pkg
    Linux    → dist/BoundlessSkiesNode-linux-x86_64

Requirements:
    pip install pyinstaller
    Windows: NSIS, NSSM binary at build/windows/nssm/nssm.exe
    macOS:   Xcode CLI tools, optionally create-dmg
    Linux:   nothing extra (AppImage optional)
"""

import argparse
import os
import platform
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DIST = ROOT / "dist"
BUILD_CACHE = ROOT / "build" / "__pycache__"


def run(cmd: list, **kwargs):
    print(f"  $ {' '.join(str(c) for c in cmd)}")
    result = subprocess.run(cmd, **kwargs)
    if result.returncode != 0:
        sys.exit(result.returncode)


def clean():
    print("Cleaning build artifacts...")
    for path in [DIST, ROOT / "build" / "BoundlessSkiesNode"]:
        if path.exists():
            shutil.rmtree(path)
            print(f"  removed {path}")


def build_bundle():
    """Run PyInstaller to produce the one-file executable."""
    print("\n=== PyInstaller bundle ===")
    spec = ROOT / "build" / "node_agent.spec"
    run([sys.executable, "-m", "PyInstaller", str(spec),
         "--clean", "--noconfirm"], cwd=ROOT)


def build_windows():
    """Invoke NSIS to build the Windows installer."""
    print("\n=== Windows NSIS installer ===")
    nsis = shutil.which("makensis") or shutil.which("makensis.exe")
    if not nsis:
        print("  WARNING: makensis not found — skipping NSIS installer")
        print("  Install NSIS from https://nsis.sourceforge.io/")
        return
    nsi_script = ROOT / "build" / "windows" / "install.nsi"
    run([nsis, str(nsi_script)], cwd=ROOT)
    installer = DIST / "BoundlessSkiesNode-Setup.exe"
    if installer.exists():
        print(f"\n  Installer: {installer}")


def build_macos():
    """Run the macOS build script."""
    print("\n=== macOS .pkg / .dmg ===")
    script = ROOT / "build" / "macos" / "build_dmg.sh"
    run(["bash", str(script)], cwd=ROOT)


def build_linux():
    """Rename / package the Linux binary."""
    print("\n=== Linux binary ===")
    src = DIST / "BoundlessSkiesNode"
    dest = DIST / "BoundlessSkiesNode-linux-x86_64"
    if src.exists():
        shutil.copy2(src, dest)
        dest.chmod(0o755)
        print(f"  Binary: {dest}")

        # Optionally wrap as AppImage (requires appimagetool)
        appimagetool = shutil.which("appimagetool")
        if appimagetool:
            _build_appimage(dest)
        else:
            print("  (appimagetool not found — skipping AppImage)")
            print("  Install: https://appimage.github.io/appimagetool/")
    else:
        print("  ERROR: PyInstaller output not found at dist/BoundlessSkiesNode")


def _build_appimage(binary: Path):
    """Wrap the binary in an AppImage."""
    print("\n  Building AppImage...")
    appdir = DIST / "BoundlessSkiesNode.AppDir"
    appdir.mkdir(exist_ok=True)

    usr_bin = appdir / "usr" / "bin"
    usr_bin.mkdir(parents=True, exist_ok=True)
    shutil.copy2(binary, usr_bin / "BoundlessSkiesNode")

    # AppRun symlink
    apprun = appdir / "AppRun"
    apprun.write_text(
        '#!/bin/bash\nexec "$(dirname "$0")/usr/bin/BoundlessSkiesNode" "$@"\n')
    apprun.chmod(0o755)

    # Minimal .desktop file
    (appdir / "BoundlessSkiesNode.desktop").write_text(
        "[Desktop Entry]\n"
        "Name=Boundless Skies Node Agent\n"
        "Exec=BoundlessSkiesNode\n"
        "Icon=BoundlessSkiesNode\n"
        "Type=Application\n"
        "Categories=Science;\n"
    )

    # Placeholder icon (1×1 PNG if none exists)
    icon_src = ROOT / "build" / "icon.png"
    if icon_src.exists():
        shutil.copy2(icon_src, appdir / "BoundlessSkiesNode.png")

    appimagetool = shutil.which("appimagetool")
    run([appimagetool, str(appdir),
         str(DIST / "BoundlessSkiesNode-linux-x86_64.AppImage")])


def verify_deps():
    """Check that PyInstaller is available."""
    try:
        import PyInstaller  # noqa: F401
    except ImportError:
        print("ERROR: PyInstaller not installed.")
        print("  pip install pyinstaller")
        sys.exit(1)


def main():
    parser = argparse.ArgumentParser(
        description="Build the Boundless Skies Node Agent installer")
    parser.add_argument("--platform",
                        choices=["windows", "macos", "linux", "auto"],
                        default="auto",
                        help="Target platform (default: auto-detect)")
    parser.add_argument("--clean", action="store_true",
                        help="Remove dist/ before building")
    parser.add_argument("--version", default="",
                        help="Version string to embed (e.g. 1.2.0)")
    parser.add_argument("--bundle-only", action="store_true",
                        help="Only run PyInstaller, skip installer packaging")
    args = parser.parse_args()

    os.chdir(ROOT)

    if args.clean:
        clean()

    verify_deps()

    plat = args.platform
    if plat == "auto":
        plat = {"Windows": "windows", "Darwin": "macos",
                "Linux": "linux"}.get(platform.system(), "linux")

    build_bundle()

    if not args.bundle_only:
        if plat == "windows":
            build_windows()
        elif plat == "macos":
            build_macos()
        elif plat == "linux":
            build_linux()

    print("\n=== Build complete ===")
    if DIST.exists():
        for f in sorted(DIST.iterdir()):
            if f.is_file():
                size_mb = f.stat().st_size / 1_048_576
                print(f"  {f.name:<50s}  {size_mb:6.1f} MB")
    print()


if __name__ == "__main__":
    main()
