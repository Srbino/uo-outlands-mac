#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# UO Outlands - Config Manager (Backup / Restore / Sync)
# =============================================================================
# HELPER SCRIPT — not part of the official UO Outlands installer.
# This is a personal migration/backup tool for syncing ClassicUO config
# between two Macs via SSH. You MUST customize the Config section below
# to match your own setup before using it.
#
# Prerequisites:
#   - SSH key-based access to the remote Mac (no password prompts)
#   - Both Macs must have UO Outlands installed via Sikarugir
#
# What it manages:
#   - ClassicUO settings.json
#   - ClassicUO profiles (Data/Profiles)
#   - Razor profiles, scripts, macros (Data/Plugins/Assistant/*)
#
# Usage:
#   ./sync-config.sh pull               Pull config from remote → local
#   ./sync-config.sh push               Push local config → remote (caution!)
#   ./sync-config.sh backup             Backup local ClassicUO config
#   ./sync-config.sh backup-remote      Backup remote ClassicUO config
#   ./sync-config.sh restore [dir]      Restore from backup (latest if omitted)
#   ./sync-config.sh list               List available backups
#
# Options:
#   --dry                               Preview only, don't change files
#   -h, --help                          Show this help
# =============================================================================

# --- Config (EDIT THESE TO MATCH YOUR SETUP) ---------------------------------
# SSH host alias — must be configured in your ~/.ssh/config
REMOTE_HOST="my-other-mac"
# Username on the remote Mac
REMOTE_USER="yourusername"
# Path to the Sikarugir wrapper (relative to $HOME) — usually no change needed
GAME_REL="Applications/Sikarugir/outlands.app/Contents/SharedSupport/prefix/drive_c/Program Files (x86)/Ultima Online Outlands"
CLASSICUO_REL="${GAME_REL}/ClassicUO"

LOCAL_BASE="$HOME"
REMOTE_BASE="/Users/${REMOTE_USER}"

# Where to store backups (will be created if it doesn't exist)
BACKUP_BASE="$HOME/outlands-backups"
# -----------------------------------------------------------------------------

# What to sync for pull/push (selective — profiles + scripts only)
SYNC_PATHS=(
    "settings.json"
    "Data/Profiles"
    "Data/Plugins/Assistant/Profiles"
    "Data/Plugins/Assistant/Scripts"
    "Data/Plugins/Assistant/Macros"
    "Data/Plugins/Assistant/counters.xml"
)

