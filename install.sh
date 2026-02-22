#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# UO Outlands - Automated macOS Setup (Apple Silicon)
# File: outlands_macons_install.sh
# =============================================================================
# Replicates a tested, working Wine+Sikarugir wrapper environment for
# UO Outlands on a clean Apple Silicon Mac.
#
# Tested on: M4 Pro MacBook Pro, macOS Tahoe (26.x)
# Engine:    WS12WineSikarugir (Wine Sikarugir 10.0)
# Wrapper:   Template 1.0.10
#
# Requirements:
#   - Apple Silicon Mac (M1/M2/M3/M4)
#   - macOS 13 (Ventura) or later
#   - ~10GB free disk space
#   - Internet connection
#
# Usage:
#   chmod +x outlands_macons_install.sh
#   ./outlands_macons_install.sh              # install
#   ./outlands_macons_install.sh --uninstall  # remove game only (wrapper + data)
#   ./outlands_macons_install.sh --purge      # remove everything (game + brew casks + support files)
#
# Compatibility:
#   Written for Bash 3.2 (stock macOS /bin/bash). No associative arrays,
#   no ${var,,}, no mapfile, no |&.
# =============================================================================

# ---------------------
#  Configurable Variables
# ---------------------

# Wrapper name and location
WRAPPER_NAME="outlands"
WRAPPER_DIR="$HOME/Applications/Sikarugir"
WRAPPER_APP="${WRAPPER_DIR}/${WRAPPER_NAME}.app"

# Sikarugir engine -- auto-detected from GitHub, these are fallbacks
FALLBACK_ENGINE_NAME="WS12WineSikarugir10.0_4"
ENGINE_URL_PREFIX="https://github.com/Sikarugir-App/Engines/releases/download/v1.0"
ENGINES_DIR="$HOME/Library/Application Support/Sikarugir/Engines"

# Sikarugir wrapper template -- auto-detected from GitHub, these are fallbacks
FALLBACK_TEMPLATE_VERSION="1.0.10"
TEMPLATE_URL_PREFIX="https://github.com/Sikarugir-App/Wrapper/releases/download/v1.0"
TEMPLATE_DIR="$HOME/Library/Application Support/Sikarugir/Template"

# GitHub API endpoints for auto-detection
GITHUB_API_ENGINES="https://api.github.com/repos/Sikarugir-App/Engines/releases"
GITHUB_API_WRAPPER="https://api.github.com/repos/Sikarugir-App/Wrapper/releases"

# Outlands installer
OUTLANDS_INSTALLER_URL="https://patch.uooutlands.com/download"
OUTLANDS_INSTALLER_NAME="Outlands.exe"
OUTLANDS_INSTALL_PATH="/Program Files (x86)/Ultima Online Outlands"
OUTLANDS_EXE_PATH="${OUTLANDS_INSTALL_PATH}/Outlands.exe"

# Wine prefix .NET packages (order matters)
WINETRICKS_PACKAGES="remove_mono dotnet20sp2 dotnet40 dotnet481"

# Minimum required disk space in GB
MIN_DISK_SPACE_GB=10

# Homebrew taps/casks
BREW_CASK_WINE="wine-stable"
BREW_CASK_SIKARUGIR="Sikarugir-App/sikarugir/sikarugir"

# Logging
LOG_DIR="$HOME/Library/Logs"
LOG_FILE="${LOG_DIR}/outlands_install_$(date +%Y%m%d_%H%M%S).log"

# Timing
START_TIME=$(date +%s)

# ---------------------
#  Color Setup (TTY detection)
# ---------------------

if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    DIM='\033[2m'
    NC='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    CYAN=''
    BOLD=''
    DIM=''
    NC=''
fi

STEP_CURRENT=0
STEP_TOTAL=13

# ---------------------
#  Logging Setup
# ---------------------

mkdir -p "${LOG_DIR}"

# Strip ANSI escape sequences for log file
strip_ansi() {
    # Use sed to remove ANSI escape codes
    sed 's/\x1b\[[0-9;]*m//g'
}

# Duplicate all output to log file (without colors)
exec > >(tee >(strip_ansi >> "${LOG_FILE}"))
exec 2> >(tee >(strip_ansi >> "${LOG_FILE}") >&2)

# ---------------------
#  Output Functions
# ---------------------

log() {
    echo -e "$1"
}

