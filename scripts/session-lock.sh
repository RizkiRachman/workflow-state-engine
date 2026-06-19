#!/usr/bin/env bash
# scripts/session-lock.sh — G21: Concurrent Session Lock
# Prevents concurrent orchestration sessions from conflicting.
# Uses file-based locking per branch with PID verification.
# Usage: scripts/session-lock.sh --lock BRANCH [OPTIONS]
#        scripts/session-lock.sh --unlock BRANCH
#        scripts/session-lock.sh --check BRANCH

set -euo pipefail

# ── Color Constants ──────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ── Defaults ─────────────────────────────────────────────────────────────────
LOCK_DIR="session"
STALE_TIMEOUT=3600
FORCE=false
COMMAND=""
BRANCH=""
EXIT_CODE=0

# ── Usage ────────────────────────────────────────────────────────────────────

usage() {
    cat <<'USAGE'
usage: session-lock.sh <COMMAND> <branch> [OPTIONS]

Prevents concurrent orchestration sessions from conflicting.

COMMANDS:
  --lock BRANCH     Acquire a lock for the given branch/session
  --unlock BRANCH   Release the lock
  --check BRANCH    Check if a lock exists and is still valid

OPTIONS:
  --stale-timeout N   Consider lock stale after N seconds (default: 3600)
  --force             Forcefully break a stale lock (for --lock)
  --help              Show this help message and exit

EXIT CODES:
  0   Success (lock acquired, released, or check passed)
  1   Lock held by another session (--lock), or general error
  2   Usage displayed (--help)

LOCK FILE (~/.lock):
  Stored in session/<branch>/.lock as JSON with PID, hostname, branch, timestamp.

EXAMPLES:
  scripts/session-lock.sh --lock feature/my-feature
  scripts/session-lock.sh --lock feature/my-feature --stale-timeout 7200
  scripts/session-lock.sh --lock feature/my-feature --force
  scripts/session-lock.sh --check feature/my-feature
  scripts/session-lock.sh --unlock feature/my-feature
USAGE
    exit 2
}

# ── Logging Functions ───────────────────────────────────────────────────────

log_pass() {
    local msg="$1"
    echo -e "${GREEN}[PASS]${NC} $msg"
}

log_fail() {
    local msg="$1"
    echo -e "${RED}[FAIL]${NC} $msg" >&2
    EXIT_CODE=1
}

log_info() {
    local msg="$1"
    echo -e "${YELLOW}[INFO]${NC} $msg"
}

log_section() {
    echo ""
    echo -e "${CYAN}■${NC} $1"
}

# ── Lock File Path Helpers ──────────────────────────────────────────────────

lock_file_path() {
    local branch="$1"
    echo "${LOCK_DIR}/${branch}/.lock"
}

# ── Lock Metadata ───────────────────────────────────────────────────────────

read_lock() {
    local lock_file="$1"
    if [[ ! -f "$lock_file" ]]; then
        echo ""
        return
    fi
    cat "$lock_file"
}

write_lock() {
    local lock_file="$1"
    local branch="$2"
    local hostname
    hostname=$(hostname 2>/dev/null || echo "unknown")
    cat > "$lock_file" <<LOCKEOF
pid=$$
hostname=${hostname}
branch=${branch}
timestamp=$(date +%s)
LOCKEOF
}

# ── PID Alive Check ─────────────────────────────────────────────────────────

pid_alive() {
    local pid="$1"
    if [[ -z "$pid" || "$pid" -le 0 ]]; then
        return 1
    fi
    kill -0 "$pid" 2>/dev/null
}

# ── Parse Lock File ─────────────────────────────────────────────────────────

parse_lock_value() {
    local lock_file="$1"
    local key="$2"
    grep "^${key}=" "$lock_file" 2>/dev/null | cut -d= -f2- || echo ""
}

# ── Lock Acquire ────────────────────────────────────────────────────────────

cmd_lock() {
    local branch="$1"
    local lock_file
    lock_file=$(lock_file_path "$branch")
    local lock_dir
    lock_dir=$(dirname "$lock_file")

    log_section "Acquiring lock for branch: ${branch}"

    # Ensure session branch directory exists
    mkdir -p "$lock_dir"

    if [[ -f "$lock_file" ]]; then
        local lock_pid
        lock_pid=$(parse_lock_value "$lock_file" "pid")
        local lock_ts
        lock_ts=$(parse_lock_value "$lock_file" "timestamp")
        local lock_host
        lock_host=$(parse_lock_value "$lock_file" "hostname")
        local now
        now=$(date +%s)
        local age=$(( now - lock_ts ))

        if pid_alive "$lock_pid"; then
            if [[ "$age" -lt "$STALE_TIMEOUT" ]]; then
                log_fail "Lock held by PID ${lock_pid} on ${lock_host} (age: ${age}s, timeout: ${STALE_TIMEOUT}s)"
                log_info "Lock file: ${lock_file}"
                exit 1
            else
                log_info "Lock exists but is stale (PID ${lock_pid}, age: ${age}s, timeout: ${STALE_TIMEOUT}s)"
                if [[ "$FORCE" == true ]]; then
                    log_info "Force flag set — breaking stale lock"
                    rm -f "$lock_file"
                else
                    log_fail "Stale lock detected. Use --force to break it."
                    log_info "Lock file: ${lock_file}"
                    exit 1
                fi
            fi
        else
            log_info "Lock exists but PID ${lock_pid} is not alive — removing stale lock"
            rm -f "$lock_file"
        fi
    fi

    # Write new lock
    write_lock "$lock_file" "$branch"
    log_pass "Lock acquired: ${lock_file} (PID: $$)"

    # Trap EXIT to auto-release
    trap 'cmd_unlock "'"$branch"'"' EXIT
}

