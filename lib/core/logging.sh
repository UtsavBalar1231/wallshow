#!/usr/bin/env bash
# logging.sh - Logging system with rotation support
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
			echo "${log_line}" >&2
		fi

		# File output - log file is initialized in init_directories()
		echo "${log_line}" >>"${LOG_FILE}"

		# Rotate if needed (with lock to prevent race condition)
		# Always acquire lock before checking size to avoid TOCTOU race
		local rotate_lock="${LOG_FILE}.rotate.lock"
		local rotate_fd
		exec {rotate_fd}>"${rotate_lock}"
		if flock -n "${rotate_fd}"; then
			local max_size
			max_size=$(get_config '.behavior.max_log_size_kb' '1024')
			local current_size
			current_size=$(du -k "${LOG_FILE}" | cut -f1)

			if [[ ${current_size} -gt ${max_size} ]]; then
				mv "${LOG_FILE}" "${LOG_FILE}.old"
				touch "${LOG_FILE}"
				chmod 600 "${LOG_FILE}"
			fi
			flock -u "${rotate_fd}"
		fi
		exec {rotate_fd}>&-
		rm -f "${rotate_lock}"
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