step() {
    STEP_CURRENT=$((STEP_CURRENT + 1))
    echo ""
    echo -e "${BLUE}[${STEP_CURRENT}/${STEP_TOTAL}]${NC} ${CYAN}$1${NC}"
    echo "────────────────────────────────────────"
}

info()    { echo -e "  ${GREEN}✓${NC} $1"; }
warn()    { echo -e "  ${YELLOW}!${NC} $1"; }
error()   { echo -e "  ${RED}✗${NC} $1"; }
die()     { error "$1"; exit 1; }

# ---------------------
#  Utility Functions
# ---------------------

check_command() {
    command -v "$1" >/dev/null 2>&1
}

# Elapsed time formatted as Xm Ys
elapsed() {
    local now
    now=$(date +%s)
    local diff=$((now - START_TIME))
    local mins=$((diff / 60))
    local secs=$((diff % 60))
    if [[ "${mins}" -gt 0 ]]; then
        echo "${mins}m ${secs}s"
    else
        echo "${secs}s"
    fi
}

plist_set_int() {
    local plist="$1" key="$2" value="$3"
    /usr/libexec/PlistBuddy -c "Set :\"${key}\" ${value}" "${plist}" 2>/dev/null \
        || /usr/libexec/PlistBuddy -c "Add :\"${key}\" integer ${value}" "${plist}"
}

plist_set_string() {
    local plist="$1" key="$2" value="$3"
    # Wrap value in escaped quotes so paths with spaces work (e.g., /Program Files (x86)/...)
    /usr/libexec/PlistBuddy -c "Set :\"${key}\" \"${value}\"" "${plist}" 2>/dev/null \
        || /usr/libexec/PlistBuddy -c "Add :\"${key}\" string \"${value}\"" "${plist}"
}

# Download a file with proper error handling
# Usage: download_file URL DEST [DESCRIPTION]
download_file() {
    local url="$1"
    local dest="$2"
    local desc="${3:-file}"

    if ! curl -fL --progress-bar -o "${dest}" "${url}"; then
        die "Failed to download ${desc} from ${url}"
    fi

    # Verify file is not empty
    if [[ ! -s "${dest}" ]]; then
        rm -f "${dest}"
        die "Downloaded ${desc} is empty (0 bytes)"
    fi
}

# Extract a tar archive with verification
# Usage: extract_archive ARCHIVE DEST [STRIP_COMPONENTS]
extract_archive() {
    local archive="$1"
    local dest="$2"
    local strip="${3:-0}"

    local tar_args="-xf"
    if [[ "${strip}" -gt 0 ]]; then
        if ! tar ${tar_args} "${archive}" -C "${dest}" --strip-components="${strip}"; then
            die "Failed to extract ${archive}"
        fi
    else
        if ! tar ${tar_args} "${archive}" -C "${dest}"; then
            die "Failed to extract ${archive}"
        fi
    fi
}

# Run Sikarugir CLI with error checking
sikarugir_cli() {
    local cmd="$1"
    shift
    if ! "${WRAPPER_APP}/Contents/MacOS/Sikarugir" "${cmd}" "$@"; then
        die "Sikarugir command failed: ${cmd} $*"
    fi
}

# Check network connectivity
check_network() {
    if ! curl -fsS --max-time 10 -o /dev/null "https://github.com"; then
        die "No network connectivity. Please check your internet connection."
    fi
}

# Query GitHub API for latest engine name matching WS12WineSikarugir prefix
# Falls back to FALLBACK_ENGINE_NAME on failure
get_latest_engine() {
    local api_response
    local latest

    # Try GitHub API -- unauthenticated rate limit is 60/hr
    if api_response=$(curl -fsS --max-time 15 "${GITHUB_API_ENGINES}" 2>/dev/null); then
        # Extract asset names matching WS12WineSikarugir*.tar.xz, pick latest by version sort
        latest=$(echo "${api_response}" \
            | grep -o '"name":"WS12WineSikarugir[^"]*\.tar\.xz"' \
            | sed 's/"name":"//;s/\.tar\.xz"//' \
            | sort -V \
            | tail -n 1)

        if [[ -n "${latest}" ]]; then
            echo "${latest}"
            return 0
        fi
    fi

    # Fallback -- warn to stderr since stdout is captured by caller
    echo -e "  ${YELLOW}!${NC} GitHub API unavailable or rate-limited, using fallback engine: ${FALLBACK_ENGINE_NAME}" >&2
    echo "${FALLBACK_ENGINE_NAME}"
}

