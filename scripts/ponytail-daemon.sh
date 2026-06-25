#!/usr/bin/env bash
set -euo pipefail

log_pass() { echo -e "\033[32m✓ $1\033[0m"; }
log_fail() { echo -e "\033[31m✗ $1\033[0m"; }
log_info() { echo -e "\033[34mℹ $1\033[0m"; }
log_verbose() { [[ "${VERBOSE:-0}" == "1" ]] && echo -e "\033[33m⋯ $1\033[0m"; }

usage() {
    cat << EOF
Usage: ponytail-daemon.sh [OPTIONS]

Continuous ponytail debt checking daemon.

OPTIONS:
  --interval SEC        Check interval in seconds (default: 60)
  --max-debt N          Max debt items before alert (default: 10)
  --directory DIR       Directory to monitor (default: .)
  --alert-mode MODE     Alert mode: warn|block|slack (default: warn)
  --log FILE            Log file for daemon output (default: ponytail-daemon.log)
  --pid-file FILE       PID file for daemon management (default: ponytail-daemon.pid)
  --stop                Stop the running daemon
  --status              Show daemon status
  --dry-run             Run once and exit (no daemon loop)
  --verbose             Show detailed checking output
  --json                Output results as JSON
  --help                Show this help

EXAMPLES:
  ponytail-daemon.sh --interval 30 --max-debt 5
  ponytail-daemon.sh --stop
  ponytail-daemon.sh --status
EOF
}

INTERVAL=60
MAX_DEBT=10
DIRECTORY="."
ALERT_MODE="warn"
LOG_FILE="ponytail-daemon.log"
PID_FILE="ponytail-daemon.pid"
DRY_RUN=0
VERBOSE=0
JSON_OUTPUT=0
ACTION="start"

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --interval) INTERVAL="$2"; shift 2 ;;
            --max-debt) MAX_DEBT="$2"; shift 2 ;;
            --directory) DIRECTORY="$2"; shift 2 ;;
            --alert-mode) ALERT_MODE="$2"; shift 2 ;;
            --log) LOG_FILE="$2"; shift 2 ;;
            --pid-file) PID_FILE="$2"; shift 2 ;;
            --stop) ACTION="stop"; shift ;;
            --status) ACTION="status"; shift ;;
            --dry-run) DRY_RUN=1; shift ;;
            --verbose) VERBOSE=1; shift ;;
            --json) JSON_OUTPUT=1; shift ;;
            --help|-h) usage; exit 0 ;;
            *) log_fail "Unknown argument: $1"; usage; exit 1 ;;
        esac
    done
}

get_timestamp() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
get_epoch_ms() { date +%s%3N; }

check_ponytail_debt() {
    local debt_count=0
    local ponytail_files=$(grep -rl "ponytail:" "$DIRECTORY" --include="*.sh" --include="*.ts" --include="*.md" 2>/dev/null || echo "")
    if [[ -n "$ponytail_files" ]]; then
        debt_count=$(echo "$ponytail_files" | wc -l | tr -d ' ')
    fi
    return $debt_count
}

run_daemon() {
    log_info "Starting ponytail daemon (interval: $INTERVALs, max-debt: $MAX_DEBT)"
    while true; do
        check_ponytail_debt
        local debt_count=$?
        if [[ "$debt_count" -gt "$MAX_DEBT" ]]; then
            case "$ALERT_MODE" in
                warn) log_fail "Ponytail debt: $debt_count > $MAX_DEBT" ;;
                block) 
                    log_fail "Ponytail debt exceeds limit ($debt_count > $MAX_DEBT). Blocking."
                    echo "$(get_timestamp) DEBT_BLOCK $debt_count" >> "$LOG_FILE"
                    ;;
                slack) log_info "Slack alert: ponytail debt $debt_count" ;;
            esac
        else
            log_pass "Ponytail debt OK: $debt_count <= $MAX_DEBT"
        fi
        log_verbose "Sleeping $INTERVAL seconds..."
        sleep "$INTERVAL" || break
        if [[ "$DRY_RUN" -eq 1 ]]; then
            log_info "Dry run complete, exiting"
            break
        fi
    done
}

stop_daemon() {
    if [[ -f "$PID_FILE" ]]; then
        local pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid"
            rm -f "$PID_FILE"
            log_pass "Daemon stopped (PID: $pid)"
        else
            log_fail "Daemon not running (stale PID file)"
            rm -f "$PID_FILE"
        fi
    else
        log_info "No daemon running"
    fi
}

show_status() {
    if [[ -f "$PID_FILE" ]]; then
        local pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            log_pass "Daemon running (PID: $pid)"
            if [[ -f "$LOG_FILE" ]]; then
                log_info "Last log entries:"
                tail -5 "$LOG_FILE"
            fi
        else
            log_fail "Daemon not running (stale PID file)"
        fi
    else
        log_info "Daemon not running"
    fi
}

main() {
    parse_args "$@"
    case "$ACTION" in
        start)
            if [[ "$DRY_RUN" -eq 1 ]]; then
                run_daemon
            else
                run_daemon &
                echo $! > "$PID_FILE"
                log_pass "Daemon started (PID: $(cat $PID_FILE))"
            fi
            ;;
        stop) stop_daemon ;;
        status) show_status ;;
        *) log_fail "Unknown action: $ACTION"; exit 1 ;;
    esac
}

main "$@"