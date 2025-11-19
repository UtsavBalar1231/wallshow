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

	# Get current cache size
	local current_size
	if current_size=$(du -sb "${CACHE_DIR}" 2>/dev/null); then
		current_size=$(echo "${current_size}" | cut -f1)
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
			dir_size=$(echo "${dir_size}" | cut -f1)
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

# ============================================================================
# WALLPAPER CHANGE
# ============================================================================

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
		sleep 1
	done

	log_info "Main loop ended"
}
