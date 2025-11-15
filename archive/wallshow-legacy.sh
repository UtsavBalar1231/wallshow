#!/usr/bin/env bash
# wallshow.sh - Professional Wallpaper Manager for Wayland/X11
# Author: UtsavBalar1231 <utsavbalar1231@gmail.com>
# Version: 1.0.0
# License: MIT
# Requires: bash 5.0+, jq, flock
#
# ============================================================================
# DEPRECATION NOTICE
# ============================================================================
# This is the legacy single-file version of wallshow, archived for reference.
# The production version uses a modular architecture with the entry point at
# bin/wallshow. Please use the modular version for all new installations.
#
# This legacy script will be removed in a future release.
# ============================================================================

set -euo pipefail
IFS=$'\n\t'

# ============================================================================
# CONSTANTS & CONFIGURATION
# ============================================================================

declare -r SCRIPT_NAME="wallshow"
declare -r VERSION="1.0.0"
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
declare -r SCRIPT_PATH

# XDG Base Directory compliance
declare -r XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
declare -r XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
declare -r XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
declare -r XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

# Application directories
declare -r CONFIG_DIR="${XDG_CONFIG_HOME}/${SCRIPT_NAME}"
declare -r STATE_DIR="${XDG_STATE_HOME}/${SCRIPT_NAME}"
declare -r CACHE_DIR="${XDG_CACHE_HOME}/${SCRIPT_NAME}"
declare -r RUNTIME_DIR="${XDG_RUNTIME_DIR}/${SCRIPT_NAME}"

# Critical files
declare -g CONFIG_FILE="${CONFIG_DIR}/config.json"
declare -r STATE_FILE="${STATE_DIR}/state.json"
declare -r LOCK_FILE="${RUNTIME_DIR}/instance.lock"
declare -r SOCKET_FILE="${RUNTIME_DIR}/control.sock"
declare -r PID_FILE="${RUNTIME_DIR}/daemon.pid"
declare -r LOG_FILE="${STATE_DIR}/wallpaper.log"

# Default configuration
declare -r DEFAULT_CONFIG='{
  "wallpaper_dirs": {
    "static": "~/Pictures/wallpapers",
    "animated": "~/Pictures/wallpapers/animated"
  },
  "intervals": {
    "change_seconds": 300,
    "transition_ms": 300,
    "gif_frame_ms": 50
  },
  "behavior": {
    "shuffle": true,
    "exclude_patterns": ["*.tmp", ".*"],
    "battery_optimization": true,
    "max_cache_size_mb": 500,
    "max_log_size_kb": 1024,
    "debug": false
  },
  "tools": {
    "preferred_static": "auto",
    "preferred_animated": "auto",
    "fallback_chain": ["swww", "swaybg", "feh", "xwallpaper"]
  }
}'

# Exit codes
declare -ri E_SUCCESS=0
declare -ri E_GENERAL=1
declare -ri E_USAGE=2
declare -ri E_NOPERM=3
declare -ri E_LOCKED=5
declare -ri E_DEPENDENCY=8

# Logging levels
declare -ri LOG_ERROR=0
declare -ri LOG_WARN=1
declare -ri LOG_INFO=2
declare -ri LOG_DEBUG=3

# Global state (minimal, most state in JSON)
declare -g LOCK_FD=""
declare -g LOG_LEVEL="${LOG_INFO}"
declare -g IS_DAEMON=false
declare -g CLEANUP_DONE=false
declare -g CONFIG_INITIALIZED=false

# ============================================================================
# INITIALIZATION & CLEANUP
# ============================================================================

cleanup_all_processes() {
	log_debug "Cleaning up all child processes..."

	# Stop animation subprocess
	local animation_pid
	animation_pid=$(read_state '.processes.animation_pid // null')
	if [[ "${animation_pid}" != "null" && -n "${animation_pid}" && "${animation_pid}" =~ ^[0-9]+$ ]] && kill -0 "${animation_pid}" 2>/dev/null; then
		log_debug "Cleaning up animation process (PID: ${animation_pid})"
		kill -TERM "${animation_pid}" 2>/dev/null || true
		sleep 0.2
		kill -KILL "${animation_pid}" 2>/dev/null || true
	fi

	# Stop swaybg processes
	local swaybg_pids
	swaybg_pids=$(read_state '.processes.swaybg_pids // []' | jq -r '.[]')
	if [[ -n "${swaybg_pids}" ]]; then
		while IFS= read -r pid; do
			if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
				log_debug "Cleaning up swaybg process (PID: ${pid})"
				kill -TERM "${pid}" 2>/dev/null || true
				sleep 0.1
				kill -KILL "${pid}" 2>/dev/null || true
			fi
		done <<<"${swaybg_pids}"
	fi

	# Stop swww-daemon process
	local swww_daemon_pid
	swww_daemon_pid=$(read_state '.processes.swww_daemon_pid // null')
	if [[ "${swww_daemon_pid}" != "null" && -n "${swww_daemon_pid}" && "${swww_daemon_pid}" =~ ^[0-9]+$ ]] && kill -0 "${swww_daemon_pid}" 2>/dev/null; then
		log_debug "Cleaning up swww-daemon process (PID: ${swww_daemon_pid})"
		kill -TERM "${swww_daemon_pid}" 2>/dev/null || true
		sleep 0.2
		kill -KILL "${swww_daemon_pid}" 2>/dev/null || true
	fi

	# Stop socat socket process
	if [[ -f "${RUNTIME_DIR}/socket.pid" ]]; then
		local socat_pid
		socat_pid=$(<"${RUNTIME_DIR}/socket.pid")
		if kill -0 "${socat_pid}" 2>/dev/null; then
			log_debug "Cleaning up socat process (PID: ${socat_pid})"
			kill -TERM "${socat_pid}" 2>/dev/null || true
			sleep 0.1
			kill -KILL "${socat_pid}" 2>/dev/null || true
		fi
		rm -f "${RUNTIME_DIR}/socket.pid"
	fi

	log_debug "All child processes cleaned up"
}

init_directories() {
	local dir
	for dir in "${CONFIG_DIR}" "${STATE_DIR}" "${CACHE_DIR}" "${RUNTIME_DIR}"; do
		if [[ ! -d "${dir}" ]]; then
			mkdir -p "${dir}" || die "Failed to create directory: ${dir}"
			chmod 700 "${dir}"
		fi
	done

	# Initialize log file if it doesn't exist
	if [[ ! -f "${LOG_FILE}" ]]; then
		touch "${LOG_FILE}" || die "Failed to create log file: ${LOG_FILE}"
		chmod 600 "${LOG_FILE}"
	fi
}

