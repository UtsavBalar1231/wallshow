#!/usr/bin/env bash
# process.sh - Daemon process management and signal handling
# Part of wallshow - Professional Wallpaper Manager for Wayland/X11

# ============================================================================
# PROCESS MANAGEMENT
# ============================================================================

daemonize() {
	log_info "Starting in daemon mode..."

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
