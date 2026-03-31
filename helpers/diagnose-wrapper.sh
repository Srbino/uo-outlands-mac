#!/usr/bin/env bash
# =============================================================================
# UO Outlands Wrapper Diagnostic Script
# Validates Wine, Sikarugir, and wrapper configuration
# =============================================================================

WRAPPER_APP="$HOME/Applications/Sikarugir/outlands.app"
WRAPPER_PREFIX="${WRAPPER_APP}/Contents/SharedSupport/prefix"
WRAPPER_WINE="${WRAPPER_APP}/Contents/SharedSupport/wine"
PLIST="${WRAPPER_APP}/Contents/Info.plist"
OUTLANDS_EXE="${WRAPPER_PREFIX}/drive_c/Program Files (x86)/Ultima Online Outlands/Outlands.exe"
ENGINES_DIR="$HOME/Library/Application Support/Sikarugir/Engines"

PASS=0
FAIL=0
WARN=0

ok()   { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }
warn() { echo "  ! $1"; WARN=$((WARN + 1)); }

echo ""
echo "========================================"
echo " UO Outlands Wrapper Diagnostics"
echo "========================================"
echo ""

# --- 1. System ---
echo "[1] System"
echo "────────────────────────────────────────"
echo "  macOS:    $(sw_vers -productVersion)"
echo "  Arch:     $(uname -m)"
echo "  Bash:     ${BASH_VERSION}"
echo "  User:     $(whoami)"
echo ""

# --- 2. Homebrew + Casks ---
echo "[2] Homebrew & Casks"
echo "────────────────────────────────────────"
if command -v brew >/dev/null 2>&1; then
    ok "Homebrew: $(brew --version | head -1)"
else
    fail "Homebrew not found"
fi

if brew list --cask wine-stable >/dev/null 2>&1; then
    ok "Wine Stable cask installed"
else
    fail "Wine Stable cask NOT installed"
fi

if brew list --cask sikarugir >/dev/null 2>&1; then
    ok "Sikarugir cask installed"
else
    fail "Sikarugir cask NOT installed"
fi
echo ""

# --- 3. Wine binary ---
echo "[3] Wine"
echo "────────────────────────────────────────"
WINE_BIN=""
# Search order: wrapper engine first (preferred), then system Wine Stable
for _candidate in \
    "${WRAPPER_WINE}/bin/wine" \
    "${WRAPPER_WINE}/bin/wine64" \
    "/Applications/Wine Stable.app/Contents/Resources/wine/bin/wine" \
    "/Applications/Wine Stable.app/Contents/Resources/wine/bin/wine64"; do
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
    fail "Wine binary not found (checked wrapper engine + /Applications/Wine Stable.app)"
fi

# Quarantine check
if [[ -d "/Applications/Wine Stable.app" ]]; then
    QATTR=$(xattr "/Applications/Wine Stable.app" 2>/dev/null | grep -c quarantine || true)
    if [[ "${QATTR}" -gt 0 ]]; then
        fail "Wine Stable has quarantine attribute (run: xattr -cr '/Applications/Wine Stable.app')"
    else
        ok "Wine Stable quarantine clear"
    fi
fi
echo ""

# --- 4. Rosetta ---
echo "[4] Rosetta 2"
echo "────────────────────────────────────────"
if /usr/bin/pgrep -x oahd >/dev/null 2>&1; then
    ok "Rosetta 2 running"
else
    fail "Rosetta 2 NOT running (required for Wine x86 translation)"
fi
echo ""

# --- 5. Wrapper structure ---
echo "[5] Wrapper Structure"
echo "────────────────────────────────────────"
if [[ -d "${WRAPPER_APP}" ]]; then
    ok "Wrapper exists: ${WRAPPER_APP}"
else
    fail "Wrapper NOT found: ${WRAPPER_APP}"
fi

if [[ -f "${PLIST}" ]]; then
    ok "Info.plist exists"
else
    fail "Info.plist NOT found"
fi

if [[ -d "${WRAPPER_WINE}/bin" ]]; then
    ok "Engine injected in wrapper"
    if [[ -f "${WRAPPER_WINE}/version" ]]; then
        ok "Engine version: $(cat "${WRAPPER_WINE}/version")"
    fi
else
    fail "Engine NOT found in wrapper (${WRAPPER_WINE}/bin missing)"
fi

if [[ -x "${WRAPPER_APP}/Contents/MacOS/Sikarugir" ]]; then
    ok "Sikarugir binary executable"
else
    fail "Sikarugir binary not executable"
