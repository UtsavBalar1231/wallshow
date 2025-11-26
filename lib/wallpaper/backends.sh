#!/usr/bin/env bash
# backends.sh - Wallpaper backend support (swww, swaybg, feh, xwallpaper)
# Part of wallshow - Professional Wallpaper Manager for Wayland/X11

# ============================================================================
# TOOL DETECTION & WALLPAPER SETTING
# ============================================================================

# Cache for display server (never changes during session)
declare -g _DISPLAY_SERVER_CACHE=""

detect_display_server() {
	# Return cached value if available (display server never changes during session)
	if [[ -n "${_DISPLAY_SERVER_CACHE}" ]]; then
		echo "${_DISPLAY_SERVER_CACHE}"
		return
	fi

	if [[ -n "${WAYLAND_DISPLAY}" ]]; then
		_DISPLAY_SERVER_CACHE="wayland"
	elif [[ -n "${DISPLAY}" ]]; then
		_DISPLAY_SERVER_CACHE="x11"
	else
		_DISPLAY_SERVER_CACHE="unknown"
	fi
	echo "${_DISPLAY_SERVER_CACHE}"
}

detect_available_tools() {
	# Use cached tool detection from cache.sh
	get_available_tools_cached
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
		sleep 0.3 # Give daemon time to start

		# Verify daemon started
		if ! kill -0 "${swww_pid}" 2>/dev/null; then
			log_error "swww-daemon failed to start"
			return 1
		fi

		# Store PID for cleanup - failure means orphaned process
		if ! update_state_atomic ".processes.swww_daemon_pid = ${swww_pid}"; then
			log_error "Failed to store swww-daemon PID - killing to prevent orphan"
			kill -TERM "${swww_pid}" 2>/dev/null || true
			return 1
		fi
		log_debug "Started swww-daemon with PID: ${swww_pid}"
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
			# Validate PID is numeric before using with kill
			if [[ -n "${pid}" ]] && is_valid_pid "${pid}" && kill -0 "${pid}" 2>/dev/null; then
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
	if ! feh_errors=$(mktemp); then
		log_error "Failed to create temp file for feh errors"
		return 1
	fi
	chmod 600 "${feh_errors}" || log_warn "Failed to secure temp file: ${feh_errors}"

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
	if ! xw_errors=$(mktemp); then
		log_error "Failed to create temp file for xwallpaper errors"
		return 1
	fi
	chmod 600 "${xw_errors}" || log_warn "Failed to secure temp file: ${xw_errors}"

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

# ============================================================================
# WALLPAPER SETTING (with fallback chain)
# ============================================================================

# Internal state for tool tracking (reset per set_wallpaper call)
declare -ga _TRIED_TOOLS=()
declare -g _LAST_ERROR=""

# Try a wallpaper tool and track result
_try_tool() {
	local tool_name="$1"
	shift
	_TRIED_TOOLS+=("${tool_name}")
	log_debug "Trying wallpaper tool: ${tool_name}"

	if "$@"; then
		return 0
	fi

	_LAST_ERROR="${tool_name} failed"
	log_debug "Tool ${tool_name} failed"
	return 1
}

# Dispatch to correct backend based on tool name
_dispatch_tool() {
	local tool="$1"
	local image="$2"
	local transition_ms="$3"

	case "${tool}" in
	swww) _try_tool "swww" set_wallpaper_swww "${image}" "${transition_ms}" ;;
	swaybg) _try_tool "swaybg" set_wallpaper_swaybg "${image}" ;;
	feh) _try_tool "feh" set_wallpaper_feh "${image}" ;;
	xwallpaper) _try_tool "xwallpaper" set_wallpaper_xwallpaper "${image}" ;;
	*)
		log_debug "Skipping unsupported tool: ${tool}"
		return 1
		;;
	esac
}

set_wallpaper() {
	local image="$1"
	local transition_ms="${2:-}"

	# Reset tracking state
	_TRIED_TOOLS=()
	_LAST_ERROR=""

	# Validate image path
	image=$(validate_path "${image}" "") || {
		log_error "Invalid image path: ${image}"
		return 1
	}

	if [[ ! -r "${image}" ]]; then
		log_error "Cannot read image: ${image}"
		return 1
	fi

	local display_server
	display_server=$(detect_display_server)
	log_debug "Display server: ${display_server}"

	# Try preferred tool first
	local preferred_tool
	preferred_tool=$(get_config '.tools.preferred_static' 'auto')
	if [[ "${preferred_tool}" != "auto" ]] && command -v "${preferred_tool}" &>/dev/null; then
		if _dispatch_tool "${preferred_tool}" "${image}" "${transition_ms}"; then
			log_info "Set wallpaper with ${preferred_tool}: ${image}"
			return 0
		fi
	fi

	# Display server fallback chain
	local fallback_tools=()
	if [[ "${display_server}" == "wayland" ]]; then
		fallback_tools=("swww" "swaybg")
	else
		fallback_tools=("feh" "xwallpaper")
	fi

	for tool in "${fallback_tools[@]}"; do
		if _dispatch_tool "${tool}" "${image}" "${transition_ms}"; then
			log_info "Set wallpaper with ${tool}: ${image}"
			return 0
		fi
	done

	# Last resort: all available tools
	local available_tools
	available_tools=$(detect_available_tools)
	while IFS= read -r tool; do
		if _dispatch_tool "${tool}" "${image}" "${transition_ms}"; then
			log_info "Set wallpaper with ${tool}: ${image}"
			return 0
		fi
	done <<<"${available_tools}"

	# All tools failed
	log_error "Failed to set wallpaper with any available tool"
	log_error "Tools attempted: ${_TRIED_TOOLS[*]:-none}"
	log_error "Last error: ${_LAST_ERROR:-unknown}"

	local error_summary
	error_summary=$(printf '%s' "Tools tried: ${_TRIED_TOOLS[*]:-none}; Last: ${_LAST_ERROR:-unknown}" | jq -Rs .)
	update_state_atomic ".last_error = ${error_summary}" 2>/dev/null || true

	return 1
}