init_config() {
	# Guard: only initialize once to avoid excessive logging
	if [[ "${CONFIG_INITIALIZED}" == "true" ]]; then
		return 0
	fi

	if [[ ! -f "${CONFIG_FILE}" ]]; then
		log_info "Creating default configuration at ${CONFIG_FILE}"
		echo "${DEFAULT_CONFIG}" | jq '.' >"${CONFIG_FILE}" || die "Failed to create config file"
		chmod 600 "${CONFIG_FILE}"
	fi

	# Validate config
	if ! jq -e '.' "${CONFIG_FILE}" >/dev/null 2>&1; then
		die "Invalid JSON in config file: ${CONFIG_FILE}"
	fi

	CONFIG_INITIALIZED=true
}

init_state() {
	local default_state='{
        "version": "'"${VERSION}"'",
        "status": "stopped",
        "current_wallpaper": null,
        "history": [],
        "stats": {
            "changes_count": 0,
            "last_change": null,
            "uptime_seconds": 0
        },
        "cache": {
            "static": {
                "files": [],
                "last_scan": null,
                "count": 0
            },
            "animated": {
                "files": [],
                "last_scan": null,
                "count": 0
            }
        },
        "processes": {
            "main_pid": null,
            "animation_pid": null,
            "swaybg_pids": [],
            "swww_daemon_pid": null
        }
    }'

	if [[ ! -f "${STATE_FILE}" ]]; then
		echo "${default_state}" | jq '.' >"${STATE_FILE}" || die "Failed to create state file"
		chmod 600 "${STATE_FILE}"
	else
		# Validate existing state
		if ! jq -e '.' "${STATE_FILE}" >/dev/null 2>&1; then
			log_warn "Corrupted state file, recreating..."
			echo "${default_state}" | jq '.' >"${STATE_FILE}"
		fi
	fi
}

cleanup() {
	if [[ "${CLEANUP_DONE}" == "true" ]]; then
		return
	fi
	CLEANUP_DONE=true

	log_debug "Running cleanup..."

	# Clean up all child processes first
	cleanup_all_processes

	# Update state before exit (use atomic update for safety)
	if [[ -f "${STATE_FILE}" ]]; then
		update_state_atomic '.status = "stopped" | .processes.main_pid = null'
	fi

	# Release lock
	if [[ -n "${LOCK_FD}" ]]; then
		flock -u "${LOCK_FD}" 2>/dev/null || true
		exec {LOCK_FD}>&- 2>/dev/null || true
	fi

	# Clean runtime files
	rm -f "${SOCKET_FILE}" "${PID_FILE}" 2>/dev/null || true

	log_info "Cleanup completed"
}

# ============================================================================
# LOGGING
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

log_error() { log ${LOG_ERROR} "$1"; }
log_warn() { log ${LOG_WARN} "$1"; }
log_info() { log ${LOG_INFO} "$1"; }
log_debug() { log ${LOG_DEBUG} "$1"; }

die() {
	log_error "$1"
	exit "${2:-${E_GENERAL}}"
}

# ============================================================================
# INSTANCE LOCKING
# ============================================================================

acquire_lock() {
	local timeout=${1:-0}

	# Create lock file if it doesn't exist
	touch "${LOCK_FILE}" || die "Cannot create lock file" ${E_NOPERM}

	# Open lock file and get file descriptor
	exec {LOCK_FD}<>"${LOCK_FILE}"

	# Try to acquire exclusive lock
	if [[ ${timeout} -gt 0 ]]; then
		if ! flock -w "${timeout}" -x "${LOCK_FD}"; then
			log_error "Another instance is running (timeout after ${timeout}s)"
			exit ${E_LOCKED}
		fi
	else
		if ! flock -n -x "${LOCK_FD}"; then
			log_error "Another instance is running"
			exit ${E_LOCKED}
		fi
	fi

	# Write our PID to lock file
	echo $$ >"${LOCK_FILE}"

	log_debug "Lock acquired (PID: $$)"
	return 0
}

release_lock() {
	if [[ -n "${LOCK_FD}" ]]; then
		flock -u "${LOCK_FD}" 2>/dev/null || true
		exec {LOCK_FD}>&- 2>/dev/null || true
		LOCK_FD=""
		log_debug "Lock released"
	fi
}

check_instance() {
	# Defense-in-depth instance checking:
	# 1. Try to acquire lock (atomic check)
	# 2. Validate PID file if lock held
	# 3. Clean stale PID if process dead

	local test_fd
	exec {test_fd}>"${LOCK_FILE}"

	if flock -n "${test_fd}"; then
		# Lock acquired - check for stale PID file
		if [[ -f "${PID_FILE}" ]]; then
			local old_pid
			old_pid=$(cat "${PID_FILE}" 2>/dev/null)
			if [[ -n "${old_pid}" ]] && ! kill -0 "${old_pid}" 2>/dev/null; then
				log_warn "Removing stale PID file (process ${old_pid} not running)"
				rm -f "${PID_FILE}"
			fi
		fi

		# Release lock - no instance running
		flock -u "${test_fd}"
		exec {test_fd}>&-
		return 1
	else
		# Lock held - validate PID is actually alive
		if [[ -f "${PID_FILE}" ]]; then
			local running_pid
			running_pid=$(cat "${PID_FILE}" 2>/dev/null)
			if [[ -n "${running_pid}" && "${running_pid}" =~ ^[0-9]+$ ]] && kill -0 "${running_pid}" 2>/dev/null; then
				# Valid instance running
				exec {test_fd}>&-
				return 0
			fi
		fi

		# Lock held but PID invalid - possible startup race
		# Conservative: assume instance is starting
		exec {test_fd}>&-
		return 0
	fi
}

# ============================================================================
# STATE MANAGEMENT
# ============================================================================

read_state() {
	local query="${1:-.}"

	if [[ ! -f "${STATE_FILE}" ]]; then
		init_state
	fi

	jq -r "${query}" "${STATE_FILE}" 2>/dev/null || {
		log_error "Failed to read state with query: ${query}"
		echo "null"
	}
}

update_state_atomic() {
	local update="$1"
	local max_retries=5
	local retry=0

	while [[ ${retry} -lt ${max_retries} ]]; do
		local temp_file
		temp_file=$(mktemp "${STATE_FILE}.XXXXXX")

		if jq "${update}" "${STATE_FILE}" >"${temp_file}" 2>/dev/null; then
			mv -f "${temp_file}" "${STATE_FILE}"
			chmod 600 "${STATE_FILE}"
			log_debug "State updated: ${update}"
			return 0
		else
			rm -f "${temp_file}"
			log_debug "State update failed (attempt $((retry + 1))/${max_retries}): ${update}"
		fi

		retry=$((retry + 1))
		sleep 0.1
	done

	log_error "Failed to update state after ${max_retries} retries: ${update}"
	return 1
}

