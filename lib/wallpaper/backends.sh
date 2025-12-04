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

# ============================================================================
# HELPER FUNCTIONS FOR SMART TOOL SELECTION
# ============================================================================

is_gif() {
	local image="$1"

	case "${image,,}" in
	*.gif) return 0 ;;
	*) return 1 ;;
	esac
}

tool_supports_native_gif() {
	local tool="$1"

	case "${tool}" in
	swww | mpvpaper)
		return 0
		;;
	*)
		return 1
		;;
	esac
}

tool_display_server() {
	local tool="$1"

	case "${tool}" in
	swww | swaybg | hyprpaper | mpvpaper | wpaperd)
		echo "wayland"
		;;
	feh | xwallpaper)
		echo "x11"
		;;
	wallutils)
		echo "both"
		;;
	*)
		echo "unknown"
		;;
	esac
}

select_best_tool() {
	local image="$1"
	local available_tools="$2"
	local display_server="$3"

	local is_animated=false
	is_gif "${image}" && is_animated=true

	if ${is_animated}; then
		local gif_tools=("swww" "mpvpaper")
		for tool in "${gif_tools[@]}"; do
			if echo "${available_tools}" | grep -qx "${tool}"; then
				local tool_ds
				tool_ds=$(tool_display_server "${tool}")
				if [[ "${tool_ds}" == "${display_server}" ]] || [[ "${tool_ds}" == "both" ]]; then
					log_debug "Selected ${tool} for native GIF playback"
					echo "${tool}"
					return 0
				fi
			fi
		done

		log_warn "No native GIF tools available, will use frame extraction"
	fi

	local static_chain=()
	if [[ "${display_server}" == "wayland" ]]; then
		static_chain=("hyprpaper" "swww" "swaybg" "wallutils")
	else
		static_chain=("feh" "xwallpaper" "wallutils")
	fi

	for tool in "${static_chain[@]}"; do
		if echo "${available_tools}" | grep -qx "${tool}"; then
			local tool_ds
			tool_ds=$(tool_display_server "${tool}")
			if [[ "${tool_ds}" == "${display_server}" ]] || [[ "${tool_ds}" == "both" ]]; then
				echo "${tool}"
				return 0
			fi
		fi
	done

	return 1
}

# ============================================================================
# BACKEND IMPLEMENTATIONS
# ============================================================================

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
		# Close lock FD in subshell to prevent swww-daemon from holding instance lock
		(
			[[ -n "${LOCK_FD}" ]] && exec {LOCK_FD}>&- 2>/dev/null
			exec swww-daemon --format argb
		) &
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
	# Close lock FD in subshell to prevent swaybg from holding instance lock
	(
		[[ -n "${LOCK_FD}" ]] && exec {LOCK_FD}>&- 2>/dev/null
		exec swaybg -i "${image}" -m fill
	) &
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

set_wallpaper_hyprpaper() {
	local image="$1"

	if ! pgrep -x "hyprpaper" &>/dev/null; then
		log_debug "Starting hyprpaper daemon"
		# Close lock FD in subshell to prevent hyprpaper from holding instance lock
		(
			[[ -n "${LOCK_FD}" ]] && exec {LOCK_FD}>&- 2>/dev/null
			exec hyprpaper
		) &
		local shell_pid=$!
		sleep 0.3

		local hypr_pid
		hypr_pid=$(pgrep -n -x "hyprpaper")

		if [[ -z "${hypr_pid}" ]] || ! is_valid_pid "${hypr_pid}"; then
			log_error "hyprpaper daemon failed to start or PID invalid"
			kill -TERM "${shell_pid}" 2>/dev/null || true
			return 1
		fi

		if ! kill -0 "${hypr_pid}" 2>/dev/null; then
			log_error "hyprpaper daemon process not found"
			return 1
		fi

		update_state_atomic ".processes.hyprpaper_pid = ${hypr_pid}" || {
			log_error "Failed to store hyprpaper PID - killing to prevent orphan"
			kill -TERM "${hypr_pid}" 2>/dev/null || true
			return 1
		}
		log_debug "Started hyprpaper with PID: ${hypr_pid}"
	fi

	# Use reload command (combines preload + set + unload previous)
	# The "," prefix means "all outputs"
	if hyprctl hyprpaper reload ",${image}" 2>/dev/null; then
		log_debug "Set wallpaper with hyprpaper: ${image}"
		return 0
	fi

	log_error "hyprpaper failed to set wallpaper"
	return 1
}