fi

# Quarantine on wrapper
QATTR_W=$(xattr "${WRAPPER_APP}" 2>/dev/null | grep -c quarantine || true)
if [[ "${QATTR_W}" -gt 0 ]]; then
    fail "Wrapper has quarantine attribute (run: xattr -cr '${WRAPPER_APP}')"
else
    ok "Wrapper quarantine clear"
fi
echo ""

# --- 6. Wine prefix ---
echo "[6] Wine Prefix"
echo "────────────────────────────────────────"
if [[ -d "${WRAPPER_PREFIX}/drive_c/windows" ]]; then
    ok "Wine prefix initialized"
else
    fail "Wine prefix NOT initialized (drive_c/windows missing)"
fi

if [[ -f "${WRAPPER_PREFIX}/system.reg" ]]; then
    ok "system.reg exists"
else
    fail "system.reg missing"
fi

FONT_COUNT=0
if [[ -d "${WRAPPER_PREFIX}/drive_c/windows/Fonts" ]]; then
    for _f in "${WRAPPER_PREFIX}/drive_c/windows/Fonts"/*.ttf; do
        [[ -f "${_f}" ]] && FONT_COUNT=$((FONT_COUNT + 1))
    done
fi
if [[ "${FONT_COUNT}" -ge 10 ]]; then
    ok "Fonts installed: ${FONT_COUNT} .ttf files"
else
    warn "Only ${FONT_COUNT} fonts (may cause rendering issues)"
fi

# .NET check
DOTNET_DIR="${WRAPPER_PREFIX}/drive_c/windows/Microsoft.NET/Framework"
if [[ -d "${DOTNET_DIR}" ]]; then
    DOTNET_DLLS=$(find "${DOTNET_DIR}" -name "mscorlib.dll" 2>/dev/null | wc -l | tr -d ' ')
    if [[ "${DOTNET_DLLS}" -gt 0 ]]; then
        ok ".NET runtimes installed (${DOTNET_DLLS} mscorlib.dll found)"
    else
        fail ".NET runtimes NOT installed (no mscorlib.dll)"
    fi
else
    fail ".NET Framework directory missing"
fi
echo ""

# --- 7. Game files ---
echo "[7] Game Files"
echo "────────────────────────────────────────"
if [[ -f "${OUTLANDS_EXE}" ]]; then
    ok "Outlands.exe found"
    ls -lh "${OUTLANDS_EXE}" | awk '{print "     Size: " $5}'
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
        warn "ClassicUO.exe not found (may need first launch to download)"
    fi
else
    fail "Game directory NOT found"
fi
echo ""

# --- 8. Plist config ---
echo "[8] Plist Configuration"
echo "────────────────────────────────────────"
if [[ -f "${PLIST}" ]]; then
    for key in "D3DMETAL" "WINEESYNC" "WINEMSYNC" "Program Name and Path" "CFBundleIdentifier" "WINEDEBUG"; do
        VAL=$(/usr/libexec/PlistBuddy -c "Print :\"${key}\"" "${PLIST}" 2>/dev/null || echo "NOT SET")
        echo "  ${key} = ${VAL}"
    done
fi
echo ""

# --- 9. Wine test run ---
echo "[9] Wine Test"
echo "────────────────────────────────────────"
if [[ -n "${WINE_BIN:-}" ]]; then
    export WINEPREFIX="${WRAPPER_PREFIX}"
    WINE_OUT=$("${WINE_BIN}" cmd /c 'echo Wine works' 2>&1 || true)
    if echo "${WINE_OUT}" | grep -q "Wine works"; then
        ok "Wine can execute commands"
    else
        fail "Wine execution failed"
        echo "     Output: ${WINE_OUT}" | head -5
    fi
else
    fail "Skipped (no Wine binary found)"
fi
echo ""

# --- 10. Engines ---
echo "[10] Installed Engines"
echo "────────────────────────────────────────"
if [[ -d "${ENGINES_DIR}" ]]; then
    ls -1 "${ENGINES_DIR}" 2>/dev/null | while read -r eng; do
        echo "  - ${eng}"
    done
else
    warn "No engines directory found"
fi
echo ""

# --- Summary ---
echo "========================================"
echo " Results: ${PASS} passed, ${FAIL} failed, ${WARN} warnings"
echo "========================================"
if [[ "${FAIL}" -gt 0 ]]; then
    echo " Fix the ✗ items above and re-run."
    exit 1
else
    echo " Everything looks good!"
    exit 0
fi
