#!/usr/bin/env bash
# loop.sh - Main wallpaper change loop and cache management
# Part of wallshow - Professional Wallpaper Manager for Wayland/X11

# ============================================================================
# CACHE MANAGEMENT
# ============================================================================

cleanup_cache() {
	local max_cache_mb
	max_cache_mb=$(get_config '.behavior.max_cache_size_mb' '500')
	local max_cache_bytes=$((max_cache_mb * 1024 * 1024))

	log_info "Cleaning cache (max size: ${max_cache_mb}MB)"

	# Get current cache size (parameter expansion instead of echo|cut)
	local current_size
	if current_size=$(du -sb "${CACHE_DIR}" 2>/dev/null); then
		current_size="${current_size%%$'\t'*}"
		if [[ ! "${current_size}" =~ ^[0-9]+$ ]]; then
			current_size="0"
		fi
	else
		current_size="0"
	fi

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
		if dir_size=$(du -sb "${dir}" 2>/dev/null); then
			dir_size="${dir_size%%$'\t'*}"
			if [[ ! "${dir_size}" =~ ^[0-9]+$ ]]; then
				dir_size="0"
			fi
		else
			dir_size="0"
		fi
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
		if find_output=$(find "${CACHE_DIR}/gifs" -type d -mindepth 1 -maxdepth 1 2>/dev/null); then
			echo "${find_output}" | while IFS= read -r d; do
				# Get modification time in seconds since epoch (portable approach)
				if [[ -d "${d}" ]]; then
					local mtime
					if mtime=$(stat -c %Y "${d}" 2>/dev/null); then
						echo "${mtime} ${d}"
					elif mtime=$(stat -f %m "${d}" 2>/dev/null); then
						echo "${mtime} ${d}"
					else
						echo "0 ${d}"
					fi
				fi
			done | {
				if sort_output=$(sort -n 2>/dev/null); then
					echo "${sort_output}" | cut -d' ' -f2- 2>/dev/null
				fi
			}
		fi
	)

	log_info "Cache cleanup completed (freed $((freed_space / 1024 / 1024))MB)"
}

# Run cache cleanup in background (non-blocking)
cleanup_cache_background() {
	local cleanup_lock="${RUNTIME_DIR}/cache_cleanup.lock"

	# Skip if cleanup already running (non-blocking check)
	if [[ -f "${cleanup_lock}" ]]; then
		local lock_pid
		lock_pid=$(cat "${cleanup_lock}" 2>/dev/null || echo "")
		if [[ -n "${lock_pid}" ]] && kill -0 "${lock_pid}" 2>/dev/null; then
			log_debug "Cache cleanup already running (PID: ${lock_pid}), skipping"
			return 0
		fi
		# Stale lock, remove it
		rm -f "${cleanup_lock}"
	fi

	# Run cleanup in background subprocess
	(
		echo "$$" >"${cleanup_lock}"
		cleanup_cache
		rm -f "${cleanup_lock}"
	) &
	disown

	log_debug "Cache cleanup started in background"
}

# ============================================================================
# WALLPAPER CHANGE
# ============================================================================

change_wallpaper() {
	local use_animated
	use_animated=$(should_use_animated)

	# Stop any running animation
	stop_animation "wallpaper_change"

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

	# Update state: current wallpaper + history + stats in single jq call
	update_wallpaper_state "${wallpaper}" || log_warn "Failed to update wallpaper state"

	return 0
}

# ============================================================================
# MAIN LOOP HELPERS
# ============================================================================

