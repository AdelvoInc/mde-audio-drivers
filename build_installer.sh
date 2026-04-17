#!/bin/bash

# ============================================================
# MixDeskEQ for macOS – Audio Driver Installer Builder
#
# Creates a .pkg installer with selectable components.
# The user can click "Customize" in the installer and
# choose which audio buses to install via checkboxes.
#
# Build requirements:
# - Xcode Command Line Tools (xcode-select --install)
# - Git
#
# End users do NOT need Xcode – they only get the .pkg.
#
# Usage: ./build_installer.sh
# ============================================================

set -e

# ── Configuration ─────────────────────────────────────────

# Instances: "Display Name|internal_suffix"
# The first DEFAULT_SELECTED will be pre-selected in the installer.
INSTANCES=(
    "MixDeskEQ System|system"
    "MixDeskEQ WebRTC|webrtc"
    "MixDeskEQ Mix 3|mix3"
    "MixDeskEQ Mix 4|mix4"
    "MixDeskEQ Mix 5|mix5"
    "MixDeskEQ Mix 6|mix6"
    "MixDeskEQ Mix 7|mix7"
    "MixDeskEQ Mix 8|mix8"
)

TOTAL_INSTANCES=${#INSTANCES[@]}
DEFAULT_SELECTED=2

# Installer metadata
PKG_IDENTIFIER_BASE="io.adelvo.mixdeskeq.bus"
PKG_VERSION="1.0.0"
PKG_TITLE="MixDeskEQ for macOS"
INSTALLER_FILENAME="MixDeskEQ-AudioDrivers-${PKG_VERSION}"

# ── Colors ────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ── Directories ───────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/_build"
REPO_DIR="${BUILD_DIR}/BlackHole"
OUTPUT_DIR="${SCRIPT_DIR}/installer"
RESOURCES_DIR="${BUILD_DIR}/resources"
HAL_RELATIVE="Library/Audio/Plug-Ins/HAL"

echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║   MixDeskEQ for macOS – Installer Builder                ║${NC}"
echo -e "${CYAN}║                                                          ║${NC}"
echo -e "${CYAN}║   Building ${TOTAL_INSTANCES} instances, ${DEFAULT_SELECTED} pre-selected.                ║${NC}"
echo -e "${CYAN}║   User selects components via checkboxes in installer.   ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""

# ── Preflight ─────────────────────────────────────────────
for tool in git xcodebuild pkgbuild productbuild; do
    if ! command -v $tool &>/dev/null; then
        echo -e "${RED}✗ '$tool' not found.${NC}"
        [ "$tool" != "git" ] && echo "  → xcode-select --install"
        exit 1
    fi
    echo -e "${GREEN}✓${NC} $tool"
done

echo ""
echo -e "${BOLD}Building ${TOTAL_INSTANCES} instances:${NC}"
for ((i=0; i<TOTAL_INSTANCES; i++)); do
    IFS='|' read -r name suffix <<< "${INSTANCES[$i]}"
    default=""
    [ $((i+1)) -le $DEFAULT_SELECTED ] && default=" ${GREEN}(pre-selected)${NC}"
    echo -e "  🎧 ${name}${default}"
done
echo ""
read -p "Start build? (y/n): " confirm
[ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && echo "Cancelled." && exit 0

# ── Setup ─────────────────────────────────────────────────
rm -rf "${BUILD_DIR}"
CONFIGS_DIR="${BUILD_DIR}/configs"
mkdir -p "${BUILD_DIR}" "${OUTPUT_DIR}" "${RESOURCES_DIR}" "${CONFIGS_DIR}"

# ── Clone BlackHole ───────────────────────────────────────
echo ""
echo -e "${CYAN}▶ Cloning BlackHole repository...${NC}"
git clone --quiet --depth 1 https://github.com/ExistentialAudio/BlackHole.git "${REPO_DIR}"
echo -e "${GREEN}✓${NC} Repository cloned"

# ── Compile & package instances ───────────────────────────
echo ""
echo -e "${CYAN}▶ Compiling instances...${NC}"

COMPONENT_PKGS=()

for ((i=0; i<TOTAL_INSTANCES; i++)); do
    IFS='|' read -r device_name safe_suffix <<< "${INSTANCES[$i]}"
    num=$((i+1))
    bundle_id="${PKG_IDENTIFIER_BASE}.${safe_suffix}"
    driver_filename="MixDeskEQ_${safe_suffix}.driver"

    echo -e "\n  ${YELLOW}[${num}/${TOTAL_INSTANCES}]${NC} Building \"${device_name}\"..."

    # Config header for this instance (clean way to pass string literals)
    config_header="${CONFIGS_DIR}/config_${safe_suffix}.h"
    cat > "${config_header}" << CONFEOF
#define kDriver_Name "MixDeskEQ_${safe_suffix}"
#define kDevice_Name "${device_name}"
#define kNumber_Of_Channels 2
#define kHas_Driver_Name_Format 0
CONFEOF

    cd "${REPO_DIR}"
    xcodebuild clean -project BlackHole.xcodeproj -configuration Release &>/dev/null 2>&1 || true
    rm -rf build/

    xcodebuild \
        -project BlackHole.xcodeproj \
        -configuration Release \
        PRODUCT_BUNDLE_IDENTIFIER="${bundle_id}" \
        CODE_SIGN_IDENTITY="-" \
        CODE_SIGNING_REQUIRED=NO \
        CODE_SIGNING_ALLOWED=NO \
        DEVELOPMENT_TEAM="" \
        'OTHER_CFLAGS=$(inherited) -include '"${config_header}" \
        &>/dev/null 2>&1

    built_driver=$(find build/Release -name "*.driver" -maxdepth 1 -type d | head -1)
    if [ -z "$built_driver" ] || [ ! -d "$built_driver" ]; then
        echo -e "  ${RED}✗ Build failed${NC}"
        exit 1
    fi

    # Payload for this instance
    inst_payload="${BUILD_DIR}/payload_${safe_suffix}"
    inst_scripts="${BUILD_DIR}/scripts_${safe_suffix}"
    mkdir -p "${inst_payload}/${HAL_RELATIVE}"
    mkdir -p "${inst_scripts}"

    cp -R "$built_driver" "${inst_payload}/${HAL_RELATIVE}/${driver_filename}"

    # Postinstall: restart CoreAudio
    cat > "${inst_scripts}/postinstall" << 'EOF'
#!/bin/bash
killall -9 coreaudiod 2>/dev/null || true
exit 0
EOF
    chmod 755 "${inst_scripts}/postinstall"

    # Build component .pkg
    comp_pkg="${BUILD_DIR}/component_${safe_suffix}.pkg"
    pkgbuild \
        --root "${inst_payload}" \
        --scripts "${inst_scripts}" \
        --identifier "${bundle_id}" \
        --version "${PKG_VERSION}" \
        --install-location "/" \
        "${comp_pkg}" &>/dev/null

    COMPONENT_PKGS+=("${comp_pkg}")
    echo -e "  ${GREEN}✓${NC} \"${device_name}\""
done

# ── Welcome HTML ──────────────────────────────────────────
echo ""
echo -e "${CYAN}▶ Creating installer resources...${NC}"

cat > "${RESOURCES_DIR}/welcome.html" << 'WELCOME_EOF'
<html>
<head><meta charset="utf-8"></head>
<body style="font-family: -apple-system, Helvetica Neue, sans-serif; padding: 20px; line-height: 1.6;">
<h2>MixDeskEQ for macOS</h2>
<p>This installer sets up virtual audio buses that MixDeskEQ uses
for routing audio between applications.</p>

<p><strong>How it works:</strong></p>
<p>Each bus is an independent stereo audio device. Audio sent to a
bus <em>output</em> appears at the <em>input</em> of the same bus
&mdash; like a virtual audio cable.</p>

<p><strong>Example Setup:</strong></p>
<table style="border-collapse: collapse; font-size: 13px; margin: 10px 0;">
<tr style="background: #f0f0f0;">
  <td style="padding: 6px 12px; border: 1px solid #ddd;"><strong>System</strong></td>
  <td style="padding: 6px 12px; border: 1px solid #ddd;">macOS system audio &rarr; MixDeskEQ input</td>
</tr>
<tr>
  <td style="padding: 6px 12px; border: 1px solid #ddd;"><strong>WebRTC</strong></td>
  <td style="padding: 6px 12px; border: 1px solid #ddd;">MixDeskEQ mix &rarr; Browser / video conferencing</td>
</tr>
<tr style="background: #f0f0f0;">
  <td style="padding: 6px 12px; border: 1px solid #ddd;"><strong>Mix 3+</strong></td>
  <td style="padding: 6px 12px; border: 1px solid #ddd;">Additional outputs for OBS, recording, etc.</td>
</tr>
</table>

<p>Click <strong>&ldquo;Customize&rdquo;</strong> to choose how many
buses to install. 2 buses are sufficient for most setups.</p>

<p style="color: #888; font-size: 11px;">Based on BlackHole (GPL-3.0) &middot; MixDeskEQ</p>
</body>
</html>
WELCOME_EOF

# ── Conclusion HTML ───────────────────────────────────────
cat > "${RESOURCES_DIR}/conclusion.html" << 'CONCLUSION_EOF'
<html>
<head><meta charset="utf-8"></head>
<body style="font-family: -apple-system, Helvetica Neue, sans-serif; padding: 20px; line-height: 1.6;">
<h2>Installation Complete</h2>
<p>Your audio buses are now available in:</p>
<ul>
<li><strong>System Settings &rarr; Sound</strong> (selectable as output device)</li>
<li><strong>Audio MIDI Setup</strong> (for verification and configuration)</li>
<li><strong>All audio applications</strong> (as input and output)</li>
<li><strong>MixDeskEQ</strong> (as routing target)</li>
</ul>
<p>You can assign custom names to buses within MixDeskEQ
to keep track of which bus is used for what.</p>
<p><strong>Tip:</strong> Open <em>Audio MIDI Setup</em>
(Applications &rarr; Utilities) to verify that all buses
are displayed correctly.</p>
</body>
</html>
CONCLUSION_EOF

echo -e "${GREEN}✓${NC} Welcome & Conclusion created"

# ── Distribution XML ──────────────────────────────────────
echo -e "${CYAN}▶ Assembling distribution package...${NC}"

DIST_XML="${BUILD_DIR}/distribution.xml"

cat > "${DIST_XML}" << DISTHEAD
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
    <title>${PKG_TITLE}</title>
    <welcome file="welcome.html"/>
    <conclusion file="conclusion.html"/>
    <options customize="allow" require-scripts="false" hostArchitectures="arm64,x86_64"/>
    <domains enable_anywhere="false" enable_currentUserHome="false" enable_localSystem="true"/>
    <choices-outline>
DISTHEAD

for ((i=0; i<TOTAL_INSTANCES; i++)); do
    IFS='|' read -r name suffix <<< "${INSTANCES[$i]}"
    echo "        <line choice=\"${suffix}\"/>" >> "${DIST_XML}"
done

echo "    </choices-outline>" >> "${DIST_XML}"

for ((i=0; i<TOTAL_INSTANCES; i++)); do
    IFS='|' read -r device_name safe_suffix <<< "${INSTANCES[$i]}"
    bundle_id="${PKG_IDENTIFIER_BASE}.${safe_suffix}"

    if [ $((i+1)) -le $DEFAULT_SELECTED ]; then
        start_selected="true"
    else
        start_selected="false"
    fi

    cat >> "${DIST_XML}" << DISTCHOICE
    <choice id="${safe_suffix}"
            title="${device_name}"
            description="Installs the virtual stereo audio device '${device_name}'. Can be used as input and output in all audio applications."
            start_selected="${start_selected}"
            start_enabled="true"
            start_visible="true">
        <pkg-ref id="${bundle_id}"/>
    </choice>
    <pkg-ref id="${bundle_id}" version="${PKG_VERSION}" onConclusion="RequireRestart">component_${safe_suffix}.pkg</pkg-ref>
DISTCHOICE
done

echo "</installer-gui-script>" >> "${DIST_XML}"

productbuild \
    --distribution "${DIST_XML}" \
    --resources "${RESOURCES_DIR}" \
    --package-path "${BUILD_DIR}" \
    "${OUTPUT_DIR}/${INSTALLER_FILENAME}.pkg" &>/dev/null

echo -e "${GREEN}✓${NC} Installer: ${OUTPUT_DIR}/${INSTALLER_FILENAME}.pkg"

# ── Uninstaller ───────────────────────────────────────────
echo ""
echo -e "${CYAN}▶ Building uninstaller...${NC}"

UNINST_SCRIPTS="${BUILD_DIR}/uninstall_scripts"
mkdir -p "${UNINST_SCRIPTS}"

cat > "${UNINST_SCRIPTS}/postinstall" << UNEOF
#!/bin/bash
HAL="/Library/Audio/Plug-Ins/HAL"
UNEOF

for ((i=0; i<TOTAL_INSTANCES; i++)); do
    IFS='|' read -r name suffix <<< "${INSTANCES[$i]}"
    echo "rm -rf \"\${HAL}/MixDeskEQ_${suffix}.driver\"" >> "${UNINST_SCRIPTS}/postinstall"
done

cat >> "${UNINST_SCRIPTS}/postinstall" << 'UNEOF2'
killall -9 coreaudiod 2>/dev/null || true
for id in $(pkgutil --pkgs | grep io.adelvo.mixdeskeq.bus); do
    pkgutil --forget "$id" 2>/dev/null || true
done
exit 0
UNEOF2
chmod 755 "${UNINST_SCRIPTS}/postinstall"

mkdir -p "${BUILD_DIR}/uninstall_resources"
cat > "${BUILD_DIR}/uninstall_resources/welcome.html" << 'UNWELCOME'
<html>
<head><meta charset="utf-8"></head>
<body style="font-family: -apple-system, Helvetica Neue, sans-serif; padding: 20px; line-height: 1.6;">
<h2>MixDeskEQ for macOS &mdash; Uninstall</h2>
<p>This will remove <strong>all</strong> MixDeskEQ audio buses
from your system.</p>
<p>After uninstalling, the devices will no longer be available in
System Settings, Audio MIDI Setup, or any other applications.</p>
<p style="color: #c00;"><strong>Please close all audio applications
including MixDeskEQ before proceeding.</strong></p>
</body>
</html>
UNWELCOME

UNINST_COMP="${BUILD_DIR}/uninstall_component.pkg"
pkgbuild \
    --nopayload \
    --scripts "${UNINST_SCRIPTS}" \
    --identifier "${PKG_IDENTIFIER_BASE}.uninstall" \
    --version "${PKG_VERSION}" \
    "${UNINST_COMP}" &>/dev/null

UNINST_DIST="${BUILD_DIR}/uninstall_distribution.xml"
cat > "${UNINST_DIST}" << UNDIST
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
    <title>MixDeskEQ for macOS – Uninstall</title>
    <welcome file="welcome.html"/>
    <options customize="never" require-scripts="false" hostArchitectures="arm64,x86_64"/>
    <domains enable_anywhere="false" enable_currentUserHome="false" enable_localSystem="true"/>
    <choices-outline>
        <line choice="uninstall"/>
    </choices-outline>
    <choice id="uninstall" visible="false">
        <pkg-ref id="${PKG_IDENTIFIER_BASE}.uninstall"/>
    </choice>
    <pkg-ref id="${PKG_IDENTIFIER_BASE}.uninstall" version="${PKG_VERSION}">uninstall_component.pkg</pkg-ref>
</installer-gui-script>
UNDIST

productbuild \
    --distribution "${UNINST_DIST}" \
    --resources "${BUILD_DIR}/uninstall_resources" \
    --package-path "${BUILD_DIR}" \
    "${OUTPUT_DIR}/${INSTALLER_FILENAME}-Uninstall.pkg" &>/dev/null

echo -e "${GREEN}✓${NC} Uninstaller: ${OUTPUT_DIR}/${INSTALLER_FILENAME}-Uninstall.pkg"

# ── Cleanup ───────────────────────────────────────────────
echo ""
echo -e "${CYAN}▶ Cleaning up...${NC}"
rm -rf "${BUILD_DIR}"

# ── Done ──────────────────────────────────────────────────
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   Build complete! 🎉                                     ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "  📦 ${OUTPUT_DIR}/${INSTALLER_FILENAME}.pkg"
echo "  🗑  ${OUTPUT_DIR}/${INSTALLER_FILENAME}-Uninstall.pkg"
echo ""
echo "  The installer presents to the user:"
echo "    1. Welcome screen with explanation + example setup"
echo "    2. Install type: Standard (System + WebRTC) or Customize"
echo "    3. On \"Customize\": Independent checkboxes for all ${TOTAL_INSTANCES} devices"
echo "    4. Conclusion screen with tips"
echo ""
echo -e "  ${YELLOW}To sign:${NC}"
echo "    productsign --sign \"Developer ID Installer: YOUR NAME\" \\"
echo "      \"${OUTPUT_DIR}/${INSTALLER_FILENAME}.pkg\" \\"
echo "      \"${OUTPUT_DIR}/${INSTALLER_FILENAME}-signed.pkg\""
echo ""
echo -e "  ${YELLOW}To notarize:${NC}"
echo "    xcrun notarytool submit \"${OUTPUT_DIR}/${INSTALLER_FILENAME}-signed.pkg\" \\"
echo "      --apple-id YOUR@EMAIL --team-id TEAM_ID \\"
echo "      --password APP_SPECIFIC_PASSWORD --wait"
echo "    xcrun stapler staple \"${OUTPUT_DIR}/${INSTALLER_FILENAME}-signed.pkg\""
echo ""
