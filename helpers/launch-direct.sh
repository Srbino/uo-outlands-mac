#!/usr/bin/env bash
# =============================================================================
# Launch Outlands directly via Wine (bypassing Sikarugir wrapper)
# Use this for debugging when outlands.app doesn't start
# =============================================================================

WRAPPER_APP="$HOME/Applications/Sikarugir/outlands.app"
WINE_BIN="${WRAPPER_APP}/Contents/SharedSupport/wine/bin/wine"
WINEPREFIX="${WRAPPER_APP}/Contents/SharedSupport/prefix"
OUTLANDS_EXE="${WINEPREFIX}/drive_c/Program Files (x86)/Ultima Online Outlands/Outlands.exe"

echo ""
echo "=== UO Outlands Direct Launch ==="
echo ""

# Validate
if [[ ! -x "${WINE_BIN}" ]]; then
    echo "ERROR: Wine binary not found: ${WINE_BIN}"
    exit 1
fi

if [[ ! -f "${OUTLANDS_EXE}" ]]; then
    echo "ERROR: Outlands.exe not found: ${OUTLANDS_EXE}"
    exit 1
fi

echo "Wine:    ${WINE_BIN}"
echo "Prefix:  ${WINEPREFIX}"
echo "Exe:     ${OUTLANDS_EXE}"
echo ""
echo "Starting Outlands... (keep this terminal open)"
echo ""

export WINEPREFIX
export WINEESYNC=1
export WINEMSYNC=1
export WINEDEBUG=-plugplay

"${WINE_BIN}" "${OUTLANDS_EXE}" 2>&1
