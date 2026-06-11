#!/bin/bash
# Boundless Skies Node Agent — macOS DMG / pkg builder
#
# Usage:  bash build/macos/build_dmg.sh [--sign "Developer ID: ..."]
#
# Prerequisites:
#   pyinstaller (for the bundle)
#   create-dmg  (brew install create-dmg) — or pkgbuild/productbuild for .pkg
#   Xcode command-line tools
#
# Outputs:
#   dist/BoundlessSkiesNode-macOS.dmg   (drag-to-install, casual users)
#   dist/BoundlessSkiesNode-macOS.pkg   (managed deployment, used by Munki/MDM)

set -e
cd "$(dirname "$0")/../.."   # repo root

VERSION=$(python3 -c "print('1.0.0')")    # TODO: read from version.py
APP_NAME="BoundlessSkiesNode"
BUNDLE_DIR="dist/${APP_NAME}.app"
CONTENTS="${BUNDLE_DIR}/Contents"
MACOS_DIR="${CONTENTS}/MacOS"
RESOURCES_DIR="${CONTENTS}/Resources"
BUILD_DIR="build/macos"
DIST_DIR="dist"

SIGN_ID="${1:-}"
if [ "$1" = "--sign" ]; then
    SIGN_ID="$2"
fi

echo "=== Building Boundless Skies Node Agent for macOS v${VERSION} ==="

# ── Step 1: PyInstaller bundle ─────────────────────────────────────────────────
echo "Building PyInstaller bundle..."
pyinstaller build/node_agent.spec --clean --noconfirm

# ── Step 2: Assemble .app bundle ───────────────────────────────────────────────
echo "Assembling .app bundle..."
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

# Move the PyInstaller one-file exe into the .app
cp "dist/${APP_NAME}" "${MACOS_DIR}/${APP_NAME}"
chmod +x "${MACOS_DIR}/${APP_NAME}"

# Info.plist
cat > "${CONTENTS}/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
    "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>org.boundlessskies.nodeagent</string>
    <key>CFBundleName</key>
    <string>Boundless Skies Node Agent</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
EOF

# Supporting files bundled into .app/Contents/Resources
cp "${BUILD_DIR}/com.boundlessskies.nodeagent.plist" "${RESOURCES_DIR}/"
cp "build/config.template.yaml" "${RESOURCES_DIR}/"
[ -f "build/icon.icns" ] && cp "build/icon.icns" "${RESOURCES_DIR}/AppIcon.icns"

# ── Step 3: Code signing ───────────────────────────────────────────────────────
if [ -n "${SIGN_ID}" ]; then
    echo "Code-signing with: ${SIGN_ID}"
    codesign --deep --force --options runtime \
        --sign "${SIGN_ID}" \
        --entitlements "${BUILD_DIR}/entitlements.plist" \
        "${BUNDLE_DIR}"
    echo "Verifying signature..."
    codesign --verify --deep --strict "${BUNDLE_DIR}"
else
    echo "Skipping code signing (pass --sign 'Developer ID: ...' to sign)"
fi

# ── Step 4: Build installer .pkg ───────────────────────────────────────────────
echo "Building .pkg installer..."
PKG_STAGING="${DIST_DIR}/pkg_staging"
mkdir -p "${PKG_STAGING}/Applications"
cp -r "${BUNDLE_DIR}" "${PKG_STAGING}/Applications/"

pkgbuild \
    --root "${PKG_STAGING}" \
    --identifier "org.boundlessskies.nodeagent" \
    --version "${VERSION}" \
    --scripts "${BUILD_DIR}" \
    --install-location "/" \
    "${DIST_DIR}/${APP_NAME}-${VERSION}-macOS-component.pkg"

# Wrap with productbuild for a GUI installer
cat > "${DIST_DIR}/distribution.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="1">
    <title>Boundless Skies Node Agent</title>
    <background file="background.png" alignment="bottomleft" scaling="none"/>
    <welcome file="welcome.html"/>
    <options customize="never" require-scripts="true" rootVolumeOnly="true"/>
    <choices-outline>
        <line choice="default">
            <line choice="org.boundlessskies.nodeagent"/>
        </line>
    </choices-outline>
    <choice id="default"/>
    <choice id="org.boundlessskies.nodeagent" visible="false">
        <pkg-ref id="org.boundlessskies.nodeagent"/>
    </choice>
    <pkg-ref id="org.boundlessskies.nodeagent" version="${VERSION}" onConclusion="none">
        ${APP_NAME}-${VERSION}-macOS-component.pkg
    </pkg-ref>
</installer-gui-script>
EOF

productbuild \
    --distribution "${DIST_DIR}/distribution.xml" \
    --package-path "${DIST_DIR}" \
    --resources "${BUILD_DIR}/resources" \
    "${DIST_DIR}/${APP_NAME}-${VERSION}-macOS.pkg"

# ── Step 5: DMG (drag-to-install) ─────────────────────────────────────────────
echo "Building .dmg..."
if command -v create-dmg &>/dev/null; then
    create-dmg \
        --volname "Boundless Skies Node Agent" \
        --window-pos 200 120 \
        --window-size 600 400 \
        --icon-size 100 \
        --icon "${APP_NAME}.app" 150 190 \
        --hide-extension "${APP_NAME}.app" \
        --app-drop-link 450 190 \
        "${DIST_DIR}/${APP_NAME}-${VERSION}-macOS.dmg" \
        "${BUNDLE_DIR}"
else
    echo "create-dmg not found — install with: brew install create-dmg"
    echo "Skipping .dmg creation (the .pkg is the primary installer)"
fi

echo ""
echo "=== Build complete ==="
echo "  Installer:  ${DIST_DIR}/${APP_NAME}-${VERSION}-macOS.pkg"
[ -f "${DIST_DIR}/${APP_NAME}-${VERSION}-macOS.dmg" ] && \
echo "  DMG:        ${DIST_DIR}/${APP_NAME}-${VERSION}-macOS.dmg"
echo ""
