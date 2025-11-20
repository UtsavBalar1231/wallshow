#!/usr/bin/env bash
# playback.sh - Animation frame cycling loop
# Part of wallshow - Professional Wallpaper Manager for Wayland/X11

# ============================================================================
# ANIMATION PLAYBACK
# ============================================================================

animate_gif_frames() {
	local frame_dir="$1"
	local frame_delay="$2"

	local frames=()
	local find_output
	if find_output=$(find "${frame_dir}" -name "frame_*.png" 2>/dev/null); then
		while IFS= read -r frame; do
			frames+=("${frame}")
		done < <(echo "${find_output}" | sort -V 2>/dev/null)
	fi

	if [[ ${#frames[@]} -eq 0 ]]; then
		log_error "No frames found in: ${frame_dir}"
		return 1
	fi

	# Load native frame delays from delays.json (in centiseconds)
	local delays=()
	local delays_file="${frame_dir}/delays.json"
	if [[ -f "${delays_file}" ]]; then
		local delays_data
		if delays_data=$(jq -r '.[]' "${delays_file}" 2>/dev/null); then
			if [[ -n "${delays_data}" ]]; then
				while IFS= read -r delay_cs; do
					# Convert centiseconds to milliseconds (cs * 10 = ms)
					local delay_ms=$((delay_cs * 10))
					# Apply minimum delay of 10ms for delay=0 frames (prevents CPU busy loop)
					[[ ${delay_ms} -lt 10 ]] && delay_ms=10
					delays+=("${delay_ms}")
				done <<<"${delays_data}"
			fi
		fi
	fi

	# Determine if using native delays or config default
	local using_native_delays=false
	if [[ ${#delays[@]} -gt 0 ]]; then
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

		# Use transition_ms=0 for GIF frames (no transition between frames)
		if set_wallpaper "${current_frame}" 0; then
			log_debug "Displaying frame: ${frame_index}"
			consecutive_failures=0
		else
			consecutive_failures=$((consecutive_failures + 1))
			log_warn "Failed to set frame ${frame_index} (${consecutive_failures} consecutive failures)"
			if [[ ${consecutive_failures} -ge 10 ]]; then
				log_error "Animation failed 10 times consecutively, exiting"
				return 1
			fi
		fi

		# Check status every 10 frames instead of every frame (reduces overhead)
		status_check_counter=$((status_check_counter + 1))
		if [[ $((status_check_counter % 10)) -eq 0 ]]; then
			local status
			status=$(read_state '.status')
			if [[ "${status}" != "running" ]]; then
				log_info "Animation stopped (status: ${status})"
				break
			fi
		fi

		# Get delay for current frame (native or config default)
		local current_delay_ms
		if ${using_native_delays} && [[ ${frame_index} -lt ${#delays[@]} ]]; then
			current_delay_ms="${delays[${frame_index}]}"
		else
			current_delay_ms="${frame_delay}"
		fi

		# Move to next frame
		frame_index=$(((frame_index + 1) % ${#frames[@]}))

		# Sleep for frame delay (convert milliseconds to seconds)
		local sleep_seconds
		if sleep_seconds=$(awk "BEGIN {printf \"%.3f\", ${current_delay_ms}/1000}"); then
			sleep "${sleep_seconds}"
		else
			sleep 0.050 # Fallback to 50ms
		fi
	done
}

stop_animation() {
	local reason="${1:-manual}" # manual, status_change, wallpaper_change, cleanup
	local animation_pid
	animation_pid=$(read_state '.processes.animation_pid // null')

	if [[ "${animation_pid}" != "null" && -n "${animation_pid}" && "${animation_pid}" =~ ^[0-9]+$ ]]; then
		if kill -0 "${animation_pid}" 2>/dev/null; then
			# Process is running, kill it
			log_info "Stopping animation process (PID: ${animation_pid}, reason: ${reason})"
			kill -TERM "${animation_pid}" 2>/dev/null || true

			# Wait up to 2 seconds for graceful exit
			local waited=0
			while kill -0 "${animation_pid}" 2>/dev/null && [[ ${waited} -lt 20 ]]; do
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
