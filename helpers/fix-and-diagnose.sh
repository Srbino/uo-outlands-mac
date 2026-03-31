#!/usr/bin/env bash
# =============================================================================
# UO Outlands - Complete Fix & Diagnostic Script
# Fixes known issues, then validates everything
# =============================================================================

set -uo pipefail

WRAPPER_APP="$HOME/Applications/Sikarugir/outlands.app"
WRAPPER_PREFIX="${WRAPPER_APP}/Contents/SharedSupport/prefix"
WRAPPER_WINE="${WRAPPER_APP}/Contents/SharedSupport/wine"
PLIST="${WRAPPER_APP}/Contents/Info.plist"
OUTLANDS_EXE="${WRAPPER_PREFIX}/drive_c/Program Files (x86)/Ultima Online Outlands/Outlands.exe"
WINE_STABLE_LIB="/Applications/Wine Stable.app/Contents/Resources/wine/lib"
ENGINE_LIB="${WRAPPER_WINE}/lib"

PASS=0
FAIL=0
WARN=0
FIXED=0

ok()    { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail()  { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }
warn()  { echo "  ! $1"; WARN=$((WARN + 1)); }
fixed() { echo "  ⚡ FIXED: $1"; FIXED=$((FIXED + 1)); }

echo ""
echo "========================================"
echo " UO Outlands - Fix & Diagnose"
echo " $(date)"
echo "========================================"

# ==========================================================
echo ""
echo "[1] System Info"
echo "────────────────────────────────────────"
echo "  macOS:     $(sw_vers -productVersion)"
echo "  Build:     $(sw_vers -buildVersion)"
echo "  Arch:      $(uname -m)"
echo "  Bash:      ${BASH_VERSION}"
echo "  User:      $(whoami)"
echo "  Home:      ${HOME}"
echo "  Locale:    ${LANG:-not set}"
echo "  Disk free: $(df -g "$HOME" | awk 'NR==2 {print $4}')GB"

# ==========================================================
echo ""
echo "[2] Homebrew"
echo "────────────────────────────────────────"
if command -v brew >/dev/null 2>&1; then
    ok "Homebrew: $(brew --version | head -1)"
    echo "  Path: $(which brew)"
else
    fail "Homebrew not found in PATH"
    echo "  PATH: ${PATH}"
fi

for cask in wine-stable sikarugir; do
    if brew list --cask "${cask}" >/dev/null 2>&1; then
        ok "Cask '${cask}' installed"
    else
        fail "Cask '${cask}' NOT installed"
    fi
done

# ==========================================================
echo ""
echo "[3] Rosetta 2"
echo "────────────────────────────────────────"
if /usr/bin/pgrep -x oahd >/dev/null 2>&1; then
    ok "Rosetta 2 running"
else
    fail "Rosetta 2 NOT running"
fi

# ==========================================================
echo ""
echo "[4] Wine Stable.app"
echo "────────────────────────────────────────"
if [[ -d "/Applications/Wine Stable.app" ]]; then
    ok "Wine Stable.app exists"
    # Quarantine check
    QATTR=$(xattr "/Applications/Wine Stable.app" 2>/dev/null | grep -c quarantine || true)
    if [[ "${QATTR}" -gt 0 ]]; then
        warn "Wine Stable.app has quarantine — fixing..."
        xattr -cr "/Applications/Wine Stable.app" 2>/dev/null || true
        fixed "Cleared quarantine on Wine Stable.app"
    else
        ok "Wine Stable.app quarantine clear"
    fi
    # List available dylibs
    if [[ -d "${WINE_STABLE_LIB}" ]]; then
        DYLIB_COUNT=$(find "${WINE_STABLE_LIB}" -name "*.dylib" -maxdepth 1 2>/dev/null | wc -l | tr -d ' ')
        ok "Wine Stable.app has ${DYLIB_COUNT} dylibs available"
    else
        fail "Wine Stable.app lib directory missing: ${WINE_STABLE_LIB}"
    fi
else
    fail "Wine Stable.app NOT found in /Applications"
fi

# ==========================================================
echo ""
echo "[5] Wrapper Structure"
echo "────────────────────────────────────────"
if [[ -d "${WRAPPER_APP}" ]]; then
    ok "Wrapper: ${WRAPPER_APP}"
else
    fail "Wrapper NOT found: ${WRAPPER_APP}"
    echo ""
    echo "  Cannot continue without wrapper. Run install.sh first."
    echo "========================================"
    exit 1
fi

if [[ -f "${PLIST}" ]]; then
    ok "Info.plist exists"
else
    fail "Info.plist NOT found"
fi

if [[ -x "${WRAPPER_APP}/Contents/MacOS/Sikarugir" ]]; then
    ok "Sikarugir binary executable"
else
    fail "Sikarugir binary not executable"
fi

# Quarantine on wrapper
QATTR_W=$(xattr "${WRAPPER_APP}" 2>/dev/null | grep -c quarantine || true)
if [[ "${QATTR_W}" -gt 0 ]]; then
    warn "Wrapper has quarantine — fixing..."
    xattr -drs com.apple.quarantine "${WRAPPER_APP}" 2>/dev/null || true
    fixed "Cleared quarantine on wrapper"
else
    ok "Wrapper quarantine clear"
fi

# Symlinks
WRAPPER_CONTENTS="${WRAPPER_APP}/Contents"
if [[ ! -L "${WRAPPER_CONTENTS}/Logs" ]]; then
    ln -sf SharedSupport/Logs "${WRAPPER_CONTENTS}/Logs" 2>/dev/null || true
    fixed "Created Logs symlink"
else
    ok "Logs symlink OK"
fi
if [[ ! -L "${WRAPPER_CONTENTS}/drive_c" ]]; then
    ln -sf SharedSupport/prefix/drive_c "${WRAPPER_CONTENTS}/drive_c" 2>/dev/null || true
    fixed "Created drive_c symlink"
else
    ok "drive_c symlink OK"
fi

# ==========================================================
echo ""
echo "[6] Wine Engine"
echo "────────────────────────────────────────"
if [[ -d "${WRAPPER_WINE}/bin" ]]; then
    ok "Engine bin directory exists"
else
    fail "Engine bin directory MISSING"
fi

if [[ -f "${WRAPPER_WINE}/version" ]]; then
    ok "Engine version: $(cat "${WRAPPER_WINE}/version")"
fi

# Find wine binary
WINE_BIN=""
for _candidate in "${WRAPPER_WINE}/bin/wine" "${WRAPPER_WINE}/bin/wine64"; do
    if [[ -x "${_candidate}" ]]; then
        WINE_BIN="${_candidate}"
        break
    fi
done
if [[ -n "${WINE_BIN}" ]]; then
    ok "Wine binary: ${WINE_BIN}"
    WINE_VER=$("${WINE_BIN}" --version 2>/dev/null || echo "unknown")
    ok "Wine version: ${WINE_VER}"
else
    fail "Wine binary not found (checked wine and wine64)"
fi

echo ""
echo "  --- Engine lib directory ---"
if [[ -d "${ENGINE_LIB}" ]]; then
    echo "  Contents:"
    ls -1 "${ENGINE_LIB}/"*.dylib 2>/dev/null | while read -r f; do
        echo "    $(basename "${f}")"
    done || echo "    (no .dylib files)"
else
    fail "Engine lib directory missing: ${ENGINE_LIB}"
fi

# ==========================================================
echo ""
echo "[7] Missing Libraries - AUTO FIX"
echo "────────────────────────────────────────"
if [[ -d "${WINE_STABLE_LIB}" ]] && [[ -d "${ENGINE_LIB}" ]]; then
    LIBS_MISSING=0
    LIBS_FIXED=0
    for _dylib in "${WINE_STABLE_LIB}"/*.dylib; do
        [[ -f "${_dylib}" ]] || continue
        _name=$(basename "${_dylib}")
        if [[ ! -f "${ENGINE_LIB}/${_name}" ]]; then
            LIBS_MISSING=$((LIBS_MISSING + 1))
            echo "  Missing: ${_name} — copying..."
            if cp "${_dylib}" "${ENGINE_LIB}/" 2>/dev/null; then
                fixed "Copied ${_name}"
                LIBS_FIXED=$((LIBS_FIXED + 1))
            else
                fail "Failed to copy ${_name}"
            fi
        fi
    done
    if [[ "${LIBS_MISSING}" -eq 0 ]]; then
        ok "All shared libraries present"
    else
        echo "  Found ${LIBS_MISSING} missing, fixed ${LIBS_FIXED}"
    fi

    # Specifically check libinotify (the known problem lib)
    if [[ -f "${ENGINE_LIB}/libinotify.0.dylib" ]]; then
        ok "libinotify.0.dylib present"
    else
        fail "libinotify.0.dylib STILL MISSING after fix attempt"
    fi
else
    if [[ ! -d "${WINE_STABLE_LIB}" ]]; then
        fail "Cannot fix: Wine Stable.app lib dir not found"
    fi
    if [[ ! -d "${ENGINE_LIB}" ]]; then
        fail "Cannot fix: Engine lib dir not found"
    fi
fi

# ==========================================================
echo ""
echo "[8] Wine Prefix"
echo "────────────────────────────────────────"
if [[ -d "${WRAPPER_PREFIX}/drive_c/windows" ]]; then
    ok "Wine prefix initialized"
else
    fail "Wine prefix NOT initialized"
fi

if [[ -f "${WRAPPER_PREFIX}/system.reg" ]]; then
    ok "system.reg exists"
else
    fail "system.reg missing"
fi

# Fonts
FONT_COUNT=0
if [[ -d "${WRAPPER_PREFIX}/drive_c/windows/Fonts" ]]; then
    for _f in "${WRAPPER_PREFIX}/drive_c/windows/Fonts"/*.ttf; do
        [[ -f "${_f}" ]] && FONT_COUNT=$((FONT_COUNT + 1))
    done
fi
if [[ "${FONT_COUNT}" -ge 10 ]]; then
    ok "Fonts: ${FONT_COUNT} .ttf files"
else
    warn "Only ${FONT_COUNT} fonts installed"
fi

# .NET
DOTNET_DIR="${WRAPPER_PREFIX}/drive_c/windows/Microsoft.NET/Framework"
if [[ -d "${DOTNET_DIR}" ]]; then
    DOTNET_DLLS=$(find "${DOTNET_DIR}" -name "mscorlib.dll" 2>/dev/null | wc -l | tr -d ' ')
    if [[ "${DOTNET_DLLS}" -gt 0 ]]; then
        ok ".NET runtimes: ${DOTNET_DLLS} mscorlib.dll found"
    else
        fail ".NET runtimes NOT installed"
    fi
else
    fail ".NET Framework directory missing"
fi

# ==========================================================
echo ""
echo "[9] Game Files"
echo "────────────────────────────────────────"
if [[ -f "${OUTLANDS_EXE}" ]]; then
    ok "Outlands.exe found ($(ls -lh "${OUTLANDS_EXE}" | awk '{print $5}'))"
else
    fail "Outlands.exe NOT found"
fi

GAME_DIR="${WRAPPER_PREFIX}/drive_c/Program Files (x86)/Ultima Online Outlands"
if [[ -d "${GAME_DIR}" ]]; then
    FILE_COUNT=$(find "${GAME_DIR}" -type f 2>/dev/null | wc -l | tr -d ' ')
    ok "Game directory: ${FILE_COUNT} files"
    if [[ -f "${GAME_DIR}/ClassicUO/ClassicUO.exe" ]]; then
        ok "ClassicUO.exe found"
    else
        warn "ClassicUO.exe not found (downloads on first launch)"
    fi
else
    fail "Game directory NOT found"
fi

# ==========================================================
echo ""
echo "[10] Plist Configuration"
echo "────────────────────────────────────────"
if [[ -f "${PLIST}" ]]; then
    for key in "D3DMETAL" "WINEESYNC" "WINEMSYNC" "DXVK" "MOLTENVKCX" \
               "Program Name and Path" "CFBundleIdentifier" "CFBundleName" \
               "WINEDEBUG" "Debug Mode"; do
        VAL=$(/usr/libexec/PlistBuddy -c "Print :\"${key}\"" "${PLIST}" 2>/dev/null || echo "NOT SET")
        echo "  ${key} = ${VAL}"
    done
fi

# ==========================================================
echo ""
echo "[11] Wine Smoke Test"
echo "────────────────────────────────────────"
if [[ -n "${WINE_BIN:-}" ]]; then
    export WINEPREFIX="${WRAPPER_PREFIX}"
    echo "  Running: ${WINE_BIN} cmd /c 'echo Wine works'"
    WINE_OUT=$("${WINE_BIN}" cmd /c 'echo Wine works' 2>&1 || true)
    if echo "${WINE_OUT}" | grep -q "Wine works"; then
        ok "Wine can execute commands"
    else
        fail "Wine execution FAILED"
        echo ""
        echo "  --- Full output ---"
        echo "${WINE_OUT}" | head -20
        echo "  --- End output ---"
    fi
    unset WINEPREFIX
else
    fail "Skipped (no Wine binary)"
fi

# ==========================================================
echo ""
echo "[12] Sikarugir Launch Test"
echo "────────────────────────────────────────"
if [[ -x "${WRAPPER_APP}/Contents/MacOS/Sikarugir" ]]; then
    echo "  Running Sikarugir (5s timeout)..."
    SIKA_OUT=$(timeout 10 "${WRAPPER_APP}/Contents/MacOS/Sikarugir" 2>&1 || true)
    if [[ -n "${SIKA_OUT}" ]]; then
        echo "  --- Sikarugir output ---"
        echo "${SIKA_OUT}" | head -20
        echo "  --- End output ---"
        if echo "${SIKA_OUT}" | grep -qi "error\|fatal\|crash\|not found\|Library not loaded"; then
            fail "Sikarugir reported errors (see above)"
        else
            ok "Sikarugir ran without errors"
        fi
    else
        warn "Sikarugir produced no output"
    fi
else
    fail "Sikarugir binary not executable"
fi

# ==========================================================
echo ""
echo "[13] Environment"
echo "────────────────────────────────────────"
echo "  PATH:"
echo "${PATH}" | tr ':' '\n' | while read -r p; do echo "    ${p}"; done
echo ""
echo "  Wine/SDL related vars:"
env | grep -iE '(wine|sdl|d3d|dxvk|metal|mvk)' 2>/dev/null | while read -r v; do
    echo "    ${v}"
done || echo "    (none)"

# LaunchAgent
LAUNCH_AGENT="$HOME/Library/LaunchAgents/com.sikarugir.outlands.audio.plist"
if [[ -f "${LAUNCH_AGENT}" ]]; then
    ok "Audio LaunchAgent installed"
else
    warn "Audio LaunchAgent not found (SDL_AUDIODRIVER may not be set)"
fi

# ==========================================================
echo ""
echo "========================================"
echo " Results: ${PASS} passed, ${FAIL} failed, ${WARN} warnings, ${FIXED} auto-fixed"
echo "========================================"
if [[ "${FIXED}" -gt 0 ]]; then
    echo " Auto-fixed ${FIXED} issues. Run diagnostics again to verify."
fi
if [[ "${FAIL}" -gt 0 ]]; then
    echo " Fix the remaining ✗ items and re-run."
    exit 1
else
    echo " Everything looks good! Try: open ~/Applications/Sikarugir/outlands.app"
    exit 0
fi
