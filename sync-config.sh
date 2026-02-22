#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# UO Outlands - Config Sync (MacBook Air → Mac Mini)
# =============================================================================
# Pulls ClassicUO profiles, Razor scripts/macros, and settings from
# MacBook Air to Mac Mini. Air is ALWAYS read-only (source of truth).
#
# Usage:
#   ./sync-config.sh          # pull config from Air → local
#   ./sync-config.sh --dry    # preview what would be synced
#   ./sync-config.sh --push   # push local config → Air (use with caution)
# =============================================================================

# --- Config ---
REMOTE_HOST="air"
REMOTE_USER="pavelsrba"
GAME_REL="Applications/Sikarugir/outlands.app/Contents/SharedSupport/prefix/drive_c/Program Files (x86)/Ultima Online Outlands"
CLASSICUO_REL="${GAME_REL}/ClassicUO"

LOCAL_BASE="$HOME"
REMOTE_BASE="/Users/${REMOTE_USER}"

# What to sync (relative to ClassicUO dir)
SYNC_PATHS=(
    "settings.json"
    "Data/Profiles"
    "Data/Plugins/Assistant/Profiles"
    "Data/Plugins/Assistant/Scripts"
    "Data/Plugins/Assistant/Macros"
    "Data/Plugins/Assistant/counters.xml"
)

# --- Colors ---
if [[ -t 1 ]]; then
    GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'
    CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'
else
    GREEN=''; YELLOW=''; RED=''; CYAN=''; BOLD=''; DIM=''; NC=''
fi

info()  { echo -e "  ${GREEN}✓${NC} $1"; }
warn()  { echo -e "  ${YELLOW}!${NC} $1"; }
error() { echo -e "  ${RED}✗${NC} $1"; }
die()   { error "$1"; exit 1; }

# --- Parse args ---
MODE="pull"
DRY_RUN=""
for arg in "$@"; do
    case "${arg}" in
        --dry|--dry-run) DRY_RUN="--dry-run" ;;
        --push) MODE="push" ;;
        --help|-h)
            echo "Usage: $0 [--dry] [--push]"
            echo "  (default)  Pull config from Air → local"
            echo "  --push     Push local config → Air"
            echo "  --dry      Preview only, don't copy"
            exit 0
            ;;
    esac
done

# --- Verify SSH ---
echo ""
echo -e "${BOLD}${CYAN}UO Outlands Config Sync${NC}"
echo "────────────────────────────────────────"

if ! ssh -o ConnectTimeout=3 -o BatchMode=yes "${REMOTE_HOST}" "true" 2>/dev/null; then
    die "Cannot reach ${REMOTE_HOST}. Is MacBook Air on the network?"
fi
REMOTE_HOSTNAME=$(ssh "${REMOTE_HOST}" "hostname" 2>/dev/null)
info "Connected to ${REMOTE_HOSTNAME}"

# --- Paths ---
LOCAL_CUO="${LOCAL_BASE}/${CLASSICUO_REL}"
REMOTE_CUO="${REMOTE_BASE}/${CLASSICUO_REL}"

if [[ ! -d "${LOCAL_CUO}" ]]; then
    die "Local ClassicUO not found: ${LOCAL_CUO}"
fi

if ! ssh "${REMOTE_HOST}" "test -d '${REMOTE_CUO}'" 2>/dev/null; then
    die "Remote ClassicUO not found: ${REMOTE_CUO}"
fi

# --- Backup local before overwriting ---
if [[ "${MODE}" == "pull" ]] && [[ -z "${DRY_RUN}" ]]; then
    BACKUP_DIR="/Volumes/documents/Games/Outlands/backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "${BACKUP_DIR}"
    for path in "${SYNC_PATHS[@]}"; do
        src="${LOCAL_CUO}/${path}"
        if [[ -e "${src}" ]]; then
            dest="${BACKUP_DIR}/${path}"
            mkdir -p "$(dirname "${dest}")"
            cp -a "${src}" "${dest}"
        fi
    done
    info "Local backup: ${BACKUP_DIR}"
fi

# --- Sync ---
if [[ "${MODE}" == "pull" ]]; then
    echo ""
    echo -e "  ${BOLD}Pulling: ${CYAN}Air → Mac Mini${NC}"
    [[ -n "${DRY_RUN}" ]] && echo -e "  ${DIM}(dry run — no files will be changed)${NC}"
    echo ""

    for path in "${SYNC_PATHS[@]}"; do
        remote_path="${REMOTE_HOST}:\"${REMOTE_CUO}/${path}\""
        local_path="${LOCAL_CUO}/${path}"

        # Ensure parent dir exists
        mkdir -p "$(dirname "${local_path}")"

        # Escape path for remote shell (parentheses, spaces)
        remote_escaped=$(printf '%s' "${REMOTE_CUO}/${path}" | sed 's/[()]/\\&/g; s/ /\\ /g')

        # Use trailing slash for directories
        if ssh "${REMOTE_HOST}" "test -d '${REMOTE_CUO}/${path}'" 2>/dev/null; then
            rsync -avz ${DRY_RUN} --delete \
                -e "ssh" \
                --rsync-path="rsync" \
                "${REMOTE_HOST}:${remote_escaped}/" \
                "${local_path}/" 2>&1 | sed 's/^/    /'
        elif ssh "${REMOTE_HOST}" "test -f '${REMOTE_CUO}/${path}'" 2>/dev/null; then
            rsync -avz ${DRY_RUN} \
                -e "ssh" \
                --rsync-path="rsync" \
                "${REMOTE_HOST}:${remote_escaped}" \
                "${local_path}" 2>&1 | sed 's/^/    /'
        else
            warn "Skipping (not found on Air): ${path}"
        fi
    done

elif [[ "${MODE}" == "push" ]]; then
    echo ""
    echo -e "  ${RED}${BOLD}Pushing: Mac Mini → Air${NC}"
    echo -e "  ${YELLOW}WARNING: This will overwrite config on Air!${NC}"
    [[ -n "${DRY_RUN}" ]] && echo -e "  ${DIM}(dry run — no files will be changed)${NC}"

    if [[ -z "${DRY_RUN}" ]]; then
        read -rp "  Are you sure? (y/N): " CONFIRM
        if [[ "${CONFIRM}" != "y" && "${CONFIRM}" != "Y" ]]; then
            echo "  Aborted."
            exit 0
        fi
    fi
    echo ""

    for path in "${SYNC_PATHS[@]}"; do
        local_path="${LOCAL_CUO}/${path}"
        remote_escaped=$(printf '%s' "${REMOTE_CUO}/${path}" | sed 's/[()]/\\&/g; s/ /\\ /g')
        if [[ -d "${local_path}" ]]; then
            rsync -avz ${DRY_RUN} --delete \
                -e "ssh" \
                "${local_path}/" \
                "${REMOTE_HOST}:${remote_escaped}/" 2>&1 | sed 's/^/    /'
        elif [[ -f "${local_path}" ]]; then
            rsync -avz ${DRY_RUN} \
                -e "ssh" \
                "${local_path}" \
                "${REMOTE_HOST}:${remote_escaped}" 2>&1 | sed 's/^/    /'
        else
            warn "Skipping (not found locally): ${path}"
        fi
    done
fi

echo ""
info "Done."