set_wallpaper_mpvpaper() {
	local image="$1"

	local our_pids
	local pids_json
	if pids_json=$(read_state '.processes.mpvpaper_pids // []'); then
		our_pids=$(echo "${pids_json}" | jq -r '.[]') || our_pids=""
	else
		our_pids=""
	fi

	if [[ -n "${our_pids}" ]]; then
		while IFS= read -r pid; do
			if [[ -n "${pid}" ]] && is_valid_pid "${pid}" && kill -0 "${pid}" 2>/dev/null; then
				kill -TERM "${pid}" 2>/dev/null || true
				sleep 0.2
				if kill -0 "${pid}" 2>/dev/null; then
					kill -KILL "${pid}" 2>/dev/null || true
				fi
			fi
		done <<<"${our_pids}"
	fi

	# Close lock FD in subshell to prevent mpvpaper from holding instance lock
	(
		[[ -n "${LOCK_FD}" ]] && exec {LOCK_FD}>&- 2>/dev/null
		exec mpvpaper --fork --layer background \
			-o "no-audio --loop-file=inf" \
			'*' "${image}"
	) &
	local shell_pid=$!
	sleep 0.3

	local mpv_pid
	mpv_pid=$(pgrep -n -x "mpvpaper")

	if [[ -z "${mpv_pid}" ]] || ! is_valid_pid "${mpv_pid}"; then
		log_error "mpvpaper daemon failed to start or PID invalid"
		kill -TERM "${shell_pid}" 2>/dev/null || true
		return 1
	fi

	if ! kill -0 "${mpv_pid}" 2>/dev/null; then
		log_error "mpvpaper daemon process not found"
		return 1
	fi

	update_state_atomic ".processes.mpvpaper_pids = [${mpv_pid}]"

	log_debug "Set wallpaper with mpvpaper: ${image} (PID: ${mpv_pid})"
	return 0
}

set_wallpaper_wallutils() {
	local image="$1"

	if setwallpaper -m fill "${image}" 2>/dev/null; then
		log_debug "Set wallpaper with wallutils: ${image}"
		return 0
	fi

	log_error "wallutils failed to set wallpaper"
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
	hyprpaper) _try_tool "hyprpaper" set_wallpaper_hyprpaper "${image}" ;;
	mpvpaper) _try_tool "mpvpaper" set_wallpaper_mpvpaper "${image}" ;;
	wallutils) _try_tool "wallutils" set_wallpaper_wallutils "${image}" ;;
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

	# Validate image path
	image=$(validate_path "${image}" "") || {
		log_error "Invalid image path: ${image}"
		return 1
	}

	if [[ ! -r "${image}" ]]; then
		log_error "Cannot read image: ${image}"
		return 1
	fi

	# Get pre-resolved tool from session context (O(1) lookup)
	local tool
	tool=$(get_session_tool "${image}")

	if [[ -z "${tool}" ]]; then
		log_error "No suitable wallpaper tool available"
		return 1
	fi

	# Log GIF frame extraction warning once (not per frame)
	if is_gif "${image}" && ! tool_supports_native_gif "${tool}"; then
		log_warn "Using static-only tool '${tool}' with GIF - frame extraction will be used"
	fi

	# Dispatch to resolved tool
	if _dispatch_tool "${tool}" "${image}" "${transition_ms}"; then
		log_info "Set wallpaper with ${tool}: ${image}"
		return 0
	fi

	# Tool failed - try fallback (rare: tool became unavailable mid-session)
	log_warn "Session tool ${tool} failed, attempting fallback"
	invalidate_session_context

	local fallback_tool
	fallback_tool=$(get_session_tool "${image}")

	if [[ -n "${fallback_tool}" ]] && [[ "${fallback_tool}" != "${tool}" ]]; then
		if _dispatch_tool "${fallback_tool}" "${image}" "${transition_ms}"; then
			log_info "Set wallpaper with fallback ${fallback_tool}: ${image}"
			return 0
		fi
	fi

	log_error "Failed to set wallpaper with any available tool"
	return 1
}
