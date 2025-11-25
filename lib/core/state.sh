#!/usr/bin/env bash
# state.sh - JSON state management with atomic updates
# Part of wallshow - Professional Wallpaper Manager for Wayland/X11

# ============================================================================
# COMMON HELPERS
# ============================================================================

# Validate that a string is a valid PID (non-empty positive integer)
# Usage: is_valid_pid "value"
# Returns: 0 if valid, 1 if invalid
is_valid_pid() {
	[[ -n "$1" && "$1" =~ ^[0-9]+$ ]]
}

# Create a secure temp file with error checking
# Usage: create_temp_file
# Returns: path to temp file on stdout, or returns 1 on failure
create_temp_file() {
	local tmpfile
	if ! tmpfile=$(mktemp); then
		log_error "Failed to create temp file"
		return 1
	fi
	chmod 600 "${tmpfile}" || log_warn "Failed to secure temp file: ${tmpfile}"
	echo "${tmpfile}"
}

# ============================================================================
# INPUT VALIDATION HELPERS
# ============================================================================

# Validate and return numeric value with bounds checking
# Usage: validate_numeric "value" "default" [min] [max]
# Returns: validated numeric value or default
validate_numeric() {
	local value="$1"
	local default="${2:-0}"
	local min="${3:-}"
	local max="${4:-}"

	# Handle null, empty, or whitespace-only
	value="${value//[[:space:]]/}"
	if [[ -z "${value}" || "${value}" == "null" ]]; then
		echo "${default}"
		return 0
	fi

	# Check if numeric (integer, optionally negative)
	if [[ ! "${value}" =~ ^-?[0-9]+$ ]]; then
		log_debug "Non-numeric value '${value}', using default: ${default}"
		echo "${default}"
		return 0
	fi

	# Enforce minimum if specified
	if [[ -n "${min}" ]] && [[ ${value} -lt ${min} ]]; then
		log_debug "Value ${value} below minimum ${min}, using minimum"
		echo "${min}"
		return 0
	fi

	# Enforce maximum if specified
	if [[ -n "${max}" ]] && [[ ${value} -gt ${max} ]]; then
		log_debug "Value ${value} above maximum ${max}, using maximum"
		echo "${max}"
		return 0
	fi

	echo "${value}"
}

# ============================================================================
# STATE MANAGEMENT
# ============================================================================

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
	local retry=0
	local lock_file="${STATE_FILE}.lock"
	local lock_fd

	# Acquire exclusive lock (prevents concurrent state corruption)
	exec {lock_fd}>"${lock_file}"
	if ! flock -w "${LIMIT_STATE_LOCK_TIMEOUT}" "${lock_fd}" 2>/dev/null; then
		log_error "Failed to acquire state lock within ${LIMIT_STATE_LOCK_TIMEOUT}s"
		exec {lock_fd}>&- 2>/dev/null || true
		return 1
	fi

	while [[ ${retry} -lt ${RETRY_STATE_UPDATE} ]]; do
		local temp_file
		temp_file=$(mktemp "${STATE_FILE}.XXXXXX")

		if jq "${update}" "${STATE_FILE}" >"${temp_file}" 2>/dev/null; then
			mv -f "${temp_file}" "${STATE_FILE}"
			chmod 600 "${STATE_FILE}"
			log_debug "State updated: ${update}"
			# Release lock
			flock -u "${lock_fd}" 2>/dev/null || true
			exec {lock_fd}>&- 2>/dev/null || true
			return 0
		else
			rm -f "${temp_file}"
			log_debug "State update failed (attempt $((retry + 1))/${RETRY_STATE_UPDATE}): ${update}"
		fi

		retry=$((retry + 1))
		sleep 0.1
	done

	# Release lock on failure
	flock -u "${lock_fd}" 2>/dev/null || true
	exec {lock_fd}>&- 2>/dev/null || true

	log_error "Failed to update state after ${RETRY_STATE_UPDATE} retries: ${update}"
	return 1
}

add_to_history() {
	local wallpaper="$1"

	# Escape wallpaper path for JSON (required - may contain special chars)
	local escaped_wallpaper
	escaped_wallpaper=$(printf '%s' "${wallpaper}" | jq -Rs .)

	# Use printf builtin for timestamp (no subprocess, ISO 8601 format is JSON-safe)
	local timestamp
	printf -v timestamp '%(%FT%T%z)T' -1

	update_state_atomic "
        .history = ([${escaped_wallpaper}] + .history | unique | .[0:${LIMIT_HISTORY_ENTRIES}]) |
        .stats.last_change = \"${timestamp}\" |
        .stats.changes_count += 1
    "
}

# Combined wallpaper state update (batches current + history in single jq call)
update_wallpaper_state() {
	local wallpaper="$1"

	# Escape wallpaper path for JSON (required - may contain special chars)
	local escaped_wallpaper
	escaped_wallpaper=$(printf '%s' "${wallpaper}" | jq -Rs .)

	# Use printf builtin for timestamp (no subprocess, ISO 8601 format is JSON-safe)
	local timestamp
	printf -v timestamp '%(%FT%T%z)T' -1

	# Single jq call for all wallpaper-related state updates
	update_state_atomic "
        .current_wallpaper = ${escaped_wallpaper} |
        .history = ([${escaped_wallpaper}] + .history | unique | .[0:${LIMIT_HISTORY_ENTRIES}]) |
        .stats.last_change = \"${timestamp}\" |
        .stats.changes_count += 1
    "
}