# Query GitHub API for latest template version matching Template- prefix
# Falls back to FALLBACK_TEMPLATE_VERSION on failure
get_latest_template() {
    local api_response
    local latest

    if api_response=$(curl -fsS --max-time 15 "${GITHUB_API_WRAPPER}" 2>/dev/null); then
        latest=$(echo "${api_response}" \
            | grep -o '"name":"Template-[^"]*\.tar\.xz"' \
            | sed 's/"name":"Template-//;s/\.tar\.xz"//' \
            | sort -V \
            | tail -n 1)

        if [[ -n "${latest}" ]]; then
            echo "${latest}"
            return 0
        fi
    fi

    # warn to stderr since stdout is captured by caller
    echo -e "  ${YELLOW}!${NC} GitHub API unavailable or rate-limited, using fallback template: ${FALLBACK_TEMPLATE_VERSION}" >&2
    echo "${FALLBACK_TEMPLATE_VERSION}"
}

# Configure all Info.plist keys for a verified working setup
configure_plist() {
    local plist="$1"

    # --- Integer keys ---
    plist_set_int "${plist}" "D3DMETAL" 1
    plist_set_int "${plist}" "WINEESYNC" 1
    plist_set_int "${plist}" "WINEMSYNC" 1
    plist_set_int "${plist}" "MOLTENVKCX" 1
    plist_set_int "${plist}" "DXVK" 0
    plist_set_int "${plist}" "DXMT" 0
    plist_set_int "${plist}" "D9VK" 0
    plist_set_int "${plist}" "CNC_DDRAW" 0
    plist_set_int "${plist}" "METAL_HUD" 0
    plist_set_int "${plist}" "FASTMATH" 0
    plist_set_int "${plist}" "Debug Mode" 0
    plist_set_int "${plist}" "Disable CPUs" 0
    plist_set_int "${plist}" "Try To Use GPU Info" 0
    plist_set_int "${plist}" "Skip Gecko" 0
    plist_set_int "${plist}" "Skip Mono" 0
    plist_set_int "${plist}" "Symlinks In User Folder" 1
    plist_set_int "${plist}" "Winetricks disable logging" 1
    plist_set_int "${plist}" "Winetricks force" 0
    plist_set_int "${plist}" "Winetricks silent" 1

    # --- String keys ---
    plist_set_string "${plist}" "Program Name and Path" "${OUTLANDS_EXE_PATH}"
    plist_set_string "${plist}" "CFBundleName" "${WRAPPER_NAME}"
    plist_set_string "${plist}" "WINEDEBUG" "-plugplay,+loaddll"
    plist_set_string "${plist}" "Gamma Correction" "default"

    # Symlink paths use single-quoted $HOME intentionally -- Sikarugir resolves
    # the literal string '$HOME' at runtime within the Wine prefix environment.
    plist_set_string "${plist}" 'Symlink Desktop' '$HOME/Desktop'
    plist_set_string "${plist}" 'Symlink Downloads' '$HOME/Downloads'
    plist_set_string "${plist}" 'Symlink My Documents' '$HOME/Documents'
    plist_set_string "${plist}" 'Symlink My Music' '$HOME/Music'
    plist_set_string "${plist}" 'Symlink My Pictures' '$HOME/Pictures'
    plist_set_string "${plist}" 'Symlink My Videos' '$HOME/Movies'
    plist_set_string "${plist}" 'Symlink Templates' '$HOME/Templates'
}

# ---------------------
#  Cleanup Trap
# ---------------------

TMPFILES=()

cleanup() {
    local exit_code=$?
    for f in "${TMPFILES[@]+"${TMPFILES[@]}"}"; do
        if [[ -e "${f}" ]]; then
            rm -rf "${f}"
        fi
    done
    if [[ ${exit_code} -ne 0 ]]; then
        echo ""
        error "Installation failed (exit code ${exit_code}). Check log: ${LOG_FILE}"
    fi
}

trap cleanup EXIT

# ---------------------
#  ASCII Banner
# ---------------------

echo ""
echo -e "${BOLD}${CYAN}"
echo "  ╔═══════════════════════════════════════════════════════════╗"
echo "  ║         UO Outlands - macOS Installer (Apple Silicon)    ║"
echo "  ║         Wine + Sikarugir Automated Setup                 ║"
echo "  ╚═══════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo -e "  ${DIM}Log: ${LOG_FILE}${NC}"

# =============================================================================
#  Uninstall Mode
# =============================================================================

