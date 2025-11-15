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
