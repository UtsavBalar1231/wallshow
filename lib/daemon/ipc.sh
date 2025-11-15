#!/usr/bin/env bash
# ipc.sh - Unix socket IPC and command handlers
# Part of wallshow - Professional Wallpaper Manager for Wayland/X11

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
			# Restart animation if current wallpaper is a GIF
			local current_wallpaper
			current_wallpaper=$(read_state '.current_wallpaper // null')

			if [[ "${current_wallpaper}" != "null" ]] && [[ "${current_wallpaper}" =~ \.(gif)$ ]]; then
				# Restart the GIF animation subprocess
				(handle_animated_wallpaper "${current_wallpaper}" &)
				log_info "Restarted GIF animation for: ${current_wallpaper}"
			fi

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
