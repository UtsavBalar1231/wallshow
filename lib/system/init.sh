#!/usr/bin/env bash
# init.sh - Initialization and cleanup handlers
# Part of wallshow - Professional Wallpaper Manager for Wayland/X11

# ============================================================================
# INITIALIZATION & CLEANUP
# ============================================================================

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

cleanup_all_processes() {
	log_debug "Cleaning up all child processes..."

	# Stop animation subprocess using stop_animation helper
	stop_animation "cleanup"

	# Stop swaybg processes
	local swaybg_pids
	local pids_json
	if pids_json=$(read_state '.processes.swaybg_pids // []'); then
		swaybg_pids=$(echo "${pids_json}" | jq -r '.[]') || swaybg_pids=""
	else
		swaybg_pids=""
	fi
	if [[ -n "${swaybg_pids}" ]]; then
		while IFS= read -r pid; do
			# Validate PID is numeric before using with kill
			if [[ -n "${pid}" && "${pid}" =~ ^[0-9]+$ ]] && kill -0 "${pid}" 2>/dev/null; then
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

	# Stop hyprpaper process
	local hyprpaper_pid
	hyprpaper_pid=$(read_state '.processes.hyprpaper_pid // null')
	if [[ "${hyprpaper_pid}" != "null" && -n "${hyprpaper_pid}" && "${hyprpaper_pid}" =~ ^[0-9]+$ ]] && kill -0 "${hyprpaper_pid}" 2>/dev/null; then
		log_debug "Cleaning up hyprpaper process (PID: ${hyprpaper_pid})"
		kill -TERM "${hyprpaper_pid}" 2>/dev/null || true
		sleep 0.2
		kill -KILL "${hyprpaper_pid}" 2>/dev/null || true
	fi

	# Stop mpvpaper processes
	local mpvpaper_pids
	local pids_json
	if pids_json=$(read_state '.processes.mpvpaper_pids // []'); then
		mpvpaper_pids=$(echo "${pids_json}" | jq -r '.[]') || mpvpaper_pids=""
	else
		mpvpaper_pids=""
	fi
	if [[ -n "${mpvpaper_pids}" ]]; then
		while IFS= read -r pid; do
			if [[ -n "${pid}" && "${pid}" =~ ^[0-9]+$ ]] && kill -0 "${pid}" 2>/dev/null; then
				log_debug "Cleaning up mpvpaper process (PID: ${pid})"
				kill -TERM "${pid}" 2>/dev/null || true
				sleep 0.1
				kill -KILL "${pid}" 2>/dev/null || true
			fi
		done <<<"${mpvpaper_pids}"
	fi

	# Stop socat socket process
	if [[ -f "${RUNTIME_DIR}/socket.pid" ]]; then
		local socat_pid
		socat_pid=$(<"${RUNTIME_DIR}/socket.pid")
		# Validate PID is numeric before using with kill
		if [[ -n "${socat_pid}" && "${socat_pid}" =~ ^[0-9]+$ ]] && kill -0 "${socat_pid}" 2>/dev/null; then
			log_debug "Cleaning up socat process (PID: ${socat_pid})"
			kill -TERM "${socat_pid}" 2>/dev/null || true
			sleep 0.1
			kill -KILL "${socat_pid}" 2>/dev/null || true
		fi
		rm -f "${RUNTIME_DIR}/socket.pid"
	fi

	log_debug "All child processes cleaned up"
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
	rm -f "${SOCKET_FILE}" "${PID_FILE}" "${RUNTIME_DIR}/daemon.ready" 2>/dev/null || true

	log_info "Cleanup completed"
}
