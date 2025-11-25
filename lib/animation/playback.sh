#!/usr/bin/env bash
# playback.sh - Animation frame cycling loop
# Part of wallshow - Professional Wallpaper Manager for Wayland/X11

# ============================================================================
# ANIMATION HELPERS
# ============================================================================

# Load frames from directory into array (passed by nameref)
# Usage: _load_frames "/path/to/frames" frames_array
_load_frames() {
	local frame_dir="$1"
	local -n _frames_ref=$2

	_frames_ref=()
	local find_output
	if find_output=$(find "${frame_dir}" -name "frame_*.png" 2>/dev/null); then
		while IFS= read -r frame; do
			_frames_ref+=("${frame}")
		done < <(echo "${find_output}" | sort -V 2>/dev/null)
	fi

	[[ "${#_frames_ref[@]}" -gt 0 ]]
}

# Load delays from delays.json into array (passed by nameref)
# Usage: _load_delays "/path/to/delays.json" delays_array
_load_delays() {
	local delays_file="$1"
	local -n _delays_ref=$2

	_delays_ref=()
	[[ ! -f "${delays_file}" ]] && return 1

	local delays_data
	if delays_data=$(jq -r '.[]' "${delays_file}" 2>/dev/null); then
		if [[ -n "${delays_data}" ]]; then
			while IFS= read -r delay_cs; do
				delay_cs=$(validate_numeric "${delay_cs}" "5" "0" "1000")
				local delay_ms=$((delay_cs * 10))
				[[ "${delay_ms}" -lt "${LIMIT_MIN_FRAME_DELAY_MS}" ]] && delay_ms="${LIMIT_MIN_FRAME_DELAY_MS}"
				_delays_ref+=("${delay_ms}")
			done <<<"${delays_data}"
		fi
	fi

	[[ "${#_delays_ref[@]}" -gt 0 ]]
}

# Check if animation should continue running
_should_continue_animation() {
	local status_file="${RUNTIME_DIR}/daemon_status"
	if [[ -r "${status_file}" ]]; then
		local status
		status=$(cat "${status_file}" 2>/dev/null || echo "running")
		[[ "${status}" == "running" ]]
	else
		return 0
	fi
}

# Convert milliseconds to sleep seconds string
_ms_to_sleep_seconds() {
	local ms="$1"
	local sec=$((ms / 1000))
	local frac=$((ms % 1000))
	printf "%d.%03d" "${sec}" "${frac}"
}

# ============================================================================
# ANIMATION PLAYBACK
# ============================================================================

animate_gif_frames() {
	local frame_dir="$1"
	local frame_delay="$2"

	# Load frames
	local frames=()
	if ! _load_frames "${frame_dir}" frames; then
		log_error "No frames found in: ${frame_dir}"
		return 1
	fi

	# Load delays (optional - falls back to config default)
	local delays=()
	local using_native_delays=false
	if _load_delays "${frame_dir}/delays.json" delays; then
		log_info "Animating ${#frames[@]} frames with native delays"
		using_native_delays=true
	else
		log_info "Animating ${#frames[@]} frames with ${frame_delay}ms delay (config default)"
	fi

	# Animation loop
	local frame_index=0
	local status_check_counter=0
	local consecutive_failures=0

	while true; do
		local current_frame="${frames[${frame_index}]}"

		if set_wallpaper "${current_frame}" 0; then
			log_debug "Displaying frame: ${frame_index}"
			consecutive_failures=0
		else
			consecutive_failures=$((consecutive_failures + 1))
			log_warn "Failed to set frame ${frame_index} (${consecutive_failures} consecutive failures)"
			if [[ "${consecutive_failures}" -ge "${RETRY_ANIMATION_FAILURES}" ]]; then
				log_error "Animation failed ${RETRY_ANIMATION_FAILURES} times consecutively, exiting"
				return 1
			fi
		fi

		# Periodic status check (every 10 frames)
		status_check_counter=$((status_check_counter + 1))
		if [[ $((status_check_counter % 10)) -eq 0 ]]; then
			if ! _should_continue_animation; then
				log_info "Animation stopped (daemon not running)"
				break
			fi
		fi

		# Get delay for current frame
		local current_delay_ms
		if [[ "${using_native_delays}" == "true" ]] && [[ "${frame_index}" -lt "${#delays[@]}" ]]; then
			current_delay_ms="${delays[${frame_index}]}"
		else
			current_delay_ms="${frame_delay}"
		fi

		# Advance frame index
		frame_index=$(((frame_index + 1) % ${#frames[@]}))

		# Sleep
		sleep "$(_ms_to_sleep_seconds "${current_delay_ms}")"
	done
}

stop_animation() {
	local reason="${1:-manual}" # manual, status_change, wallpaper_change, cleanup
	local animation_pid
	animation_pid=$(read_state '.processes.animation_pid // null')

	if [[ "${animation_pid}" != "null" && -n "${animation_pid}" ]] && is_valid_pid "${animation_pid}"; then
		if kill -0 "${animation_pid}" 2>/dev/null; then
			# Process is running, kill it
			log_info "Stopping animation process (PID: ${animation_pid}, reason: ${reason})"
			kill -TERM "${animation_pid}" 2>/dev/null || true

			# Wait up to 2 seconds for graceful exit
			local waited=0
			while kill -0 "${animation_pid}" 2>/dev/null && [[ "${waited}" -lt 20 ]]; do
				sleep 0.1
				waited=$((waited + 1))
			done

			# Force kill if still alive
			if kill -0 "${animation_pid}" 2>/dev/null; then
				log_warn "Force killing animation process (PID: ${animation_pid})"
				kill -KILL "${animation_pid}" 2>/dev/null || true
			fi

			log_info "Animation process cleaned up (PID: ${animation_pid})"
		else
			# Process is already dead, just log and clean up
			log_debug "Animation process ${animation_pid} is not running (cleaning stale PID)"
		fi

		# Always clear the PID from state, whether the process was running or not
		update_state_atomic '.processes.animation_pid = null' || log_warn "Failed to clear animation PID from state"
	fi
}