if [[ "${1:-}" == "--uninstall" || "${1:-}" == "--purge" ]]; then
    PURGE=false
    if [[ "${1:-}" == "--purge" ]]; then
        PURGE=true
        echo ""
        echo -e "  ${RED}${BOLD}PURGE MODE${NC} -- will remove game AND brew casks (Wine, Sikarugir)"
    else
        echo ""
        echo -e "  ${YELLOW}${BOLD}UNINSTALL MODE${NC} -- will remove game wrapper and support files"
    fi

    echo ""
    echo "  The following will be removed:"
    echo -e "    ${CYAN}${WRAPPER_APP}${NC}"
    echo -e "    ${CYAN}$HOME/Library/Application Support/Sikarugir${NC}"
    if [[ "${PURGE}" == true ]]; then
        echo -e "    ${CYAN}brew cask: wine-stable${NC}"
        echo -e "    ${CYAN}brew cask: sikarugir${NC}"
    fi
    echo ""
    read -rp "  Are you sure? (y/N): " CONFIRM_UNINSTALL
    if [[ "${CONFIRM_UNINSTALL}" != "y" && "${CONFIRM_UNINSTALL}" != "Y" ]]; then
        echo "  Aborted."
        exit 0
    fi

    echo ""
    if [[ -d "${WRAPPER_APP}" ]]; then
        rm -rf "${WRAPPER_APP}"
        info "Removed wrapper: ${WRAPPER_APP}"
    else
        info "Wrapper not found (already removed?)"
    fi

    if [[ -d "$HOME/Library/Application Support/Sikarugir" ]]; then
        rm -rf "$HOME/Library/Application Support/Sikarugir"
        info "Removed Sikarugir support files"
    fi

    if [[ "${PURGE}" == true ]]; then
        if brew list --cask wine-stable >/dev/null 2>&1; then
            brew uninstall --cask wine-stable
            info "Uninstalled Wine Stable"
        else
            info "Wine Stable not installed"
        fi
        if brew list --cask sikarugir >/dev/null 2>&1; then
            brew uninstall --cask sikarugir
            info "Uninstalled Sikarugir"
        else
            info "Sikarugir not installed"
        fi
    fi

    echo ""
    echo -e "${GREEN}${BOLD} Uninstall complete.${NC}"
    exit 0
fi

# =============================================================================
#  Step 1: Pre-flight Checks
# =============================================================================

step "Pre-flight checks"

# Apple Silicon check
ARCH=$(uname -m)
if [[ "${ARCH}" != "arm64" ]]; then
    die "This script is designed for Apple Silicon (arm64). Detected: ${ARCH}"
fi
info "Apple Silicon (${ARCH}) detected"

# macOS version -- robust parsing with validation
MACOS_VERSION=$(sw_vers -productVersion 2>/dev/null || echo "0.0.0")
MACOS_MAJOR=$(echo "${MACOS_VERSION}" | cut -d. -f1)
if ! [[ "${MACOS_MAJOR}" =~ ^[0-9]+$ ]]; then
    die "Could not determine macOS version (got: ${MACOS_VERSION})"
fi
if [[ "${MACOS_MAJOR}" -lt 13 ]]; then
    die "macOS 13 (Ventura) or later required. Detected: ${MACOS_VERSION}"
fi
info "macOS ${MACOS_VERSION}"

# Check if wrapper already exists (before disk check -- affects severity)
WRAPPER_EXISTS=false
if [[ -d "${WRAPPER_APP}" ]]; then
    WRAPPER_EXISTS=true
    info "Wrapper already exists at: ${WRAPPER_APP}"
fi

# Disk space -- warn only on re-run (everything already installed), die on fresh install
AVAILABLE_GB=$(df -g "$HOME" | awk 'NR==2 {print $4}')
if [[ "${AVAILABLE_GB}" -lt "${MIN_DISK_SPACE_GB}" ]]; then
    if [[ "${WRAPPER_EXISTS}" == true ]]; then
        warn "Low disk space (${AVAILABLE_GB}GB free) but wrapper already exists, continuing..."
    else
        die "Need at least ${MIN_DISK_SPACE_GB}GB free. Available: ${AVAILABLE_GB}GB"
    fi
else
    info "${AVAILABLE_GB}GB disk space available"
fi

# Network connectivity
warn "Checking network connectivity..."
check_network
info "Network connectivity OK"

# =============================================================================
#  Step 2: Rosetta 2
# =============================================================================

step "Installing Rosetta 2"

if /usr/bin/pgrep -x oahd >/dev/null 2>&1; then
    info "Rosetta 2 already installed"
