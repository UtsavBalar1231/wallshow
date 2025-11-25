#!/usr/bin/env bash
# logging.sh - Logging system (rotation handled by logrotate)
# Part of wallshow - Professional Wallpaper Manager for Wayland/X11

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

		# File output - log file is initialized in init_directories()
		# Rotation is handled externally by logrotate (/etc/logrotate.d/wallshow)
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
