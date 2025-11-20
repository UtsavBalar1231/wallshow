#!/usr/bin/env bash
# backends.sh - Wallpaper backend support (swww, swaybg, feh, xwallpaper)
# Part of wallshow - Professional Wallpaper Manager for Wayland/X11

# ============================================================================
# TOOL DETECTION & WALLPAPER SETTING
# ============================================================================

detect_display_server() {
	if [[ -n "${WAYLAND_DISPLAY}" ]]; then
		echo "wayland"
	elif [[ -n "${DISPLAY}" ]]; then
		echo "x11"
	else
		echo "unknown"
	fi
}

detect_available_tools() {
	local tools=()
	local tool_commands=("swww" "swaybg" "hyprpaper" "mpvpaper" "feh" "xwallpaper" "nitrogen")

	for tool in "${tool_commands[@]}"; do
		if command -v "${tool}" &>/dev/null; then
			tools+=("${tool}")
			log_debug "Found wallpaper tool: ${tool}"
		fi
	done

	printf '%s\n' "${tools[@]}"
}

set_wallpaper_swww() {
	local image="$1"
	local transition_ms="${2:-}"

	# Use passed transition or read from config
	if [[ -z "${transition_ms}" ]]; then
		transition_ms=$(get_config '.intervals.transition_ms' '300')
	fi

	# Ensure daemon is running
	if ! pgrep -x "swww-daemon" &>/dev/null; then
		log_debug "Starting swww-daemon"
		swww-daemon --format argb &
		local swww_pid=$!
		update_state_atomic ".processes.swww_daemon_pid = ${swww_pid}" || log_warn "Failed to store swww-daemon PID"
		log_debug "Started swww-daemon with PID: ${swww_pid}"
		sleep 0.5 # Give daemon time to start
	fi

	# Set wallpaper with transition
	if swww img "${image}" \
		--transition-type random \
		--transition-duration "$((transition_ms / 1000)).${transition_ms:(-3)}" \
		2>/dev/null; then
		log_debug "Set wallpaper with swww (transition: ${transition_ms}ms): ${image}"
		return 0
	fi

	return 1
}

set_wallpaper_swaybg() {
	local image="$1"

	# Kill existing swaybg instances spawned by us
	local our_pids
	local pids_json
	if pids_json=$(read_state '.processes.swaybg_pids // []'); then
		our_pids=$(echo "${pids_json}" | jq -r '.[]') || our_pids=""
	else
		our_pids=""
	fi
	if [[ -n "${our_pids}" ]]; then
		while IFS= read -r pid; do
			if kill -0 "${pid}" 2>/dev/null; then
				kill -TERM "${pid}" 2>/dev/null || true
				# Wait briefly for graceful exit
				sleep 0.2
				# Force kill if still alive
				if kill -0 "${pid}" 2>/dev/null; then
					kill -KILL "${pid}" 2>/dev/null || true
				fi
			fi
		done <<<"${our_pids}"
	fi

	# Start new instance
	swaybg -i "${image}" -m fill &
	local new_pid=$!

	# Update state with new PID
	update_state_atomic ".processes.swaybg_pids = [${new_pid}]"

	log_debug "Set wallpaper with swaybg: ${image} (PID: ${new_pid})"
	return 0
}

set_wallpaper_feh() {
	local image="$1"
	local feh_errors
	feh_errors=$(mktemp)
	chmod 600 "${feh_errors}" # Secure immediately

	if feh --bg-fill "${image}" 2>"${feh_errors}"; then
		rm -f "${feh_errors}"
		log_debug "Set wallpaper with feh: ${image}"
		return 0
	fi

	log_error "feh failed to set wallpaper:"
	while IFS= read -r err_line; do
		log_error "  ${err_line}"
	done <"${feh_errors}"
	rm -f "${feh_errors}"
	return 1
}

set_wallpaper_xwallpaper() {
	local image="$1"
	local xw_errors
	xw_errors=$(mktemp)
	chmod 600 "${xw_errors}" # Secure immediately

	if xwallpaper --zoom "${image}" 2>"${xw_errors}"; then
		rm -f "${xw_errors}"
		log_debug "Set wallpaper with xwallpaper: ${image}"
		return 0
	fi

	log_error "xwallpaper failed to set wallpaper:"
	while IFS= read -r err_line; do
		log_error "  ${err_line}"
	done <"${xw_errors}"
	rm -f "${xw_errors}"
	return 1
}

set_wallpaper() {
	local image="$1"
	local transition_ms="${2:-}"

	# Validate image path
	image=$(validate_path "${image}" "") || {
		log_error "Invalid image path: ${image}"
		return 1
	}

	# Check if file exists and is readable
	if [[ ! -r "${image}" ]]; then
		log_error "Cannot read image: ${image}"
		return 1
	fi

	local display_server
	display_server=$(detect_display_server)
	log_debug "Display server: ${display_server}"

	# Get preferred tool from config
	local preferred_tool
	preferred_tool=$(get_config '.tools.preferred_static' 'auto')

	# Try preferred tool first if specified
	if [[ "${preferred_tool}" != "auto" ]] && command -v "${preferred_tool}" &>/dev/null; then
		case "${preferred_tool}" in
		swww) set_wallpaper_swww "${image}" "${transition_ms}" && return 0 ;;
		swaybg) set_wallpaper_swaybg "${image}" && return 0 ;;
		feh) set_wallpaper_feh "${image}" && return 0 ;;
		xwallpaper) set_wallpaper_xwallpaper "${image}" && return 0 ;;
		*) log_warn "Unsupported preferred tool: ${preferred_tool}" ;;
		esac
	fi

	# Fallback chain based on display server
	if [[ "${display_server}" == "wayland" ]]; then
		set_wallpaper_swww "${image}" "${transition_ms}" && return 0
		set_wallpaper_swaybg "${image}" && return 0
	else
		set_wallpaper_feh "${image}" && return 0
		set_wallpaper_xwallpaper "${image}" && return 0
	fi

	# Last resort: try all available tools
	local available_tools
	available_tools=$(detect_available_tools)

	while IFS= read -r tool; do
		case "${tool}" in
		swww) set_wallpaper_swww "${image}" "${transition_ms}" && return 0 ;;
		swaybg) set_wallpaper_swaybg "${image}" && return 0 ;;
		feh) set_wallpaper_feh "${image}" && return 0 ;;
		xwallpaper) set_wallpaper_xwallpaper "${image}" && return 0 ;;
		*) log_debug "Skipping unsupported tool: ${tool}" ;;
		esac
	done <<<"${available_tools}"

	log_error "Failed to set wallpaper with any available tool"
	return 1
}