add_to_history() {
	local wallpaper="$1"
	local max_history=100

	# Properly escape both wallpaper path and timestamp for JSON to prevent injection
	local escaped_wallpaper
	escaped_wallpaper=$(printf '%s' "${wallpaper}" | jq -Rs .)
	local timestamp
	timestamp=$(date -Iseconds)
	local escaped_timestamp
	escaped_timestamp=$(printf '%s' "${timestamp}" | jq -Rs .)

	update_state_atomic "
        .history = ([${escaped_wallpaper}] + .history | unique | .[0:${max_history}]) |
        .stats.last_change = ${escaped_timestamp} |
        .stats.changes_count += 1
    "
}

# ============================================================================
# CONFIGURATION MANAGEMENT
# ============================================================================

get_config() {
	local query="$1"
	local default="${2:-}"

	if [[ ! -f "${CONFIG_FILE}" ]]; then
		init_config
	fi

	local config_value
	config_value=$(jq -r "${query}" "${CONFIG_FILE}" 2>/dev/null || echo "null")

	if [[ "${config_value}" == "null" || -z "${config_value}" ]]; then
		echo "${default}"
	else
		echo "${config_value}"
	fi
}

reload_config() {
	log_info "Reloading configuration..."

	# Validate config file
	if ! jq -e '.' "${CONFIG_FILE}" >/dev/null 2>&1; then
		log_error "Invalid configuration file, keeping current config"
		return 1
	fi

	# Update log level if changed
	if [[ "$(get_config '.behavior.debug' 'false')" == "true" ]]; then
		LOG_LEVEL=${LOG_DEBUG}
	else
		LOG_LEVEL=${LOG_INFO}
	fi

	log_info "Configuration reloaded"
	return 0
}

# ============================================================================
# PATH VALIDATION & SECURITY
# ============================================================================