# What to backup/restore (everything)
BACKUP_PATHS=(
    "settings.json"
    "Data"
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

# --- Helpers ---
escape_remote_path() {
    printf '%s' "$1" | sed 's/[()]/\\&/g; s/ /\\ /g'
}

require_ssh() {
    if ! ssh -o ConnectTimeout=3 -o BatchMode=yes "${REMOTE_HOST}" "true" 2>/dev/null; then
        die "Cannot reach ${REMOTE_HOST}. Is the remote Mac on the network?"
    fi
    REMOTE_HOSTNAME=$(ssh "${REMOTE_HOST}" "hostname" 2>/dev/null)
    info "Connected to ${REMOTE_HOSTNAME}"
}

require_local_cuo() {
    LOCAL_CUO="${LOCAL_BASE}/${CLASSICUO_REL}"
    if [[ ! -d "${LOCAL_CUO}" ]]; then
        die "Local ClassicUO not found: ${LOCAL_CUO}"
    fi
}

require_remote_cuo() {
    REMOTE_CUO="${REMOTE_BASE}/${CLASSICUO_REL}"
    if ! ssh "${REMOTE_HOST}" "test -d '${REMOTE_CUO}'" 2>/dev/null; then
        die "Remote ClassicUO not found: ${REMOTE_CUO}"
    fi
}

rsync_remote_to_local() {
    local path="$1" remote_cuo="$2" local_cuo="$3" dry="$4"
    local local_path="${local_cuo}/${path}"
    local remote_escaped
    remote_escaped=$(escape_remote_path "${remote_cuo}/${path}")

    mkdir -p "$(dirname "${local_path}")"

    if ssh "${REMOTE_HOST}" "test -d '${remote_cuo}/${path}'" 2>/dev/null; then
        mkdir -p "${local_path}"
        rsync -avz ${dry} --delete \
            -e "ssh" --rsync-path="rsync" \
            "${REMOTE_HOST}:${remote_escaped}/" \
            "${local_path}/" 2>&1 | sed 's/^/    /'
    elif ssh "${REMOTE_HOST}" "test -f '${remote_cuo}/${path}'" 2>/dev/null; then
        rsync -avz ${dry} \
            -e "ssh" --rsync-path="rsync" \
            "${REMOTE_HOST}:${remote_escaped}" \
            "${local_path}" 2>&1 | sed 's/^/    /'
    else
        warn "Skipping (not found on remote): ${path}"
    fi
}

rsync_local_to_remote() {
    local path="$1" local_cuo="$2" remote_cuo="$3" dry="$4"
    local local_path="${local_cuo}/${path}"
    local remote_escaped
    remote_escaped=$(escape_remote_path "${remote_cuo}/${path}")

    if [[ -d "${local_path}" ]]; then
        rsync -avz ${dry} --delete \
            -e "ssh" \
            "${local_path}/" \
            "${REMOTE_HOST}:${remote_escaped}/" 2>&1 | sed 's/^/    /'
    elif [[ -f "${local_path}" ]]; then
        rsync -avz ${dry} \
            -e "ssh" \
            "${local_path}" \
            "${REMOTE_HOST}:${remote_escaped}" 2>&1 | sed 's/^/    /'
    else
        warn "Skipping (not found locally): ${path}"
    fi
}

# --- Parse args ---
MODE=""
DRY_RUN=""
RESTORE_DIR=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        pull)          MODE="pull" ;;
        push)          MODE="push" ;;
        backup)        MODE="backup" ;;
        backup-remote) MODE="backup-remote" ;;
        restore)       MODE="restore"
                       if [[ ${2:-} ]] && [[ ! "$2" =~ ^- ]]; then
                           RESTORE_DIR="$2"; shift
                       fi
                       ;;
        list)          MODE="list" ;;
        --dry|--dry-run) DRY_RUN="--dry-run" ;;
        -h|--help)
            echo "Usage: $0 <command> [--dry]"
            echo ""
            echo "Commands:"
            echo "  pull               Pull config from remote → local (default)"
            echo "  push               Push local config → remote (use with caution!)"
            echo "  backup             Full backup of local ClassicUO config"
            echo "  backup-remote      Full backup of remote ClassicUO config"
            echo "  restore [dir]      Restore from backup (latest if dir omitted)"
            echo "  list               List available backups"
            echo ""
            echo "Options:"
            echo "  --dry              Preview only, don't change files"
            exit 0
            ;;
        *)  die "Unknown argument: $1 (use --help)" ;;
    esac
    shift
done

# Default to pull if no command given
[[ -z "${MODE}" ]] && MODE="pull"

# --- Header ---
echo ""
echo -e "${BOLD}${CYAN}UO Outlands Config Manager${NC}"
echo "────────────────────────────────────────"

