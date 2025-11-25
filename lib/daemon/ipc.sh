#!/usr/bin/env bash
# ipc.sh - Unix socket IPC and command handlers
# Part of wallshow - Professional Wallpaper Manager for Wayland/X11

# ============================================================================
# COMMAND HANDLERS (extracted for testability)
# ============================================================================

_ipc_cmd_next() {
	log_info "Received command: next"
	(change_wallpaper &)
	echo "OK: Wallpaper change queued (async, check logs for result)"
}

_ipc_cmd_pause() {
	log_info "Received command: pause"
	local daemon_pid
	daemon_pid=$(read_state '.processes.main_pid // null')
	if [[ "${daemon_pid}" != "null" && -n "${daemon_pid}" ]] && is_valid_pid "${daemon_pid}" && kill -0 "${daemon_pid}" 2>/dev/null; then
		if kill -USR1 "${daemon_pid}" 2>/dev/null; then
			echo "OK: Pause signal sent"
		else
			echo "ERROR: Failed to send pause signal"
		fi
	else
		echo "ERROR: Daemon not running"
	fi
}

_ipc_cmd_resume() {
	log_info "Received command: resume"
	local daemon_pid
	daemon_pid=$(read_state '.processes.main_pid // null')
	if [[ "${daemon_pid}" != "null" && -n "${daemon_pid}" ]] && is_valid_pid "${daemon_pid}" && kill -0 "${daemon_pid}" 2>/dev/null; then
		if kill -USR2 "${daemon_pid}" 2>/dev/null; then
			echo "OK: Resume signal sent"
		else
			echo "ERROR: Failed to send resume signal"
		fi
	else
		echo "ERROR: Daemon not running"
	fi
}

_ipc_cmd_status() {
	local status
	if status=$(read_state '.'); then
		echo "${status}"
	else
		echo "ERROR: Failed to read status"
	fi
}

_ipc_cmd_reload() {
	log_info "Received command: reload"
	local daemon_pid
	daemon_pid=$(read_state '.processes.main_pid // null')
	if [[ "${daemon_pid}" != "null" && -n "${daemon_pid}" ]] && is_valid_pid "${daemon_pid}" && kill -0 "${daemon_pid}" 2>/dev/null; then
		if kill -HUP "${daemon_pid}" 2>/dev/null; then
			echo "OK: Reload signal sent to daemon"
		else
			echo "ERROR: Failed to send reload signal"
		fi
	else
		echo "ERROR: Daemon not running"
	fi
}

_ipc_cmd_stop() {
	log_info "Received command: stop"
	local daemon_pid
	daemon_pid=$(read_state '.processes.main_pid // null')
	if [[ "${daemon_pid}" != "null" && -n "${daemon_pid}" ]] && is_valid_pid "${daemon_pid}" && kill -0 "${daemon_pid}" 2>/dev/null; then
		if kill -TERM "${daemon_pid}" 2>/dev/null; then
			echo "OK: Stopping"
		else
			echo "ERROR: Failed to send stop signal"
		fi
	else
		echo "ERROR: Daemon not running"
	fi
}

# ============================================================================
# IPC SOCKET HANDLING
# ============================================================================

create_socket() {
	# NOTE: Race condition between rm and socat is mitigated by acquire_lock()
	# being called in daemon startup before this function. The instance lock
	# prevents concurrent daemon instances from racing on socket creation.
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

	# Try non-blocking first
	if ! flock -n "${cmd_lock_fd}"; then
		# Check if lock is stale (held longer than timeout)
		local lock_age=0
		if [[ -f "${cmd_lock}" ]]; then
			local lock_mtime now
			lock_mtime=$(stat -c %Y "${cmd_lock}" 2>/dev/null || echo 0)
			printf -v now '%(%s)T' -1
			lock_age=$((now - lock_mtime))
		fi

		if [[ "${lock_age}" -gt "${LIMIT_COMMAND_LOCK_TIMEOUT}" ]]; then
			log_warn "Command lock held for ${lock_age}s (>${LIMIT_COMMAND_LOCK_TIMEOUT}s), forcing unlock"
			# Force acquire by recreating lock file
			rm -f "${cmd_lock}"
			exec {cmd_lock_fd}>"${cmd_lock}"
			if ! flock -n "${cmd_lock_fd}"; then
				echo "ERROR: Failed to acquire command lock after stale detection"
				exec {cmd_lock_fd}>&-
				return 1
			fi
		else
			echo "ERROR: Another command is currently executing (age: ${lock_age}s)"
			exec {cmd_lock_fd}>&-
			return 1
		fi
	fi

	# Update lock timestamp to track when command started
	touch "${cmd_lock}"

	local cmd
	if ! read -r -t 5 cmd; then
		echo "ERROR: Read timeout or connection closed"
		flock -u "${cmd_lock_fd}" 2>/dev/null || true
		exec {cmd_lock_fd}>&- 2>/dev/null || true
		return 1
	fi

	case "${cmd}" in
	"next") _ipc_cmd_next ;;
	"pause") _ipc_cmd_pause ;;
	"resume") _ipc_cmd_resume ;;
	"status") _ipc_cmd_status ;;
	"reload") _ipc_cmd_reload ;;
	"stop") _ipc_cmd_stop ;;
	*) echo "ERROR: Unknown command: ${cmd}" ;;
	esac

	# Release command lock
	flock -u "${cmd_lock_fd}" 2>/dev/null || true
	exec {cmd_lock_fd}>&- 2>/dev/null || true
}

send_socket_command() {
	local cmd="$1"

	if [[ ! -e "${SOCKET_FILE}" ]]; then
		log_error "Daemon not running (socket not found)"
		return 1
	fi

	# socat is a hard dependency checked at startup
	echo "${cmd}" | socat - UNIX-CONNECT:"${SOCKET_FILE}"
}