else
    warn "Installing Rosetta 2..."
    /usr/sbin/softwareupdate --install-rosetta --agree-to-license
    info "Rosetta 2 installed"
fi

# =============================================================================
#  Step 3: Homebrew
# =============================================================================

step "Checking Homebrew"

if check_command brew; then
    info "Homebrew found at $(which brew)"
else
    echo ""
    error "Homebrew is not installed."
    echo ""
    echo "  This script needs Homebrew (macOS package manager) to install"
    echo "  Wine (Windows compatibility layer) and Sikarugir (wrapper manager)."
    echo ""
    echo "  Install it from: ${BOLD}https://brew.sh${NC}"
    echo ""
    echo "  Then re-run this script."
    die "Homebrew required. See https://brew.sh"
fi

# =============================================================================
#  Step 4: Wine Stable + Sikarugir
# =============================================================================

step "Installing Wine Stable + Sikarugir"

if brew list --cask "${BREW_CASK_WINE}" >/dev/null 2>&1; then
    info "Wine Stable already installed"
else
    warn "Installing Wine Stable..."
    brew install --cask --no-quarantine "${BREW_CASK_WINE}"
    info "Wine Stable installed"
fi

if brew list --cask sikarugir >/dev/null 2>&1; then
    info "Sikarugir already installed"
else
    warn "Installing Sikarugir..."
    brew install --cask --no-quarantine "${BREW_CASK_SIKARUGIR}"
    info "Sikarugir installed"
fi

# =============================================================================
#  Step 5: Detect Latest Engine + Template
# =============================================================================

step "Detecting latest engine and template versions"

ENGINE_NAME=$(get_latest_engine)
info "Engine: ${ENGINE_NAME}"

TEMPLATE_VERSION=$(get_latest_template)
info "Template: Template-${TEMPLATE_VERSION}"

# Derived URLs and paths
ENGINE_URL="${ENGINE_URL_PREFIX}/${ENGINE_NAME}.tar.xz"
TEMPLATE_URL="${TEMPLATE_URL_PREFIX}/Template-${TEMPLATE_VERSION}.tar.xz"
TEMPLATE_APP="${TEMPLATE_DIR}/Template-${TEMPLATE_VERSION}.app"

# =============================================================================
#  Step 6: Download Engine + Template
# =============================================================================

step "Downloading Sikarugir engine and wrapper template"

mkdir -p "${ENGINES_DIR}"
mkdir -p "${TEMPLATE_DIR}"

ENGINE_ARCHIVE="${ENGINES_DIR}/${ENGINE_NAME}.tar.xz"
if [[ -f "${ENGINE_ARCHIVE}" ]]; then
    info "Engine archive already exists: ${ENGINE_NAME}.tar.xz"
else
    warn "Downloading engine: ${ENGINE_NAME}..."
    download_file "${ENGINE_URL}" "${ENGINE_ARCHIVE}" "engine ${ENGINE_NAME}"
    info "Engine downloaded ($(du -h "${ENGINE_ARCHIVE}" | cut -f1))"
fi

TEMPLATE_ARCHIVE="${TEMPLATE_DIR}/Template-${TEMPLATE_VERSION}.tar.xz"
if [[ -d "${TEMPLATE_APP}" ]]; then
    info "Wrapper template already exists: Template-${TEMPLATE_VERSION}.app"
else
    if [[ ! -f "${TEMPLATE_ARCHIVE}" ]]; then
        warn "Downloading wrapper template: Template-${TEMPLATE_VERSION}..."
        download_file "${TEMPLATE_URL}" "${TEMPLATE_ARCHIVE}" "template ${TEMPLATE_VERSION}"
    fi
    warn "Extracting template..."
    extract_archive "${TEMPLATE_ARCHIVE}" "${TEMPLATE_DIR}"
    if [[ ! -d "${TEMPLATE_APP}" ]]; then
        die "Template extraction succeeded but ${TEMPLATE_APP} not found"
    fi
    info "Template extracted"
fi

# =============================================================================
#  Step 7: Create Wrapper
# =============================================================================

step "Creating wrapper: ${WRAPPER_NAME}.app"

WRAPPER_WINE_DIR="${WRAPPER_APP}/Contents/SharedSupport/wine"

if [[ "${WRAPPER_EXISTS}" == true ]] && [[ -d "${WRAPPER_WINE_DIR}/bin" ]]; then
    info "Wrapper already complete with engine, skipping creation"
