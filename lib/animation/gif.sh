#!/usr/bin/env bash
# gif.sh - GIF frame extraction and ImageMagick interface
# Part of wallshow - Professional Wallpaper Manager for Wayland/X11

# ============================================================================
# GIF FRAME EXTRACTION
# ============================================================================

extract_gif_frames() {
	local gif_path="$1"
	local output_dir="$2"

	if ! command -v magick &>/dev/null && ! command -v convert &>/dev/null; then
		log_error "ImageMagick is required for GIF extraction"
		return 1
	fi

	log_info "Extracting frames from: ${gif_path}"

	# Use convert or magick based on availability
	local convert_cmd="convert"
	command -v magick &>/dev/null && convert_cmd="magick"

	# Extract frames and capture errors
	local extract_errors
	extract_errors=$(mktemp)
	chmod 600 "${extract_errors}" # Secure immediately

	if ${convert_cmd} "${gif_path}" -coalesce "${output_dir}/frame_%04d.png" 2>"${extract_errors}"; then
		rm -f "${extract_errors}"
		log_info "Extracted frames to: ${output_dir}"
	else
		# Log extraction errors
		log_error "Failed to extract GIF frames from ${gif_path}:"
		while IFS= read -r err_line; do
			log_error "  ${err_line}"
		done <"${extract_errors}"
		rm -f "${extract_errors}"
		return 1
	fi

	# Extract native frame delays (in centiseconds, GIF standard)
	log_info "Extracting native frame delays from: ${gif_path}"
	local identify_cmd="identify"
	command -v magick &>/dev/null && identify_cmd="magick identify"

	local delays_json
	local identify_output
	if identify_output=$(${identify_cmd} -format "%T\n" "${gif_path}" 2>/dev/null); then
		if delays_json=$(echo "${identify_output}" | jq -s '.'); then
			if [[ -n "${delays_json}" && "${delays_json}" != "null" && "${delays_json}" != "" ]]; then
				echo "${delays_json}" >"${output_dir}/delays.json"
				local frame_count
				frame_count=$(echo "${delays_json}" | jq 'length')
				log_info "Extracted ${frame_count} frame delays (centiseconds): ${delays_json}"
			else
				log_warn "Could not extract native frame delays, will use config default"
				echo '[]' >"${output_dir}/delays.json"
			fi
		else
			log_warn "Could not parse frame delays as JSON, will use config default"
			echo '[]' >"${output_dir}/delays.json"
		fi
	else
		log_warn "Could not extract native frame delays from ImageMagick, will use config default"
		echo '[]' >"${output_dir}/delays.json"
	fi

	return 0
}

handle_animated_wallpaper() {
	local gif_path="$1"

	# Generate cache key from file hash
	local gif_hash
	local hash_output
	if ! hash_output=$(sha256sum "${gif_path}"); then
		log_error "Failed to compute hash for: ${gif_path}"
		return 1
	fi
	if ! gif_hash=$(echo "${hash_output}" | cut -d' ' -f1); then
		log_error "Failed to extract hash from sha256sum output"
		return 1
	fi
	if [[ -z "${gif_hash}" ]]; then
		log_error "Hash is empty for: ${gif_path}"
		return 1
	fi
	local gifs_cache="${CACHE_DIR}/gifs/${gif_hash}"

	# Check if frames are already extracted
	if [[ -d "${gifs_cache}" ]] && [[ -f "${gifs_cache}/frame_0000.png" ]]; then
		log_info "Using cached frames for: ${gif_path}"
	else
		# Create cache directory
		mkdir -p "${gifs_cache}"

		# Extract frames
		if ! extract_gif_frames "${gif_path}" "${gifs_cache}"; then
			rm -rf "${gifs_cache}"
			return 1
		fi
	fi

	# Get frame delay from config (minimum 10ms to prevent CPU busy loop)
	local frame_delay
	frame_delay=$(get_config '.intervals.gif_frame_ms' '50')
	if [[ ${frame_delay} -lt 10 ]]; then
		log_warn "Frame delay (${frame_delay}ms) too low, using minimum 10ms"
		frame_delay=10
	fi

	# Start animation in background
	# Close inherited lock FD to prevent child from holding daemon lock
	(
		# Close inherited LOCK_FD if it exists (prevents child from holding lock)
		if [[ -n "${LOCK_FD}" ]] && [[ "${LOCK_FD}" =~ ^[0-9]+$ ]]; then
			eval "exec ${LOCK_FD}>&-" 2>/dev/null || true
		fi

		# Set trap to clean PID on ANY exit (crash, normal, error)
		trap 'update_state_atomic ".processes.animation_pid = null" 2>/dev/null || true' EXIT

		animate_gif_frames "${gifs_cache}" "${frame_delay}"
	) &

	local animation_pid=$!
	update_state_atomic ".processes.animation_pid = ${animation_pid}"

	log_info "Started GIF animation (PID: ${animation_pid})"
	return 0
}