# ── Lock Unlock ─────────────────────────────────────────────────────────────

cmd_unlock() {
    local branch="$1"
    local lock_file
    lock_file=$(lock_file_path "$branch")

    if [[ ! -f "$lock_file" ]]; then
        log_info "No lock file found for branch: ${branch}"
        return 0
    fi

    local lock_pid
    lock_pid=$(parse_lock_value "$lock_file" "pid")

    # Only allow unlocking if we hold the lock or --force
    if [[ "$lock_pid" != "$$" && "$FORCE" != true ]]; then
        log_fail "Cannot unlock — lock held by PID ${lock_pid} (current PID: $$). Use --force to override."
        exit 1
    fi

    rm -f "$lock_file"
    log_pass "Lock released: ${lock_file}"
}

# ── Lock Check ──────────────────────────────────────────────────────────────

cmd_check() {
    local branch="$1"
    local lock_file
    lock_file=$(lock_file_path "$branch")

    log_section "Checking lock for branch: ${branch}"

    if [[ ! -f "$lock_file" ]]; then
        log_pass "No lock — branch is free"
        return 0
    fi

    local lock_pid
    lock_pid=$(parse_lock_value "$lock_file" "pid")
    local lock_ts
    lock_ts=$(parse_lock_value "$lock_file" "timestamp")
    local lock_host
    lock_host=$(parse_lock_value "$lock_file" "hostname")
    local lock_branch
    lock_branch=$(parse_lock_value "$lock_file" "branch")
    local now
    now=$(date +%s)
    local age=$(( now - lock_ts ))

    echo "  Lock file:  ${lock_file}"
    echo "  PID:        ${lock_pid}"
    echo "  Host:       ${lock_host}"
    echo "  Branch:     ${lock_branch}"
    echo "  Timestamp:  ${lock_ts} ($(date -r "$lock_ts" 2>/dev/null || echo "N/A"))"
    echo "  Age:        ${age}s"

    if pid_alive "$lock_pid"; then
        if [[ "$age" -ge "$STALE_TIMEOUT" ]]; then
            log_info "Lock is alive but stale (age: ${age}s, timeout: ${STALE_TIMEOUT}s)"
            EXIT_CODE=1
        else
            log_info "Lock is held by active PID ${lock_pid} on ${lock_host} (age: ${age}s)"
            EXIT_CODE=1
        fi
    else
        log_info "Lock file exists but PID ${lock_pid} is dead — stale lock"
        EXIT_CODE=1
    fi
}

# ── Argument Parsing ────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
    case $1 in
        --lock)
            COMMAND="lock"
            shift
            if [[ $# -eq 0 || "$1" == --* ]]; then
                echo -e "${RED}ERROR: --lock requires a branch name${NC}" >&2
                exit 1
            fi
            BRANCH="$1"
            shift
            ;;
        --unlock)
            COMMAND="unlock"
            shift
            if [[ $# -eq 0 || "$1" == --* ]]; then
                echo -e "${RED}ERROR: --unlock requires a branch name${NC}" >&2
                exit 1
            fi
            BRANCH="$1"
            shift
            ;;
        --check)
            COMMAND="check"
            shift
            if [[ $# -eq 0 || "$1" == --* ]]; then
                echo -e "${RED}ERROR: --check requires a branch name${NC}" >&2
                exit 1
            fi
            BRANCH="$1"
            shift
            ;;
        --stale-timeout)
            shift
            if [[ $# -eq 0 ]]; then
                echo -e "${RED}ERROR: --stale-timeout requires a number${NC}" >&2
                exit 1
            fi
            STALE_TIMEOUT="$1"
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --help)
            usage
            ;;
        *)
            echo -e "${RED}ERROR: Unknown option: $1${NC}" >&2
            usage
            ;;
    esac
done

# ── Validation ──────────────────────────────────────────────────────────────

if [[ -z "$COMMAND" ]]; then
    echo -e "${RED}ERROR: One of --lock, --unlock, or --check is required${NC}" >&2
    usage
fi

if [[ ! "$STALE_TIMEOUT" =~ ^[0-9]+$ ]]; then
    echo -e "${RED}ERROR: --stale-timeout must be a positive integer${NC}" >&2
    exit 1
fi

# ── Dispatch ────────────────────────────────────────────────────────────────

case "$COMMAND" in
    lock)
        cmd_lock "$BRANCH"
        ;;
    unlock)
        cmd_unlock "$BRANCH"
        ;;
    check)
        cmd_check "$BRANCH"
        ;;
esac

exit $EXIT_CODE