else
    mkdir -p "${WRAPPER_DIR}"

    if [[ -d "${WRAPPER_APP}" ]]; then
        warn "Wrapper exists but incomplete, rebuilding..."
        rm -rf "${WRAPPER_APP}"
    fi

    cp -a "${TEMPLATE_APP}" "${WRAPPER_APP}"
    info "Wrapper created from template"

    # Inject engine into wrapper
    if [[ ! -d "${WRAPPER_WINE_DIR}/bin" ]]; then
        warn "Injecting engine into wrapper..."
        mkdir -p "${WRAPPER_WINE_DIR}"
        # Engine archive contains wswine.bundle/ prefix -- strip it
        extract_archive "${ENGINE_ARCHIVE}" "${WRAPPER_WINE_DIR}" 1
        if [[ ! -d "${WRAPPER_WINE_DIR}/bin" ]]; then
            die "Engine injection failed: ${WRAPPER_WINE_DIR}/bin not found"
        fi
        info "Engine injected: $(cat "${WRAPPER_WINE_DIR}/version" 2>/dev/null || echo "${ENGINE_NAME}")"
    fi

    # Create symlinks expected by Sikarugir
    WRAPPER_CONTENTS="${WRAPPER_APP}/Contents"
    if [[ ! -L "${WRAPPER_CONTENTS}/Logs" ]]; then
        ln -sf SharedSupport/Logs "${WRAPPER_CONTENTS}/Logs"
    fi
    if [[ ! -L "${WRAPPER_CONTENTS}/drive_c" ]]; then
        ln -sf SharedSupport/prefix/drive_c "${WRAPPER_CONTENTS}/drive_c"
    fi
    info "Wrapper symlinks created"

    # Remove quarantine attribute from wrapper
    xattr -drs com.apple.quarantine "${WRAPPER_APP}" 2>/dev/null || true
    info "Quarantine attribute removed from wrapper"
fi

# =============================================================================
#  Step 8: Configure Info.plist
# =============================================================================

step "Configuring wrapper (Info.plist)"

PLIST="${WRAPPER_APP}/Contents/Info.plist"

# Preserve existing bundle ID on re-run, generate new one only for fresh wrapper
EXISTING_BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "${PLIST}" 2>/dev/null || echo "")
if [[ -n "${EXISTING_BUNDLE_ID}" ]] && [[ "${EXISTING_BUNDLE_ID}" == com.sikarugir.${WRAPPER_NAME}.* ]]; then
    BUNDLE_ID="${EXISTING_BUNDLE_ID}"
    info "Bundle ID preserved: ${BUNDLE_ID}"
else
    BUNDLE_UUID=$(uuidgen | tr '[:upper:]' '[:lower:]' | cut -d- -f1)
    BUNDLE_ID="com.sikarugir.${WRAPPER_NAME}.${BUNDLE_UUID}"
    plist_set_string "${PLIST}" "CFBundleIdentifier" "${BUNDLE_ID}"
    info "Bundle ID: ${BUNDLE_ID}"
fi

# Apply all plist configuration (idempotent -- safe to re-apply)
configure_plist "${PLIST}"

info "D3DMETAL enabled (critical for game stability)"
info "WINEESYNC + WINEMSYNC enabled"
info "Launch target: ${OUTLANDS_EXE_PATH}"
info "WINEDEBUG: -plugplay,+loaddll"

# =============================================================================
#  Step 9: Initialize Wine Prefix
# =============================================================================

step "Initializing Wine prefix"

WRAPPER_PREFIX="${WRAPPER_APP}/Contents/SharedSupport/prefix"
if [[ ! -d "${WRAPPER_PREFIX}/drive_c/windows" ]]; then
    warn "Running wineboot to create prefix (this may take a minute)..."
    sikarugir_cli WSS-wineprefixcreate
    if [[ ! -d "${WRAPPER_PREFIX}/drive_c/windows" ]]; then
        die "Wine prefix creation failed: ${WRAPPER_PREFIX}/drive_c/windows not found"
    fi
    info "Wine prefix created"
else
    info "Wine prefix already exists"
fi

# Remove .ttc font entries from Wine registry -- SixLabors.Fonts cannot parse
# TrueType Collection files and ClassicUO crashes with "Table 'name' is missing"
for _reg in "${WRAPPER_PREFIX}/system.reg" "${WRAPPER_PREFIX}/user.reg"; do
    if [[ -f "${_reg}" ]] && grep -q '\.ttc"' "${_reg}" 2>/dev/null; then
        sed -i '' '/\.ttc"$/d' "${_reg}"
    fi
