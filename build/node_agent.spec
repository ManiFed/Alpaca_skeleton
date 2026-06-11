# -*- mode: python ; coding: utf-8 -*-
#
# Boundless Skies Node Agent — PyInstaller spec
#
# Build the one-file bundle:
#   pyinstaller build/node_agent.spec
#
# Output:  dist/BoundlessSkiesNode[.exe]
#
# Requirements:
#   pip install pyinstaller
#   (All runtime deps must be installed in the active venv)

import os
import sys
from pathlib import Path

ROOT = Path(SPECPATH).parent          # repo root (build/ is one level down)
ENTRY = ROOT / "main_service.py"

block_cipher = None

# ── Hidden imports ─────────────────────────────────────────────────────────────
# PyInstaller cannot detect all dynamic imports.  List everything we know is
# used at runtime but not found by static analysis.

hidden_imports = [
    # astropy sub-packages loaded dynamically
    "astropy.wcs",
    "astropy.io.fits",
    "astropy.coordinates",
    "astropy.time",
    "astropy.units",
    "astropy.wcs.utils",

    # numpy extension modules
    "numpy.core._methods",
    "numpy.lib.format",

    # Flask internals
    "flask",
    "werkzeug",
    "werkzeug.serving",
    "werkzeug.debug",
    "jinja2",
    "click",

    # PIL / Pillow
    "PIL",
    "PIL.Image",
    "PIL.ImageDraw",

    # requests / urllib3 / certifi
    "requests",
    "urllib3",
    "certifi",
    "charset_normalizer",
    "idna",

    # PyYAML
    "yaml",

    # Local packages
    "alpaca",
    "alpaca.telescope",
    "alpaca.camera",
    "alpaca.focuser",
    "alpaca.autofocus",
    "alpaca.filterwheel",
    "alpaca.platesolve",
    "alpaca.safety_manager",
    "alpaca.device_manager",
    "alpaca.discovery",
    "alpaca.covercalibrator",
    "alpaca.client",

    # Other local modules
    "shared_models",
    "photometry",
    "stacking",
    "image_watcher",
    "cloud_communicator",
    "aavso_submission",
    "fits_export",
    "geolocation",
    "sleep_prevention",

    # pyongc
    "pyongc",

    # scipy (may be pulled in by astropy)
    "scipy",
    "scipy.ndimage",
    "scipy.optimize",

    # Standard library modules that PyInstaller sometimes misses
    "logging.handlers",
    "email.mime.text",
    "email.mime.multipart",
]

# ── Data files ─────────────────────────────────────────────────────────────────
# Tuples: (source_path, dest_directory_in_bundle)

datas = [
    # pyongc database
    (str(ROOT / "venv" / "lib" / "python*" / "site-packages" / "pyongc" / "ongc.db"),
     "pyongc"),

    # Config template — installer writes the real config; this is the fallback
    (str(ROOT / "build" / "config.template.yaml"), "."),

    # ASTAP is a separate binary; we ship a reference, not the binary itself.
    # Members install ASTAP separately.  See README.
]

# ── Analysis ───────────────────────────────────────────────────────────────────

a = Analysis(
    [str(ENTRY)],
    pathex=[str(ROOT)],
    binaries=[],
    datas=datas,
    hiddenimports=hidden_imports,
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[
        # Exclude heavy packages we don't use
        "tkinter",
        "matplotlib",
        "IPython",
        "jupyter",
        "notebook",
        "pandas",
        "sympy",
    ],
    win_no_prefer_redirects=False,
    win_private_assemblies=False,
    cipher=block_cipher,
    noarchive=False,
)

pyz = PYZ(a.pure, a.zipped_data, cipher=block_cipher)

# ── One-file exe ───────────────────────────────────────────────────────────────

exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.zipfiles,
    a.datas,
    [],
    name="BoundlessSkiesNode",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    upx_exclude=[],
    runtime_tmpdir=None,
    console=True,          # Keep console for log output; Windows Service wrapper hides it
    disable_windowed_traceback=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
    icon=str(ROOT / "build" / "icon.ico") if (ROOT / "build" / "icon.ico").exists() else None,
)