validate_path() {
	local path="$1"
	local base_dir="$2"

	# Expand tilde and resolve path
	path="${path/#\~/$HOME}"
	local resolved
	resolved=$(readlink -f "${path}" 2>/dev/null) || return 1

	# Ensure path exists
	[[ -e "${resolved}" ]] || return 1

	# If base_dir provided, ensure path is within it
	if [[ -n "${base_dir}" ]]; then
		base_dir="${base_dir/#\~/$HOME}"
		base_dir=$(readlink -f "${base_dir}" 2>/dev/null) || return 1

		# Check if resolved path starts with base_dir
		[[ "${resolved}" == "${base_dir}"/* || "${resolved}" == "${base_dir}" ]] || return 1
	fi

	echo "${resolved}"
	return 0
}

sanitize_filename() {
	local filename="$1"
	# Remove path components and dangerous characters
	basename "${filename}" | tr -d '\0' | sed 's/[^a-zA-Z0-9._-]/_/g'
}

# ============================================================================
# PROCESS MANAGEMENT
# ============================================================================

daemonize() {
	log_info "Starting in daemon mode..."

	# Pre-flight check: verify no instance already running
	if check_instance; then
		die "Daemon already running" ${E_LOCKED}
	fi

	# Fork and exit parent
	if [[ "${IS_DAEMON}" == "false" ]]; then
		IS_DAEMON=true

		# Redirect output BEFORE forking
		exec 1>"${STATE_DIR}/daemon.out"
		exec 2>"${STATE_DIR}/daemon.err"
		exec 0</dev/null

		# Start daemon in background
		# NOTE: After setsid, $BASHPID contains the actual daemon PID
		# The parent cannot reliably capture this via $!, so the child writes it
		(
			# Create new session (detach from controlling terminal)
			setsid 2>/dev/null || true

			# Acquire lock IMMEDIATELY (prevent race with other instances)
			acquire_lock

			# Write PID using $BASHPID (explicit PID in subshell context)
			# In a subshell, $$ would be the parent's PID, $BASHPID is this process
			echo "${BASHPID}" >"${PID_FILE}"

			# Update state with daemon PID and starting status
			update_state_atomic '.processes.main_pid = '"${BASHPID}"' | .status = "starting"' || log_warn "Failed to store main daemon PID in state"

			log_info "Daemon process started (PID: ${BASHPID})"

			# Create IPC socket AFTER acquiring lock (security: only daemon can create socket)
			create_socket

			# Set up signal handlers
			trap 'handle_signal TERM' TERM
			trap 'handle_signal INT' INT
			trap 'handle_signal HUP' HUP
			trap 'cleanup' EXIT

			# Run main loop
			main_loop
		) &

		# Parent exits immediately - daemon now runs independently
		# NOTE: $! here is not the actual daemon PID due to setsid
		# The child process writes its own PID above
		log_info "Daemon started, parent exiting"
		echo "Daemon started. Check status with: $0 status"
		exit 0
	fi
}

handle_signal() {
	local signal="$1"
	log_info "Received signal: ${signal}"

	case "${signal}" in
	TERM | INT)
		log_info "Shutting down gracefully..."
		update_state_atomic '.status = "stopping"'
		cleanup
		exit 0
		;;
	HUP)
		log_info "Reloading configuration..."
		reload_config
		;;
	*)
		log_warn "Unhandled signal: ${signal}"
		;;
	esac
}

# ============================================================================
# WALLPAPER DISCOVERY & CACHING
# ============================================================================

discover_wallpapers() {
	local dir="$1"
	local cache_key="$2"
	local force_refresh="${3:-false}"

	# Validate directory
	dir=$(validate_path "${dir}" "") || {
		log_error "Invalid directory: ${dir}"
		return 1
	}

	# Check cache
	local cached_list
	local last_scan
	cached_list=$(jq -r ".cache.${cache_key}.files // []" "${STATE_FILE}" 2>/dev/null || echo "[]")
	last_scan=$(jq -r ".cache.${cache_key}.last_scan // 0" "${STATE_FILE}" 2>/dev/null || echo "0")

	local now
	now=$(date +%s)
	local cache_age=$((now - last_scan))
	local max_age=3600 # 1 hour

	if [[ "${force_refresh}" == "false" && ${cache_age} -lt ${max_age} && "${cached_list}" != "[]" ]]; then
		log_debug "Using cached wallpaper list for ${cache_key}"
		echo "${cached_list}"
		return 0
	fi

	log_info "Scanning directory: ${dir}"

	# Build exclude pattern arguments as an array
	local -a exclude_args=()
	local exclude_patterns
	# Get exclude patterns as a JSON array then extract values
	exclude_patterns=$(jq -r '.behavior.exclude_patterns[]?' "${CONFIG_FILE}" 2>/dev/null || echo "")

	if [[ -n "${exclude_patterns}" ]]; then
		while IFS= read -r pattern; do
			if [[ -n "${pattern}" ]]; then
				# Validate pattern contains only safe shell glob characters to prevent command injection
				if [[ "${pattern}" =~ ^[a-zA-Z0-9.*_-]+$ ]]; then
					exclude_args+=("!" "-name" "${pattern}")
				else
					log_warn "Skipping invalid exclude pattern (security): ${pattern}"
				fi
			fi
		done <<<"${exclude_patterns}"
	fi

	# Execute find and build file array, then convert to JSON once (O(n) instead of O(n²))
	local -a file_array=()
	local count=0

	# Find wallpaper files - log permission errors instead of suppressing
	local find_errors
	find_errors=$(mktemp)
	while IFS= read -r file; do
		[[ -z "${file}" ]] && continue
		file_array+=("${file}")
		count=$((count + 1))
	done < <(find "${dir}" -type f \( \
		-iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \
		-o -iname "*.webp" -o -iname "*.gif" -o -iname "*.bmp" \
		\) "${exclude_args[@]}" 2>"${find_errors}")

	# Log any permission or access errors from find
	if [[ -s "${find_errors}" ]]; then
		while IFS= read -r err_line; do
			log_warn "find: ${err_line}"
		done <"${find_errors}"
	fi
	rm -f "${find_errors}"

	log_info "Found ${count} wallpapers in ${dir}"

	# Convert file array to JSON in one operation
	local files_json
	if [[ ${count} -eq 0 ]]; then
		files_json="[]"
	else
		files_json=$(printf '%s\n' "${file_array[@]}" | jq -Rs 'split("\n") | map(select(length > 0))')
	fi

	# Update cache (use atomic for consistency)
	update_state_atomic ".cache.${cache_key} = {
        \"files\": ${files_json},
        \"last_scan\": ${now},
        \"count\": ${count}
    }"

	echo "${files_json}"
}

get_wallpaper_list() {
	local use_animated="${1:-false}"
	local wallpaper_dir

	if [[ "${use_animated}" == "true" ]]; then
		wallpaper_dir=$(get_config '.wallpaper_dirs.animated' "$HOME/Pictures/wallpapers/animated")
		wallpaper_dir="${wallpaper_dir/#\~/$HOME}"
		discover_wallpapers "${wallpaper_dir}" "animated" "false"
	else
		wallpaper_dir=$(get_config '.wallpaper_dirs.static' "$HOME/Pictures/wallpapers")
		wallpaper_dir="${wallpaper_dir/#\~/$HOME}"
		discover_wallpapers "${wallpaper_dir}" "static" "false"
	fi
}

select_random_wallpaper() {
	local use_animated="${1:-false}"
	local wallpapers
	wallpapers=$(get_wallpaper_list "${use_animated}")

	if [[ "${wallpapers}" == "[]" || -z "${wallpapers}" ]]; then
		log_error "No wallpapers found"
		return 1
	fi

	# Try selecting a valid wallpaper (retry if file was deleted)
	local selected
	local attempts=0
	while [[ ${attempts} -lt 10 ]]; do
		selected=$(echo "${wallpapers}" | jq -r '.[] | select(. != null)' | shuf -n1)

		if [[ -z "${selected}" ]]; then
			log_error "Failed to select wallpaper"
			return 1
		fi

		# Validate file exists (cache may be stale)
		if [[ -f "${selected}" ]]; then
			echo "${selected}"
			return 0
		fi

		log_warn "Cached wallpaper no longer exists: ${selected}"
		attempts=$((attempts + 1))
	done

	log_error "Failed to find valid wallpaper after 10 attempts (cache may be stale)"
	return 1
}

# ============================================================================
# TOOL DETECTION & WALLPAPER SETTING
# ============================================================================

detect_display_server() {
	if [[ -n "${WAYLAND_DISPLAY}" ]]; then
		echo "wayland"
	elif [[ -n "${DISPLAY}" ]]; then
		echo "x11"
	else
		echo "unknown"
	fi
}

detect_available_tools() {
	local tools=()
	local tool_commands=("swww" "swaybg" "hyprpaper" "mpvpaper" "feh" "xwallpaper" "nitrogen")

	for tool in "${tool_commands[@]}"; do
		if command -v "${tool}" &>/dev/null; then
			tools+=("${tool}")
			log_debug "Found wallpaper tool: ${tool}"
		fi
	done

	printf '%s\n' "${tools[@]}"
}

set_wallpaper_swww() {
	local image="$1"
	local transition_ms="${2:-}"

	# Use passed transition or read from config
	if [[ -z "${transition_ms}" ]]; then
		transition_ms=$(get_config '.intervals.transition_ms' '300')
	fi

	# Ensure daemon is running
	if ! pgrep -x "swww-daemon" &>/dev/null; then
		log_debug "Starting swww-daemon"
		swww-daemon --format xrgb &
		local swww_pid=$!
		update_state_atomic ".processes.swww_daemon_pid = ${swww_pid}" || log_warn "Failed to store swww-daemon PID"
		log_debug "Started swww-daemon with PID: ${swww_pid}"
		sleep 0.5 # Give daemon time to start
	fi

	# Set wallpaper with transition
	if swww img "${image}" \
		--transition-type random \
		--transition-duration "$((transition_ms / 1000)).${transition_ms:(-3)}" \
		2>/dev/null; then
		log_debug "Set wallpaper with swww (transition: ${transition_ms}ms): ${image}"
		return 0
	fi

	return 1
}

set_wallpaper_swaybg() {
	local image="$1"

	# Kill existing swaybg instances spawned by us
	local our_pids
	our_pids=$(read_state '.processes.swaybg_pids // []' | jq -r '.[]')
	if [[ -n "${our_pids}" ]]; then
		while IFS= read -r pid; do
			if kill -0 "${pid}" 2>/dev/null; then
				kill -TERM "${pid}" 2>/dev/null || true
				# Wait briefly for graceful exit
				sleep 0.2
				# Force kill if still alive
				if kill -0 "${pid}" 2>/dev/null; then
					kill -KILL "${pid}" 2>/dev/null || true
				fi
			fi
		done <<<"${our_pids}"
	fi

	# Start new instance
	swaybg -i "${image}" -m fill &
	local new_pid=$!

	# Update state with new PID
	update_state_atomic ".processes.swaybg_pids = [${new_pid}]"

	log_debug "Set wallpaper with swaybg: ${image} (PID: ${new_pid})"
	return 0
}

set_wallpaper_feh() {
	local image="$1"
	local feh_errors
	feh_errors=$(mktemp)
	chmod 600 "${feh_errors}" # Secure immediately

	if feh --bg-fill "${image}" 2>"${feh_errors}"; then
		rm -f "${feh_errors}"
		log_debug "Set wallpaper with feh: ${image}"
		return 0
	fi

	log_error "feh failed to set wallpaper:"
	while IFS= read -r err_line; do
		log_error "  ${err_line}"
	done <"${feh_errors}"
	rm -f "${feh_errors}"
	return 1
}

set_wallpaper_xwallpaper() {
	local image="$1"
	local xw_errors
	xw_errors=$(mktemp)
	chmod 600 "${xw_errors}" # Secure immediately

	if xwallpaper --zoom "${image}" 2>"${xw_errors}"; then
		rm -f "${xw_errors}"
		log_debug "Set wallpaper with xwallpaper: ${image}"
		return 0
	fi

	log_error "xwallpaper failed to set wallpaper:"
	while IFS= read -r err_line; do
		log_error "  ${err_line}"
	done <"${xw_errors}"
	rm -f "${xw_errors}"
	return 1
}

set_wallpaper() {
	local image="$1"
	local transition_ms="${2:-}"

	# Validate image path
	image=$(validate_path "${image}" "") || {
		log_error "Invalid image path: ${image}"
		return 1
	}

	# Check if file exists and is readable
	if [[ ! -r "${image}" ]]; then
		log_error "Cannot read image: ${image}"
		return 1
	fi

	local display_server
	display_server=$(detect_display_server)
	log_debug "Display server: ${display_server}"

	# Get preferred tool from config
	local preferred_tool
	preferred_tool=$(get_config '.tools.preferred_static' 'auto')

	# Try preferred tool first if specified
	if [[ "${preferred_tool}" != "auto" ]] && command -v "${preferred_tool}" &>/dev/null; then
		case "${preferred_tool}" in
		swww) set_wallpaper_swww "${image}" "${transition_ms}" && return 0 ;;
		swaybg) set_wallpaper_swaybg "${image}" && return 0 ;;
		feh) set_wallpaper_feh "${image}" && return 0 ;;
		xwallpaper) set_wallpaper_xwallpaper "${image}" && return 0 ;;
		esac
	fi

	# Fallback chain based on display server
	if [[ "${display_server}" == "wayland" ]]; then
		set_wallpaper_swww "${image}" "${transition_ms}" && return 0
		set_wallpaper_swaybg "${image}" && return 0
	else
		set_wallpaper_feh "${image}" && return 0
		set_wallpaper_xwallpaper "${image}" && return 0
	fi

	# Last resort: try all available tools
	local available_tools
	available_tools=$(detect_available_tools)

	while IFS= read -r tool; do
		case "${tool}" in
		swww) set_wallpaper_swww "${image}" "${transition_ms}" && return 0 ;;
		swaybg) set_wallpaper_swaybg "${image}" && return 0 ;;
		feh) set_wallpaper_feh "${image}" && return 0 ;;
		xwallpaper) set_wallpaper_xwallpaper "${image}" && return 0 ;;
		esac
	done <<<"${available_tools}"

	log_error "Failed to set wallpaper with any available tool"
	return 1
}

# ============================================================================
# BATTERY DETECTION
# ============================================================================

get_battery_status() {
	local battery_status="unknown"

	# Try multiple battery paths
	local battery_paths=(
		"/sys/class/power_supply/BAT0/status"
		"/sys/class/power_supply/BAT1/status"
		"/sys/class/power_supply/BATT/status"
	)

	for path in "${battery_paths[@]}"; do
		if [[ -r "${path}" ]]; then
			battery_status=$(tr '[:upper:]' '[:lower:]' <"${path}")
			log_debug "Battery status from ${path}: ${battery_status}"
			break
		fi
	done

	echo "${battery_status}"
}

should_use_animated() {
	local battery_optimization
	battery_optimization=$(get_config '.behavior.battery_optimization' 'true')

	if [[ "${battery_optimization}" != "true" ]]; then
		echo "true"
		return
	fi

	local battery_status
	battery_status=$(get_battery_status)

	if [[ "${battery_status}" == "discharging" ]]; then
		echo "false"
	else
		echo "true"
	fi
}

# ============================================================================
# GIF ANIMATION HANDLING
# ============================================================================

extract_gif_frames() {
	local gif_path="$1"
	local output_dir="$2"

	if ! command -v magick &>/dev/null && ! command -v convert &>/dev/null; then
		log_error "ImageMagick is required for GIF extraction"
		return 1
	fi

	log_info "Extracting frames from: ${gif_path}"

	# Use convert or magick based on availability
	local convert_cmd="convert"
	command -v magick &>/dev/null && convert_cmd="magick"

	# Extract frames and capture errors
	local extract_errors
	extract_errors=$(mktemp)
	chmod 600 "${extract_errors}" # Secure immediately

	if ${convert_cmd} "${gif_path}" -coalesce "${output_dir}/frame_%04d.png" 2>"${extract_errors}"; then
		rm -f "${extract_errors}"
		log_info "Extracted frames to: ${output_dir}"
	else
		# Log extraction errors
		log_error "Failed to extract GIF frames from ${gif_path}:"
		while IFS= read -r err_line; do
			log_error "  ${err_line}"
		done <"${extract_errors}"
		rm -f "${extract_errors}"
		return 1
	fi

	# Extract native frame delays (in centiseconds, GIF standard)
	log_info "Extracting native frame delays from: ${gif_path}"
	local identify_cmd="identify"
	command -v magick &>/dev/null && identify_cmd="magick identify"

	local delays_json
	if delays_json=$(${identify_cmd} -format "%T\n" "${gif_path}" 2>/dev/null | jq -s '.'); then
		echo "${delays_json}" >"${output_dir}/delays.json"
		local frame_count
		frame_count=$(echo "${delays_json}" | jq 'length')
		log_info "Extracted ${frame_count} frame delays (centiseconds): ${delays_json}"
	else
		log_warn "Could not extract native frame delays, will use config default"
		echo '[]' >"${output_dir}/delays.json"
	fi

	return 0
}

animate_gif_frames() {
	local frame_dir="$1"
	local frame_delay="$2"

	local frames=()
	while IFS= read -r frame; do
		frames+=("${frame}")
	done < <(find "${frame_dir}" -name "frame_*.png" | sort -V)

	if [[ ${#frames[@]} -eq 0 ]]; then
		log_error "No frames found in: ${frame_dir}"
		return 1
	fi

	# Load native frame delays from delays.json (in centiseconds)
	local delays=()
	local delays_file="${frame_dir}/delays.json"
	if [[ -f "${delays_file}" ]]; then
		while IFS= read -r delay_cs; do
			# Convert centiseconds to milliseconds (cs * 10 = ms)
			local delay_ms=$((delay_cs * 10))
			# Apply minimum delay of 10ms for delay=0 frames (prevents CPU busy loop)
			[[ ${delay_ms} -lt 10 ]] && delay_ms=10
			delays+=("${delay_ms}")
		done < <(jq -r '.[]' "${delays_file}" 2>/dev/null || echo "")
	fi

	# Determine if using native delays or config default
	local using_native_delays=false
	if [[ ${#delays[@]} -gt 0 ]]; then
		log_info "Animating ${#frames[@]} frames with native delays"
		using_native_delays=true
	else
		log_info "Animating ${#frames[@]} frames with ${frame_delay}ms delay (config default)"
	fi

	# Animation loop
	local frame_index=0
	local status_check_counter=0
	while true; do
		local current_frame="${frames[${frame_index}]}"

		# Use transition_ms=0 for GIF frames (no transition between frames)
		if set_wallpaper "${current_frame}" 0; then
			log_debug "Displaying frame: ${frame_index}"
		fi

		# Check status every 10 frames instead of every frame (reduces overhead)
		status_check_counter=$((status_check_counter + 1))
		if [[ $((status_check_counter % 10)) -eq 0 ]]; then
			local status
			status=$(read_state '.status')
			if [[ "${status}" != "running" ]]; then
				log_info "Animation stopped (status: ${status})"
				break
			fi
		fi

		# Get delay for current frame (native or config default)
		local current_delay_ms
		if ${using_native_delays} && [[ ${frame_index} -lt ${#delays[@]} ]]; then
			current_delay_ms="${delays[${frame_index}]}"
		else
			current_delay_ms="${frame_delay}"
		fi

		# Move to next frame
		frame_index=$(((frame_index + 1) % ${#frames[@]}))

		# Sleep for frame delay (convert milliseconds to seconds)
		sleep "$(awk "BEGIN {printf \"%.3f\", ${current_delay_ms}/1000}")"
	done
}

handle_animated_wallpaper() {
	local gif_path="$1"

	# Generate cache key from file hash
	local gif_hash
	gif_hash=$(sha256sum "${gif_path}" | cut -d' ' -f1)
	local cache_dir="${CACHE_DIR}/gifs/${gif_hash}"

	# Check if frames are already extracted
	if [[ -d "${cache_dir}" ]] && [[ -f "${cache_dir}/frame_0000.png" ]]; then
		log_info "Using cached frames for: ${gif_path}"
	else
		# Create cache directory
		mkdir -p "${cache_dir}"

		# Extract frames
		if ! extract_gif_frames "${gif_path}" "${cache_dir}"; then
			rm -rf "${cache_dir}"
			return 1
		fi
	fi

	# Get frame delay from config (minimum 10ms to prevent CPU busy loop)
	local frame_delay
	frame_delay=$(get_config '.intervals.gif_frame_ms' '50')
	if [[ ${frame_delay} -lt 10 ]]; then
		log_warn "Frame delay (${frame_delay}ms) too low, using minimum 10ms"
		frame_delay=10
	fi

	# Start animation in background
	# Close inherited lock FD to prevent child from holding daemon lock
	(
		# Close inherited LOCK_FD if it exists (prevents child from holding lock)
		if [[ -n "${LOCK_FD}" ]] && [[ "${LOCK_FD}" =~ ^[0-9]+$ ]]; then
			eval "exec ${LOCK_FD}>&-" 2>/dev/null || true
		fi

		animate_gif_frames "${cache_dir}" "${frame_delay}"
	) &

	local animation_pid=$!
	update_state_atomic ".processes.animation_pid = ${animation_pid}"

	log_info "Started GIF animation (PID: ${animation_pid})"
	return 0
}

# ============================================================================
# CACHE MANAGEMENT
# ============================================================================

cleanup_cache() {
	local max_cache_mb
	max_cache_mb=$(get_config '.behavior.max_cache_size_mb' '500')
	local max_cache_bytes=$((max_cache_mb * 1024 * 1024))

	log_info "Cleaning cache (max size: ${max_cache_mb}MB)"

	# Get current cache size
	local current_size
	current_size=$(du -sb "${CACHE_DIR}" | cut -f1)

	if [[ ${current_size} -le ${max_cache_bytes} ]]; then
		log_debug "Cache size (${current_size} bytes) within limit"
		return 0
	fi

	# Check if gifs cache directory exists
	if [[ ! -d "${CACHE_DIR}/gifs" ]]; then
		log_debug "GIF cache directory doesn't exist yet, nothing to clean"
		return 0
	fi

	# Remove oldest GIF frames first (using portable find approach)
	local freed_space=0
	while IFS= read -r dir; do
		[[ -z "${dir}" ]] && continue
		local dir_size
		dir_size=$(du -sb "${dir}" | cut -f1)
		rm -rf "${dir}"
		freed_space=$((freed_space + dir_size))
		log_debug "Removed cache: ${dir} (freed ${dir_size} bytes)"

		current_size=$((current_size - dir_size))
		if [[ ${current_size} -le ${max_cache_bytes} ]]; then
			break
		fi
	done < <(
		# Use ls -t for portable timestamp-based sorting
		# Sort by modification time (oldest first)
		find "${CACHE_DIR}/gifs" -type d -mindepth 1 -maxdepth 1 2>/dev/null |
			while IFS= read -r d; do
				# Get modification time in seconds since epoch (portable approach)
				if [[ -d "${d}" ]]; then
					echo "$(stat -c %Y "${d}" 2>/dev/null || stat -f %m "${d}" 2>/dev/null) ${d}"
				fi
			done | sort -n | cut -d' ' -f2-
	)

	log_info "Cache cleanup completed (freed $((freed_space / 1024 / 1024))MB)"
}

# ============================================================================
# MAIN LOOP
# ============================================================================

stop_animation() {
	local animation_pid
	animation_pid=$(read_state '.processes.animation_pid // null')

	if [[ "${animation_pid}" != "null" && -n "${animation_pid}" && "${animation_pid}" =~ ^[0-9]+$ ]]; then
		if kill -0 "${animation_pid}" 2>/dev/null; then
			# Process is running, kill it
			log_info "Stopping animation process (PID: ${animation_pid})"
			kill -TERM "${animation_pid}" 2>/dev/null || true

			# Wait up to 2 seconds for graceful exit
			local waited=0
			while kill -0 "${animation_pid}" 2>/dev/null && [[ ${waited} -lt 20 ]]; do
				sleep 0.1
				waited=$((waited + 1))
			done

			# Force kill if still alive
			if kill -0 "${animation_pid}" 2>/dev/null; then
				log_warn "Force killing animation process (PID: ${animation_pid})"
				kill -KILL "${animation_pid}" 2>/dev/null || true
			fi

			log_info "Animation process cleaned up (PID: ${animation_pid})"
		else
			# Process is already dead, just log and clean up
			log_debug "Animation process ${animation_pid} is not running (cleaning stale PID)"
		fi

		# Always clear the PID from state, whether the process was running or not
		update_state_atomic '.processes.animation_pid = null' || log_warn "Failed to clear animation PID from state"
	fi
}

change_wallpaper() {
	local use_animated
	use_animated=$(should_use_animated)

	# Stop any running animation
	stop_animation

	# Select new wallpaper
	local wallpaper
	wallpaper=$(select_random_wallpaper "${use_animated}")

	if [[ -z "${wallpaper}" ]]; then
		log_error "Failed to select wallpaper"
		return 1
	fi

	log_info "Changing wallpaper to: ${wallpaper}"

	# Check if it's an animated wallpaper
	if [[ "${wallpaper}" =~ \.(gif)$ ]]; then
		if ! handle_animated_wallpaper "${wallpaper}"; then
			log_error "Failed to handle animated wallpaper: ${wallpaper}"
			return 1
		fi
	else
		if ! set_wallpaper "${wallpaper}"; then
			log_error "Failed to set wallpaper: ${wallpaper}"
			return 1
		fi
	fi

	# Update state with properly escaped wallpaper path
	local escaped_wallpaper
	escaped_wallpaper=$(printf '%s' "${wallpaper}" | jq -Rs .)
	update_state_atomic ".current_wallpaper = ${escaped_wallpaper}" || log_warn "Failed to update current wallpaper in state"
	add_to_history "${wallpaper}" || log_warn "Failed to add wallpaper to history"

	return 0
}

main_loop() {
	log_info "Starting main loop..."

	# Clean up any stale animation PID from previous runs
	local stale_animation_pid
	stale_animation_pid=$(read_state '.processes.animation_pid // null')
	if [[ "${stale_animation_pid}" != "null" && -n "${stale_animation_pid}" ]]; then
		if ! kill -0 "${stale_animation_pid}" 2>/dev/null; then
			log_info "Cleaning stale animation PID from state: ${stale_animation_pid}"
			update_state_atomic '.processes.animation_pid = null' || log_warn "Failed to clear stale animation PID"
		fi
	fi

	# Update status (use atomic for consistency)
	update_state_atomic '.status = "running"' || {
		log_error "Failed to update status to running"
		return 1
	}

	# Get change interval from config
	local change_interval
	change_interval=$(get_config '.intervals.change_seconds' '300')

	# Initial wallpaper change (non-fatal if it fails)
	if ! change_wallpaper; then
		log_warn "Initial wallpaper change failed, will retry in loop"
	fi

	# Main loop
	local last_change
	last_change=$(date +%s)
	local last_cleanup
	last_cleanup=$(date +%s)

	while true; do
		# Check status
		local status
		status=$(read_state '.status')

		case "${status}" in
		"stopping" | "stopped")
			log_info "Stopping main loop..."
			stop_animation
			break
			;;
		"paused")
			sleep 1
			continue
			;;
		"running") ;;
		*)
			log_warn "Unknown status: ${status}"
			sleep 1
			continue
			;;
		esac

		# Check if it's time to change wallpaper
		local now
		now=$(date +%s)
		local elapsed=$((now - last_change))

		if [[ ${elapsed} -ge ${change_interval} ]]; then
			# Only update last_change if wallpaper change succeeds
			if change_wallpaper; then
				last_change=${now}
			else
				log_error "Wallpaper change failed, will retry at next interval"
			fi
		fi

		# Periodic cache cleanup (every hour)
		local cleanup_elapsed=$((now - last_cleanup))
		if [[ ${cleanup_elapsed} -ge 3600 ]]; then
			cleanup_cache
			last_cleanup=${now}
		fi

		# Sleep for a bit
		sleep 5
	done

	log_info "Main loop ended"
}

# ============================================================================
# IPC SOCKET HANDLING
# ============================================================================

create_socket() {
	if [[ -e "${SOCKET_FILE}" ]]; then
		rm -f "${SOCKET_FILE}"
	fi

	# Start socat and capture its PID reliably
	socat UNIX-LISTEN:"${SOCKET_FILE}",fork EXEC:"${SCRIPT_PATH} --socket-handler" &
	local socat_pid=$!
	echo "${socat_pid}" >"${RUNTIME_DIR}/socket.pid"
	log_info "IPC socket created at: ${SOCKET_FILE} (PID: ${socat_pid})"
}

handle_socket_command() {
	# Acquire command lock to prevent concurrent execution
	local cmd_lock="${RUNTIME_DIR}/command.lock"
	local cmd_lock_fd
	exec {cmd_lock_fd}>"${cmd_lock}"
	if ! flock -n "${cmd_lock_fd}"; then
		echo "ERROR: Another command is currently executing"
		exec {cmd_lock_fd}>&-
		return 1
	fi

	local cmd
	read -r cmd

	case "${cmd}" in
	"next")
		log_info "Received command: next"
		# Trigger async wallpaper change to avoid blocking socat connection
		(change_wallpaper &)
		echo "OK: Wallpaper change initiated"
		;;
	"pause")
		log_info "Received command: pause"
		if update_state_atomic '.status = "paused"'; then
			stop_animation
			# Verify state was actually updated
			local current_status
			current_status=$(read_state '.status')
			if [[ "${current_status}" == "paused" ]]; then
				echo "OK: Paused"
			else
				log_warn "State update succeeded but verification failed (status: ${current_status})"
				echo "OK: Paused (pending verification)"
			fi
		else
			echo "ERROR: Failed to pause"
		fi
		;;
	"resume")
		log_info "Received command: resume"
		if update_state_atomic '.status = "running"'; then
			# Verify state was actually updated
			local current_status
			current_status=$(read_state '.status')
			if [[ "${current_status}" == "running" ]]; then
				echo "OK: Resumed"
			else
				log_warn "State update succeeded but verification failed (status: ${current_status})"
				echo "OK: Resumed (pending verification)"
			fi
		else
			echo "ERROR: Failed to resume"
		fi
		;;
	"status")
		local status
		if status=$(read_state '.'); then
			echo "${status}"
		else
			echo "ERROR: Failed to read status"
		fi
		;;
	"reload")
		log_info "Received command: reload"
		# Send HUP signal to daemon to reload config in main process
		local daemon_pid
		daemon_pid=$(read_state '.processes.main_pid // null')
		if [[ "${daemon_pid}" != "null" && -n "${daemon_pid}" && "${daemon_pid}" =~ ^[0-9]+$ ]] && kill -0 "${daemon_pid}" 2>/dev/null; then
			if kill -HUP "${daemon_pid}" 2>/dev/null; then
				echo "OK: Reload signal sent to daemon"
			else
				echo "ERROR: Failed to send reload signal"
			fi
		else
			echo "ERROR: Daemon not running"
		fi
		;;
	"stop")
		log_info "Received command: stop"
		if update_state_atomic '.status = "stopping"'; then
			echo "OK: Stopping"
		else
			echo "ERROR: Failed to initiate stop"
		fi
		;;
	*)
		echo "ERROR: Unknown command: ${cmd}"
		;;
	esac

	# Release command lock
	flock -u "${cmd_lock_fd}" 2>/dev/null || true
	exec {cmd_lock_fd}>&- 2>/dev/null || true
}

send_socket_command() {
	local cmd="$1"

	if [[ ! -e "${SOCKET_FILE}" ]]; then
		log_error "Socket not found: ${SOCKET_FILE}"
		return 1
	fi

	# socat is a hard dependency checked at startup
	echo "${cmd}" | socat - UNIX-CONNECT:"${SOCKET_FILE}"
}

# ============================================================================
# CLI INTERFACE
# ============================================================================

show_usage() {
	cat <<EOF
${SCRIPT_NAME} v${VERSION} - Professional Wallpaper Manager

Usage: $(basename "$0") [COMMAND] [OPTIONS]

Commands:
    start       Start wallpaper slideshow
    stop        Stop wallpaper slideshow
    restart     Restart wallpaper slideshow
    daemon      Start in daemon mode
    next        Change to next wallpaper
    pause       Pause slideshow
    resume      Resume slideshow
    status      Show current status
    info        Show detailed information
    list        List available wallpapers
    reload      Reload configuration
    clean       Clean cache
    help        Show this help message

Options:
    -d, --debug     Enable debug logging
    -c, --config    Specify config file
    -v, --version   Show version

Configuration:
    ${CONFIG_FILE}

State & Logs:
    ${STATE_FILE}
    ${LOG_FILE}

Examples:
    $(basename "$0") daemon     # Start as daemon
    $(basename "$0") next       # Change wallpaper
    $(basename "$0") status     # Check status

EOF
}

show_info() {
	echo "═══════════════════════════════════════════════════"
	echo " ${SCRIPT_NAME} v${VERSION}"
	echo "═══════════════════════════════════════════════════"
	echo
	echo "Status Information:"
	echo "──────────────────"

	local status current_wallpaper changes_count last_change
	status=$(read_state '.status // "unknown"')
	current_wallpaper=$(read_state '.current_wallpaper // "none"')
	changes_count=$(read_state '.stats.changes_count // 0')
	last_change=$(read_state '.stats.last_change // "never"')

	printf "%-20s: %s\n" "Status" "${status}"
	printf "%-20s: %s\n" "Current Wallpaper" "${current_wallpaper}"
	printf "%-20s: %s\n" "Changes Count" "${changes_count}"
	printf "%-20s: %s\n" "Last Change" "${last_change}"

	echo
	echo "System Information:"
	echo "──────────────────"

	local display_server battery_status
	display_server=$(detect_display_server)
	battery_status=$(get_battery_status)

	printf "%-20s: %s\n" "Display Server" "${display_server}"
	printf "%-20s: %s\n" "Battery Status" "${battery_status}"

	echo
	echo "Available Tools:"
	echo "───────────────"
	detect_available_tools | sed 's/^/  - /'

	echo
	echo "Cache Usage:"
	echo "───────────"
	if [[ -d "${CACHE_DIR}" ]]; then
		local cache_size
		cache_size=$(du -sh "${CACHE_DIR}" 2>/dev/null | cut -f1)
		printf "%-20s: %s\n" "Cache Size" "${cache_size}"
	fi
}

list_wallpapers() {
	echo "Static Wallpapers:"
	echo "─────────────────"
	get_wallpaper_list "false" | jq -r '.[]' | sed 's/^/  /'

	echo
	echo "Animated Wallpapers:"
	echo "───────────────────"
	get_wallpaper_list "true" | jq -r '.[]' | sed 's/^/  /'
}

# ============================================================================
# MAIN ENTRY POINT
# ============================================================================

main() {
	# Check for socket handler
	if [[ "${1:-}" == "--socket-handler" ]]; then
		handle_socket_command
		exit 0
	fi

	# Parse options and extract command (options can appear anywhere)
	local cmd=""
	while [[ $# -gt 0 ]]; do
		case "$1" in
		-h | --help)
			show_usage
			exit 0
			;;
		-v | --version)
			echo "${SCRIPT_NAME} v${VERSION}"
			exit 0
			;;
		-d | --debug)
			LOG_LEVEL=${LOG_DEBUG}
			log_debug "Debug mode enabled"
			shift
			;;
		-c | --config)
			if [[ -z "${2:-}" ]]; then
				echo "[ERROR] --config requires a path argument" >&2
				show_usage
				exit ${E_USAGE}
			fi
			CONFIG_FILE="$2"
			shift 2
			;;
		-*)
			log_error "Unknown option: $1"
			show_usage
			exit ${E_USAGE}
			;;
		*)
			# Not an option, must be the command (take first non-option)
			if [[ -z "${cmd}" ]]; then
				cmd="$1"
			fi
			shift
			;;
		esac
	done

	# Default to help if no command specified
	cmd="${cmd:-help}"

	# Check required dependencies
	if ! command -v jq &>/dev/null; then
		echo "[ERROR] jq is required but not installed" >&2
		echo "Install: sudo pacman -S jq" >&2
		exit ${E_DEPENDENCY}
	fi

	if ! command -v socat &>/dev/null; then
		echo "[ERROR] socat is required but not installed" >&2
		echo "Install: sudo pacman -S socat" >&2
		exit ${E_DEPENDENCY}
	fi

	# Check optional dependencies
	if ! command -v convert &>/dev/null && ! command -v magick &>/dev/null; then
		echo "[WARN] ImageMagick not found - GIF animations will not work" >&2
		echo "Install: sudo pacman -S imagemagick" >&2
	fi

	# Initialize
	init_directories
	init_config
	init_state

	# Handle commands
	case "${cmd}" in
	start)
		# Set up cleanup for persistent commands only
		trap 'cleanup' EXIT
		acquire_lock
		create_socket
		main_loop
		;;
	stop)
		send_socket_command "stop" || die "Daemon not running. Nothing to stop." ${E_GENERAL}
		echo "Stopping wallpaper manager..."
		;;
	restart)
		"${SCRIPT_PATH}" stop
		sleep 2
		"${SCRIPT_PATH}" start
		;;
	daemon)
		# Cleanup trap is set inside daemon child process
		# Socket created inside daemonize() after lock acquisition
		daemonize
		;;
	next)
		send_socket_command "next" || die "Daemon not running. Start with: $0 daemon" ${E_GENERAL}
		;;
	pause)
		send_socket_command "pause" || die "Daemon not running. Start with: $0 daemon" ${E_GENERAL}
		;;
	resume)
		send_socket_command "resume" || die "Daemon not running. Start with: $0 daemon" ${E_GENERAL}
		;;
	status)
		send_socket_command "status" || die "Daemon not running. Start with: $0 daemon" ${E_GENERAL}
		;;
	info)
		show_info
		;;
	list)
		list_wallpapers
		;;
	reload)
		send_socket_command "reload" || die "Daemon not running. Start with: $0 daemon" ${E_GENERAL}
		;;
	clean)
		cleanup_cache
		;;
	help)
		show_usage
		;;
	*)
		log_error "Unknown command: ${cmd}"
		show_usage
		exit ${E_USAGE}
		;;
	esac
}

# Run main if not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	main "$@"
fi