done
info "Wine registry cleaned (removed .ttc font entries)"

# Install Windows core fonts from macOS system into Wine prefix
WINE_FONTS_DIR="${WRAPPER_PREFIX}/drive_c/windows/Fonts"
mkdir -p "${WINE_FONTS_DIR}"
FONT_COUNT=0
for _f in "${WINE_FONTS_DIR}"/*.ttf; do
    [[ -f "${_f}" ]] && FONT_COUNT=$((FONT_COUNT + 1))
done
if [[ "${FONT_COUNT}" -ge 10 ]]; then
    info "Core fonts already installed (${FONT_COUNT} .ttf files)"
else
    MACOS_FONTS="/System/Library/Fonts/Supplemental"
    FONTS_COPIED=0
    if [[ -d "${MACOS_FONTS}" ]]; then
        for pattern in "Arial" "Courier New" "Times New Roman" "Georgia" "Verdana" "Tahoma" "Trebuchet MS" "Comic Sans" "Impact" "Webdings"; do
            for f in "${MACOS_FONTS}/${pattern}"*.ttf; do
                [[ -f "${f}" ]] && cp "${f}" "${WINE_FONTS_DIR}/" 2>/dev/null && FONTS_COPIED=$((FONTS_COPIED + 1))
            done
        done
    fi
    if [[ "${FONTS_COPIED}" -gt 0 ]]; then
        info "Copied ${FONTS_COPIED} core fonts from macOS system"
    else
        warn "No macOS system fonts found, game may have font issues"
    fi
fi

# =============================================================================
#  Step 10: Install .NET Runtimes
# =============================================================================

step "Installing .NET runtimes via winetricks"

# Check .NET installation by looking for actual DLL files, not just directories
# (wineboot creates empty Framework dirs without real .NET installed)
DOTNET_DIR="${WRAPPER_PREFIX}/drive_c/windows/Microsoft.NET/Framework"
DOTNET_INSTALLED=false
if [[ -f "${DOTNET_DIR}/v2.0.50727/mscorlib.dll" ]] && [[ -f "${DOTNET_DIR}/v4.0.30319/mscorlib.dll" ]]; then
    DOTNET_INSTALLED=true
fi

if [[ "${DOTNET_INSTALLED}" == true ]]; then
    info ".NET already installed (v2.0 + v4.0 mscorlib.dll found)"
else
    for pkg in ${WINETRICKS_PACKAGES}; do
        warn "Installing ${pkg} (this may take several minutes)..."
        # Retry once on failure
        if ! "${WRAPPER_APP}/Contents/MacOS/Sikarugir" WSS-winetricks "${pkg}"; then
            warn "Retrying ${pkg}..."
            if ! "${WRAPPER_APP}/Contents/MacOS/Sikarugir" WSS-winetricks "${pkg}"; then
                die "Failed to install ${pkg} via winetricks after retry"
            fi
        fi
        info "${pkg} installed"
    done
fi

# Set Windows version to XP after .NET installs (matches working config)
# Check registry for current Windows version
WINXP_SET=false
SYSTEM_REG="${WRAPPER_PREFIX}/system.reg"
if [[ -f "${SYSTEM_REG}" ]] && grep -q '"ProductName"="Microsoft Windows XP"' "${SYSTEM_REG}" 2>/dev/null; then
    WINXP_SET=true
fi

if [[ "${WINXP_SET}" == true ]]; then
    info "Windows XP mode already set"
else
    warn "Setting Windows version to XP..."
    sikarugir_cli WSS-winetricks winxp
    info "Windows XP mode set"
fi

# =============================================================================
#  Step 11: Install UO Outlands
# =============================================================================

step "Installing UO Outlands"

DRIVE_C="${WRAPPER_PREFIX}/drive_c"
OUTLANDS_DIR="${DRIVE_C}${OUTLANDS_INSTALL_PATH}"
OUTLANDS_EXE="${OUTLANDS_DIR}/Outlands.exe"

if [[ -f "${OUTLANDS_EXE}" ]]; then
    info "Outlands already installed at: ${OUTLANDS_INSTALL_PATH}"
else
    # Outlands.exe is a self-patching launcher -- download directly into the prefix.
    # It will download game files on first run inside Wine.
    mkdir -p "${OUTLANDS_DIR}"

    warn "Downloading Outlands launcher..."
    download_file "${OUTLANDS_INSTALLER_URL}" "${OUTLANDS_EXE}" "Outlands launcher"

    if [[ -f "${OUTLANDS_EXE}" ]]; then
        info "Outlands.exe placed at: ${OUTLANDS_INSTALL_PATH} ($(du -h "${OUTLANDS_EXE}" | cut -f1))"
    else
        die "Failed to place Outlands.exe at: ${OUTLANDS_INSTALL_PATH}"
    fi
fi

# =============================================================================
#  Step 12: Fix Wine audio (SDL3 + CoreAudio)
# =============================================================================

step "Configuring audio (SDL3 DirectSound fix)"

# ClassicUO uses FAudio → SDL3 → Wine WASAPI → CoreAudio. Wine's WASAPI
# implementation has buffering issues with CoreAudio, causing crackling on
# USB audio devices. Switching SDL3 to DirectSound backend avoids this.
#
# These env vars must be set BEFORE Sikarugir launches (Sikarugir doesn't
# pass arbitrary plist keys as env vars). A LaunchAgent sets them at login.
LAUNCH_AGENT_ID="com.sikarugir.${WRAPPER_NAME}.audio"
LAUNCH_AGENT_DIR="$HOME/Library/LaunchAgents"
LAUNCH_AGENT_PLIST="${LAUNCH_AGENT_DIR}/${LAUNCH_AGENT_ID}.plist"

mkdir -p "${LAUNCH_AGENT_DIR}"

cat > "${LAUNCH_AGENT_PLIST}" << PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>${LAUNCH_AGENT_ID}</string>
	<key>ProgramArguments</key>
	<array>
		<string>/bin/launchctl</string>
		<string>setenv</string>
		<string>SDL_AUDIODRIVER</string>
		<string>directsound</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
</dict>
</plist>
PLISTEOF

info "LaunchAgent created: ${LAUNCH_AGENT_PLIST}"

# Also set it for the current session
launchctl setenv SDL_AUDIODRIVER directsound 2>/dev/null || true
launchctl setenv SDL_AUDIO_DEVICE_SAMPLE_FRAMES 4096 2>/dev/null || true
info "SDL_AUDIODRIVER=directsound set for current session"

# =============================================================================
#  Step 13: Finishing Up
# =============================================================================

step "Finishing up"

# --- Final Summary ---
ELAPSED=$(elapsed)

echo ""
echo "════════════════════════════════════════════════════════════════"
echo -e "${GREEN}${BOLD} Setup Complete!${NC}  ${DIM}(${ELAPSED})${NC}"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo -e "  Wrapper:    ${CYAN}${WRAPPER_APP}${NC}"
echo -e "  Engine:     ${CYAN}${ENGINE_NAME}${NC}"
echo -e "  Template:   ${CYAN}Template-${TEMPLATE_VERSION}${NC}"
echo -e "  D3DMetal:   ${GREEN}Enabled${NC}"
echo -e "  .NET:       ${GREEN}${WINETRICKS_PACKAGES}${NC}"
echo -e "  Log:        ${DIM}${LOG_FILE}${NC}"
echo ""
echo -e "  ${BOLD}How to launch:${NC}"
echo "    Double-click ${WRAPPER_NAME}.app in ${WRAPPER_DIR}"
echo ""
echo -e "  ${BOLD}Audio:${NC}"
echo "    SDL_AUDIODRIVER=directsound (fixes CoreAudio crackling)"
echo "    Set via LaunchAgent, persists across reboots."
echo "    Wine does NOT hot-switch audio devices -- connect"
echo "    AirPods/headphones BEFORE launching the game."
echo ""
echo -e "  ${BOLD}Tips:${NC}"
echo "    - Switch Razor/Game windows: Cmd+\` (backtick)"
echo "    - Reconfigure wrapper: Right-click ${WRAPPER_NAME}.app"
echo "        -> Show Package Contents -> Configure.app"
echo "    - Razor profiles: drive_c/users/crossover/Application Data/Razor/"
echo "    - Game logs: drive_c${OUTLANDS_INSTALL_PATH}/Logs/"
echo "    - If game won't start, try running wrapper from Terminal:"
echo "        open \"${WRAPPER_APP}\""
echo ""
echo -e "  ${BOLD}Uninstall:${NC}"
echo "    ./outlands_macons_install.sh --uninstall  # remove game only"
echo "    ./outlands_macons_install.sh --purge      # remove everything + brew casks"
echo ""
echo "════════════════════════════════════════════════════════════════"
