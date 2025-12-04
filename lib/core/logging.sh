#!/usr/bin/env bash
# logging.sh - Logging system with built-in rotation
# Part of wallshow - Professional Wallpaper Manager for Wayland/X11

# ============================================================================
# LOG ROTATION
# ============================================================================

# Track last rotation check to avoid stat() on every log call
declare -g _LAST_ROTATION_CHECK=0
declare -g _ROTATION_CHECK_INTERVAL=100 # Check every N log calls
declare -g _LOG_CALL_COUNT=0

# Rotate log file if it exceeds max size
_maybe_rotate_log() {
	# Skip if LOG_FILE not set yet
	[[ -z "${LOG_FILE:-}" || ! -f "${LOG_FILE}" ]] && return 0

	# Throttle rotation checks (not every log call)
	_LOG_CALL_COUNT=$((_LOG_CALL_COUNT + 1))
	if [[ $((_LOG_CALL_COUNT % _ROTATION_CHECK_INTERVAL)) -ne 0 ]]; then
		return 0
	fi

	# Get max size from config (default 512KB)
	local max_size_kb
	max_size_kb=$(get_config '.behavior.max_log_size_kb' '512' 2>/dev/null) || max_size_kb=512
	local max_size_bytes=$((max_size_kb * 1024))

	# Get current file size
	local current_size
	current_size=$(stat -c %s "${LOG_FILE}" 2>/dev/null) || return 0

	# Rotate if exceeded
	if [[ ${current_size} -ge ${max_size_bytes} ]]; then
		_rotate_log
	fi
}

# Perform log rotation (keep up to 5 old logs)
_rotate_log() {
	local max_rotations=5

	# Rotate existing logs: .4 -> .5, .3 -> .4, etc.
	for ((i = max_rotations - 1; i >= 1; i--)); do
		local old="${LOG_FILE}.${i}"
		local new="${LOG_FILE}.$((i + 1))"
		if [[ -f "${old}" ]]; then
			mv -f "${old}" "${new}" 2>/dev/null || true
		fi
	done

	# Current log becomes .1
	if [[ -f "${LOG_FILE}" ]]; then
		mv -f "${LOG_FILE}" "${LOG_FILE}.1" 2>/dev/null || true
	fi

	# Create fresh log file
	touch "${LOG_FILE}" 2>/dev/null || true
	chmod 600 "${LOG_FILE}" 2>/dev/null || true

	# Remove oldest if exceeds max
	local oldest="${LOG_FILE}.$((max_rotations + 1))"
	[[ -f "${oldest}" ]] && rm -f "${oldest}" 2>/dev/null
}

# ============================================================================
# LOGGING FUNCTIONS
# ============================================================================

log() {
	local level=$1
	local message=$2
	local timestamp
	timestamp=$(date '+%Y-%m-%d %H:%M:%S')

	local level_str
	case ${level} in
	"${LOG_ERROR}") level_str="ERROR" ;;
	"${LOG_WARN}") level_str="WARN " ;;
	"${LOG_INFO}") level_str="INFO " ;;
	"${LOG_DEBUG}") level_str="DEBUG" ;;
	*) level_str="UNKN " ;;
	esac

	if [[ ${level} -le ${LOG_LEVEL} ]]; then
		local log_line="[${timestamp}] [${level_str}] ${message}"

		# Console output - always to stderr to avoid polluting function output
		if [[ "${IS_DAEMON}" == "false" ]]; then
			# Interactive mode - log to stderr
			echo "${log_line}" >&2
		elif [[ -n "${JOURNAL_STREAM:-}" || -n "${INVOCATION_ID:-}" ]]; then
			# Daemon under systemd - also log to stderr for journald capture
			echo "${log_line}" >&2
		fi

		# Check if rotation needed (throttled)
		_maybe_rotate_log

		# File output
		if ! echo "${log_line}" >>"${LOG_FILE}" 2>/dev/null; then
			# Log file write failed - fallback to stderr only in daemon mode
			# (non-daemon already logged to stderr above)
			if [[ "${IS_DAEMON}" == "true" ]]; then
				echo "${log_line}" >&2
			fi
		fi
	fi
}

log_error() { log "${LOG_ERROR}" "$1"; }
log_warn() { log "${LOG_WARN}" "$1"; }
log_info() { log "${LOG_INFO}" "$1"; }
log_debug() { log "${LOG_DEBUG}" "$1"; }

die() {
	log_error "$1"
	exit "${2:-${E_GENERAL}}"
}