# Process pending signal requests (SIGTERM, SIGUSR1, SIGUSR2)
# Returns: 0 to continue loop, 1 to break (stop requested)
_process_signal_requests() {
	# Handle stop request (SIGTERM/SIGINT)
	if [[ "${STOP_REQUESTED}" == "true" ]]; then
		STOP_REQUESTED=false
		log_info "Stopping main loop (signal received)..."
		DAEMON_STATUS="stopping"
		write_status_file
		update_state_atomic '.status = "stopping"' &
		stop_animation "status_change"
		return 1
	fi

	# Handle pause request (SIGUSR1)
	if [[ "${PAUSE_REQUESTED}" == "true" ]]; then
		PAUSE_REQUESTED=false
		if [[ "${DAEMON_STATUS}" != "paused" ]]; then
			log_info "Pausing daemon (signal received)"
			DAEMON_STATUS="paused"
			write_status_file
			stop_animation "pause"
			update_state_atomic '.status = "paused"' &
		fi
	fi

	# Handle resume request (SIGUSR2)
	if [[ "${RESUME_REQUESTED}" == "true" ]]; then
		RESUME_REQUESTED=false
		if [[ "${DAEMON_STATUS}" == "paused" ]]; then
			log_info "Resuming daemon (signal received)"
			DAEMON_STATUS="running"
			write_status_file
			update_state_atomic '.status = "running"' &

			# Restart animation if current wallpaper is a GIF
			local current_wallpaper
			current_wallpaper=$(read_state '.current_wallpaper // null')
			if [[ "${current_wallpaper}" != "null" && "${current_wallpaper}" =~ \.(gif)$ ]]; then
				(handle_animated_wallpaper "${current_wallpaper}" &)
				log_info "Restarted GIF animation for: ${current_wallpaper}"
			fi
		fi
	fi

	return 0
}

# Validate animation PID and handle errors
_validate_animation_pid() {
	local animation_pid
	animation_pid=$(read_state '.processes.animation_pid // null')
	if [[ "${animation_pid}" != "null" && -n "${animation_pid}" ]]; then
		if ! kill -0 "${animation_pid}" 2>/dev/null; then
			log_warn "Animation PID ${animation_pid} not running, cleaning stale PID"
			update_state_atomic '.processes.animation_pid = null'
		fi
	fi

	# Check for animation errors reported by subprocess
	local animation_error
	animation_error=$(read_state '.animation_error // null')
	if [[ "${animation_error}" != "null" ]]; then
		log_warn "Animation error detected: ${animation_error}"
		update_state_atomic '.animation_error = null'
		log_info "Attempting recovery by selecting new wallpaper"
		change_wallpaper || log_error "Recovery wallpaper change also failed"
	fi
}

# ============================================================================
# MAIN LOOP
# ============================================================================

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

	# Update state file for persistence (in-memory status already set in daemonize())
	update_state_atomic '.status = "running"' || log_warn "Failed to persist running status"

	# Get change interval from config
	local change_interval
	change_interval=$(get_config '.intervals.change_seconds' '300')

	# Initial wallpaper change (non-fatal if it fails)
	if ! change_wallpaper; then
		log_warn "Initial wallpaper change failed, will retry in loop"
	fi

	# Main loop - use printf builtin instead of date subprocess
	local last_change last_cleanup last_pid_check
	printf -v last_change '%(%s)T' -1
	printf -v last_cleanup '%(%s)T' -1
	printf -v last_pid_check '%(%s)T' -1

	while true; do
		# Process signal requests (returns 1 to break on stop)
		_process_signal_requests || break

		# Skip processing if paused (fast check - no I/O)
		if [[ "${DAEMON_STATUS}" == "paused" ]]; then
			sleep 60
			continue
		fi

		# Check if it's time to change wallpaper (printf builtin - no subprocess)
		local now
		printf -v now '%(%s)T' -1
		local elapsed=$((now - last_change))

		if [[ "${elapsed}" -ge "${change_interval}" ]]; then
			if change_wallpaper; then
				last_change=${now}
			else
				log_error "Wallpaper change failed, will retry at next interval"
			fi
		fi

		# Periodic validation of animation PID
		if [[ $((now - last_pid_check)) -ge ${INTERVAL_PID_CHECK} ]]; then
			_validate_animation_pid
			last_pid_check=${now}
		fi

		# Periodic cache cleanup (non-blocking)
		local cleanup_elapsed=$((now - last_cleanup))
		if [[ "${cleanup_elapsed}" -ge "${INTERVAL_CACHE_CLEANUP}" ]]; then
			cleanup_cache_background
			last_cleanup=${now}
		fi

		# Sleep 60s (signals wake us immediately)
		sleep 60
	done

	log_info "Main loop ended"
}