# =============================================================================
# LIST — show available backups
# =============================================================================
if [[ "${MODE}" == "list" ]]; then
    if [[ ! -d "${BACKUP_BASE}" ]]; then
        die "Backup directory not found: ${BACKUP_BASE}"
    fi

    backups=()
    while IFS= read -r -d '' d; do
        backups+=("$d")
    done < <(find "${BACKUP_BASE}" -maxdepth 1 -type d -name 'backup_*' -print0 | sort -z)

    if [[ ${#backups[@]} -eq 0 ]]; then
        warn "No backups found in ${BACKUP_BASE}"
        exit 0
    fi

    echo ""
    for b in "${backups[@]}"; do
        name=$(basename "$b")
        size=$(du -sh "$b" 2>/dev/null | cut -f1)
        echo -e "  ${CYAN}${name}${NC}  ${DIM}(${size})${NC}"
    done
    echo ""
    echo -e "  ${DIM}Restore with: $0 restore <dir-name>${NC}"
    exit 0
fi

# =============================================================================
# BACKUP — full local backup
# =============================================================================
if [[ "${MODE}" == "backup" ]]; then
    require_local_cuo
    LOCAL_CUO="${LOCAL_BASE}/${CLASSICUO_REL}"

    BACKUP_DIR="${BACKUP_BASE}/backup_$(date +%Y%m%d_%H%M%S)"

    echo ""
    echo -e "  ${BOLD}Backing up local ClassicUO → ${CYAN}${BACKUP_DIR}${NC}"
    [[ -n "${DRY_RUN}" ]] && echo -e "  ${DIM}(dry run)${NC}"
    echo ""

    if [[ -z "${DRY_RUN}" ]]; then
        mkdir -p "${BACKUP_DIR}"
        for path in "${BACKUP_PATHS[@]}"; do
            src="${LOCAL_CUO}/${path}"
            if [[ -e "${src}" ]]; then
                dest="${BACKUP_DIR}/${path}"
                mkdir -p "$(dirname "${dest}")"
                cp -a "${src}" "${dest}"
                info "Copied: ${path}"
            else
                warn "Skipping (not found): ${path}"
            fi
        done
        size=$(du -sh "${BACKUP_DIR}" 2>/dev/null | cut -f1)
        info "Backup complete (${size}): ${BACKUP_DIR}"
    else
        for path in "${BACKUP_PATHS[@]}"; do
            src="${LOCAL_CUO}/${path}"
            [[ -e "${src}" ]] && info "Would copy: ${path}" || warn "Not found: ${path}"
        done
    fi

    echo ""
    info "Done."
    exit 0
fi

# =============================================================================
# BACKUP-REMOTE — full backup from remote Mac (via SSH)
# =============================================================================
if [[ "${MODE}" == "backup-remote" ]]; then
    require_ssh
    require_remote_cuo

    BACKUP_DIR="${BACKUP_BASE}/backup_remote_$(date +%Y%m%d_%H%M%S)"

    echo ""
    echo -e "  ${BOLD}Backing up remote ClassicUO → ${CYAN}${BACKUP_DIR}${NC}"
    [[ -n "${DRY_RUN}" ]] && echo -e "  ${DIM}(dry run)${NC}"
    echo ""

    [[ -z "${DRY_RUN}" ]] && mkdir -p "${BACKUP_DIR}"

    for path in "${BACKUP_PATHS[@]}"; do
        rsync_remote_to_local "${path}" "${REMOTE_CUO}" "${BACKUP_DIR}" "${DRY_RUN}"
    done

    if [[ -z "${DRY_RUN}" ]]; then
        size=$(du -sh "${BACKUP_DIR}" 2>/dev/null | cut -f1)
        info "Backup complete (${size}): ${BACKUP_DIR}"
    fi

    echo ""
    info "Done."
    exit 0
fi

# =============================================================================
# RESTORE — restore from backup to local ClassicUO
# =============================================================================
if [[ "${MODE}" == "restore" ]]; then
    require_local_cuo
    LOCAL_CUO="${LOCAL_BASE}/${CLASSICUO_REL}"

    # Find backup dir
    if [[ -n "${RESTORE_DIR}" ]]; then
        if [[ -d "${RESTORE_DIR}" ]]; then
            BACKUP_DIR="${RESTORE_DIR}"
        elif [[ -d "${BACKUP_BASE}/${RESTORE_DIR}" ]]; then
            BACKUP_DIR="${BACKUP_BASE}/${RESTORE_DIR}"
        else
            die "Backup not found: ${RESTORE_DIR}"
        fi
    else
        BACKUP_DIR=$(find "${BACKUP_BASE}" -maxdepth 1 -type d -name 'backup_*' | sort | tail -1)
        if [[ -z "${BACKUP_DIR}" ]]; then
            die "No backups found in ${BACKUP_BASE}"
        fi
        info "Using latest backup: $(basename "${BACKUP_DIR}")"
    fi

    echo ""
    echo -e "  ${BOLD}Restoring: ${CYAN}$(basename "${BACKUP_DIR}") → local ClassicUO${NC}"
    [[ -n "${DRY_RUN}" ]] && echo -e "  ${DIM}(dry run)${NC}"
    echo ""

    # Safety backup before restore
    if [[ -z "${DRY_RUN}" ]]; then
        PRE_RESTORE="${BACKUP_BASE}/backup_pre_restore_$(date +%Y%m%d_%H%M%S)"
        mkdir -p "${PRE_RESTORE}"
        for path in "${BACKUP_PATHS[@]}"; do
            src="${LOCAL_CUO}/${path}"
            if [[ -e "${src}" ]]; then
                dest="${PRE_RESTORE}/${path}"
                mkdir -p "$(dirname "${dest}")"
                cp -a "${src}" "${dest}"
            fi
        done
        info "Safety backup: ${PRE_RESTORE}"
    fi

    # Restore
    for path in "${BACKUP_PATHS[@]}"; do
        src="${BACKUP_DIR}/${path}"
        dest="${LOCAL_CUO}/${path}"
        if [[ ! -e "${src}" ]]; then
            warn "Skipping (not in backup): ${path}"
            continue
        fi

        if [[ -n "${DRY_RUN}" ]]; then
            info "Would restore: ${path}"
            continue
        fi

        mkdir -p "$(dirname "${dest}")"
        if [[ -d "${src}" ]]; then
            rsync -av --delete "${src}/" "${dest}/" 2>&1 | sed 's/^/    /'
        else
            cp -a "${src}" "${dest}"
            info "Restored: ${path}"
        fi
    done

    echo ""
    info "Done."
    exit 0
fi

# =============================================================================
# PULL / PUSH — sync with remote Mac via SSH
# =============================================================================
require_ssh
require_local_cuo
require_remote_cuo
LOCAL_CUO="${LOCAL_BASE}/${CLASSICUO_REL}"
REMOTE_CUO="${REMOTE_BASE}/${CLASSICUO_REL}"

if [[ "${MODE}" == "pull" ]]; then
    # Auto-backup before pull
    if [[ -z "${DRY_RUN}" ]]; then
        BACKUP_DIR="${BACKUP_BASE}/backup_$(date +%Y%m%d_%H%M%S)"
        mkdir -p "${BACKUP_DIR}"
        for path in "${SYNC_PATHS[@]}"; do
            src="${LOCAL_CUO}/${path}"
            if [[ -e "${src}" ]]; then
                dest="${BACKUP_DIR}/${path}"
                mkdir -p "$(dirname "${dest}")"
                cp -a "${src}" "${dest}"
            fi
        done
        info "Auto-backup: ${BACKUP_DIR}"
    fi

    echo ""
    echo -e "  ${BOLD}Pulling: ${CYAN}remote → local${NC}"
    [[ -n "${DRY_RUN}" ]] && echo -e "  ${DIM}(dry run)${NC}"
    echo ""

    for path in "${SYNC_PATHS[@]}"; do
        rsync_remote_to_local "${path}" "${REMOTE_CUO}" "${LOCAL_CUO}" "${DRY_RUN}"
    done

elif [[ "${MODE}" == "push" ]]; then
    echo ""
    echo -e "  ${RED}${BOLD}Pushing: local → remote${NC}"
    echo -e "  ${YELLOW}WARNING: This will overwrite config on the remote Mac!${NC}"
    [[ -n "${DRY_RUN}" ]] && echo -e "  ${DIM}(dry run)${NC}"

    if [[ -z "${DRY_RUN}" ]]; then
        read -rp "  Are you sure? (y/N): " CONFIRM
        if [[ "${CONFIRM}" != "y" && "${CONFIRM}" != "Y" ]]; then
            echo "  Aborted."
            exit 0
        fi
    fi
    echo ""

    for path in "${SYNC_PATHS[@]}"; do
        rsync_local_to_remote "${path}" "${LOCAL_CUO}" "${REMOTE_CUO}" "${DRY_RUN}"
    done
fi

echo ""
info "Done."
