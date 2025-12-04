#!/usr/bin/env bash
# process.sh - Daemon process management and signal handling
# Part of wallshow - Professional Wallpaper Manager for Wayland/X11

# ============================================================================
# IN-MEMORY STATUS (Signal-based IPC)
# ============================================================================

# Daemon status - checked by main loop (no jq calls!)
declare -g DAEMON_STATUS="stopped"

# Signal request flags - set by signal handlers, processed by main loop
declare -g PAUSE_REQUESTED=false
declare -g RESUME_REQUESTED=false
declare -g STOP_REQUESTED=false

# Status file for animation subprocess (lightweight alternative to JSON)
declare -g DAEMON_STATUS_FILE=""

# Write status to lightweight file (for animation subprocess)
write_status_file() {
	if [[ -n "${DAEMON_STATUS_FILE}" ]]; then
		echo "${DAEMON_STATUS}" >"${DAEMON_STATUS_FILE}"
	fi
}

# ============================================================================
# PROCESS MANAGEMENT
# ============================================================================

daemonize() {
	log_info "Starting in daemon mode..."

	# Clean up stale runtime files from previous crashes
	# (EXIT trap doesn't fire on SIGKILL)
	if [[ -e "${SOCKET_FILE}" || -e "${PID_FILE}" || -e "${RUNTIME_DIR}/daemon.ready" ]]; then
		# Verify no daemon is actually running
		if ! check_instance; then
			log_info "Cleaning up stale runtime files from previous crash"
			rm -f "${SOCKET_FILE}" "${PID_FILE}" "${RUNTIME_DIR}/daemon.ready" \
				"${RUNTIME_DIR}/daemon_status" 2>/dev/null || true

			# Also clean stale PIDs from state.json
			local stale_main_pid stale_anim_pid
			stale_main_pid=$(read_state '.processes.main_pid // null' 2>/dev/null)
			stale_anim_pid=$(read_state '.processes.animation_pid // null' 2>/dev/null)

			if [[ "${stale_main_pid}" != "null" || "${stale_anim_pid}" != "null" ]]; then
				log_info "Cleaning stale PIDs from state.json"
				update_state_atomic '.status = "stopped" | .processes.main_pid = null | .processes.animation_pid = null' 2>/dev/null || true
			fi
		fi
	fi

	# Pre-flight check: verify no instance already running
	if check_instance; then
		die "Daemon already running" "${E_LOCKED}"
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

			# Signal parent that PID file is ready (prevents systemd race condition)
			touch "${RUNTIME_DIR}/daemon.ready"

			# Update state with daemon PID and starting status
			# CRITICAL: PID storage failure makes daemon uncontrollable - must be fatal
			if ! update_state_atomic '.processes.main_pid = '"${BASHPID}"' | .status = "starting"'; then
				log_error "FATAL: Failed to store daemon PID in state - daemon would be uncontrollable"
				cleanup
				exit "${E_GENERAL}"
			fi

			log_info "Daemon process started (PID: ${BASHPID})"

			# Initialize caches (MUST be in main shell context, not in subshell)
			init_caches

			# Initialize session context (resolves wallpaper tools once)
			init_session_context

			# Initialize status file for animation subprocess
			DAEMON_STATUS_FILE="${RUNTIME_DIR}/daemon_status"
			DAEMON_STATUS="running"
			write_status_file

			# Create IPC socket AFTER acquiring lock (security: only daemon can create socket)
			create_socket

			# Set up signal handlers (SIGUSR1/USR2 for pause/resume - minimal handlers!)
			trap 'handle_signal TERM' TERM
			trap 'handle_signal INT' INT
			trap 'handle_signal HUP' HUP
			trap 'handle_signal USR1' USR1
			trap 'handle_signal USR2' USR2
			trap '' PIPE # Ignore SIGPIPE (broken socket connections)
			trap 'cleanup' EXIT

			# Run main loop
			main_loop
		) &

		# Parent exits immediately - daemon now runs independently
		# NOTE: $! here is not the actual daemon PID due to setsid
		# The child process writes its own PID above
		log_info "Daemon started, parent exiting"

		# Wait for child to signal readiness (prevents systemd PID file race)
		local ready_file="${RUNTIME_DIR}/daemon.ready"
		timeout 5 bash -c "while [[ ! -f '${ready_file}' ]]; do sleep 0.05; done" 2>/dev/null || true

		echo "Daemon started. Check status with: $0 status"
		exit 0
	fi
}

handle_signal() {
	local signal="$1"
	log_info "Received signal: ${signal}"

	case "${signal}" in
	TERM | INT)
		# Just set flag - main loop handles cleanup
		STOP_REQUESTED=true
		;;
	HUP)
		log_info "Reloading configuration..."
		invalidate_all_caches
		invalidate_session_context
		reload_config
		;;
	USR1)
		# Pause request - just set flag, main loop does heavy work
		PAUSE_REQUESTED=true
		;;
	USR2)
		# Resume request - just set flag, main loop does heavy work
		RESUME_REQUESTED=true
		;;
	*)
		log_warn "Unhandled signal: ${signal}"
		;;
	esac
}
