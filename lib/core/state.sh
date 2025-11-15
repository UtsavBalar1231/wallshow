#!/usr/bin/env bash
# state.sh - JSON state management with atomic updates
# Part of wallshow - Professional Wallpaper Manager for Wayland/X11

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
