#!/usr/bin/env bash
# interface.sh - CLI user interface (help, info, list)
# Part of wallshow - Professional Wallpaper Manager for Wayland/X11

# ============================================================================
# CLI INTERFACE
# ============================================================================

show_usage() {
	cat <<EOF
${SCRIPT_NAME} v${VERSION} - Professional Wallpaper Manager

Usage: $(basename "$0") [COMMAND] [OPTIONS]

Commands:
    start       Start wallpaper slideshow
    stop        Stop wallpaper slideshow
    restart     Restart wallpaper slideshow
    daemon      Start in daemon mode
    next        Change to next wallpaper
    pause       Pause slideshow
    resume      Resume slideshow
    status      Show current status
    info        Show detailed information
    diagnose    Run diagnostics and troubleshoot issues
    list        List available wallpapers
    reload      Reload configuration
    clean       Clean cache
    help        Show this help message

Options:
    -d, --debug     Enable debug logging
    -c, --config    Specify config file
    -v, --version   Show version

Configuration:
    ${CONFIG_FILE}

State & Logs:
    ${STATE_FILE}
    ${LOG_FILE}

Examples:
    $(basename "$0") daemon     # Start as daemon
    $(basename "$0") next       # Change wallpaper
    $(basename "$0") status     # Check status

EOF
}

# ============================================================================
# STALE STATE DETECTION & CLEANUP
# ============================================================================

# Clean up stale wallpaper backend PIDs
# Returns "true" if any stale backends were found
_cleanup_backend_pids() {
	local stale_backends=false
	local jq_cleanup=""

	# Check swaybg PIDs
	local swaybg_pids_json
	swaybg_pids_json=$(read_state '.processes.swaybg_pids // []')
	local swaybg_pids
	swaybg_pids=$(echo "${swaybg_pids_json}" | jq -r '.[]' 2>/dev/null) || swaybg_pids=""

	if [[ -n "${swaybg_pids}" ]]; then
		local live_pids=()
		local found_stale=false
		while IFS= read -r pid; do
			if [[ -n "${pid}" ]] && is_valid_pid "${pid}" && kill -0 "${pid}" 2>/dev/null; then
				live_pids+=("${pid}")
			else
				log_debug "Stale swaybg PID ${pid} detected"
				found_stale=true
				stale_backends=true
			fi
		done <<<"${swaybg_pids}"
		if ${found_stale}; then
			if [[ ${#live_pids[@]} -eq 0 ]]; then
				jq_cleanup="${jq_cleanup} | .processes.swaybg_pids = []"
			else
				local pids_str
				pids_str=$(
					IFS=,
					echo "${live_pids[*]}"
				)
				jq_cleanup="${jq_cleanup} | .processes.swaybg_pids = [${pids_str}]"
			fi
		fi
	fi

	# Check swww daemon PID
	local swww_pid
	swww_pid=$(read_state '.processes.swww_daemon_pid // null')
	if [[ "${swww_pid}" != "null" && -n "${swww_pid}" ]]; then
		if ! is_valid_pid "${swww_pid}" || ! kill -0 "${swww_pid}" 2>/dev/null; then
			log_debug "Stale swww-daemon PID ${swww_pid} detected"
			jq_cleanup="${jq_cleanup} | .processes.swww_daemon_pid = null"
			stale_backends=true
		fi
	fi

	# Check hyprpaper PID
	local hypr_pid
	hypr_pid=$(read_state '.processes.hyprpaper_pid // null')
	if [[ "${hypr_pid}" != "null" && -n "${hypr_pid}" ]]; then
		if ! is_valid_pid "${hypr_pid}" || ! kill -0 "${hypr_pid}" 2>/dev/null; then
			log_debug "Stale hyprpaper PID ${hypr_pid} detected"
			jq_cleanup="${jq_cleanup} | .processes.hyprpaper_pid = null"
			stale_backends=true
		fi
	fi

	# Check mpvpaper PIDs
	local mpv_pids_json
	mpv_pids_json=$(read_state '.processes.mpvpaper_pids // []')
	local mpv_pids
	mpv_pids=$(echo "${mpv_pids_json}" | jq -r '.[]' 2>/dev/null) || mpv_pids=""

	if [[ -n "${mpv_pids}" ]]; then
		local live_mpv_pids=()
		local found_mpv_stale=false
		while IFS= read -r pid; do
			if [[ -n "${pid}" ]] && is_valid_pid "${pid}" && kill -0 "${pid}" 2>/dev/null; then
				live_mpv_pids+=("${pid}")
			else
				log_debug "Stale mpvpaper PID ${pid} detected"
				found_mpv_stale=true
				stale_backends=true
			fi
		done <<<"${mpv_pids}"
		if ${found_mpv_stale}; then
			if [[ ${#live_mpv_pids[@]} -eq 0 ]]; then
				jq_cleanup="${jq_cleanup} | .processes.mpvpaper_pids = []"
			else
				local mpv_pids_str
				mpv_pids_str=$(
					IFS=,
					echo "${live_mpv_pids[*]}"
				)
				jq_cleanup="${jq_cleanup} | .processes.mpvpaper_pids = [${mpv_pids_str}]"
			fi
		fi
	fi

	# Apply cleanup if needed
	if [[ -n "${jq_cleanup}" ]]; then
		jq_cleanup="${jq_cleanup# | }" # Remove leading " | "
		update_state_atomic "${jq_cleanup}" 2>/dev/null || true
	fi

	echo "${stale_backends}"
}

# Detect and auto-cleanup stale daemon state
# Called before displaying status to ensure accuracy
# Also useful for daemon startup to clean previous crash remnants
_cleanup_stale_state() {
	local main_pid animation_pid
	local main_stale=false
	local animation_stale=false

	main_pid=$(read_state '.processes.main_pid // null')
	animation_pid=$(read_state '.processes.animation_pid // null')

	# Check main daemon PID
	if [[ "${main_pid}" != "null" && -n "${main_pid}" ]]; then
		if ! is_valid_pid "${main_pid}" || ! kill -0 "${main_pid}" 2>/dev/null; then
			log_warn "Stale main PID ${main_pid} detected, cleaning up"
			main_stale=true
		fi
	fi

	# Check animation PID (independently - animation can die while daemon lives)
	if [[ "${animation_pid}" != "null" && -n "${animation_pid}" ]]; then
		if ! is_valid_pid "${animation_pid}" || ! kill -0 "${animation_pid}" 2>/dev/null; then
			log_debug "Stale animation PID ${animation_pid} detected, cleaning up"
			animation_stale=true
		fi
	fi

	# Build atomic update based on what's stale
	if ${main_stale} || ${animation_stale}; then
		local jq_update=""

		if ${main_stale}; then
			# Main daemon dead - full cleanup
			jq_update='.status = "stopped" | .processes.main_pid = null'
			# Also cleanup runtime files
			rm -f "${PID_FILE}" "${SOCKET_FILE}" "${RUNTIME_DIR}/daemon.ready" \
				"${RUNTIME_DIR}/daemon_status" 2>/dev/null || true
		fi

		if ${animation_stale}; then
			if [[ -n "${jq_update}" ]]; then
				jq_update="${jq_update} | .processes.animation_pid = null"
			else
				jq_update='.processes.animation_pid = null'
			fi
		fi

		update_state_atomic "${jq_update}" 2>/dev/null || true
	fi

	# Also cleanup stale backend PIDs (swaybg, swww, hyprpaper, mpvpaper)
	_cleanup_backend_pids >/dev/null
}

show_info() {
	echo "═══════════════════════════════════════════════════"
	echo " ${SCRIPT_NAME} v${VERSION}"
	echo "═══════════════════════════════════════════════════"
	echo
	echo "Status Information:"
	echo "──────────────────"

	local status current_wallpaper changes_count last_change
	status=$(read_state '.status // "unknown"')
	current_wallpaper=$(read_state '.current_wallpaper // "none"')
	changes_count=$(read_state '.stats.changes_count // 0')
	last_change=$(read_state '.stats.last_change // "never"')

	printf "%-20s: %s\n" "Status" "${status}"
	printf "%-20s: %s\n" "Current Wallpaper" "${current_wallpaper}"
	printf "%-20s: %s\n" "Changes Count" "${changes_count}"
	printf "%-20s: %s\n" "Last Change" "${last_change}"

	echo
	echo "System Information:"
	echo "──────────────────"

	local display_server battery_status
	display_server=$(detect_display_server)
	battery_status=$(get_battery_status)

	printf "%-20s: %s\n" "Display Server" "${display_server}"
	printf "%-20s: %s\n" "Battery Status" "${battery_status}"

	echo
	echo "Available Tools:"
	echo "───────────────"
	local tools_output
	if tools_output=$(detect_available_tools); then
		# Add prefix to each line
		while IFS= read -r line; do
			echo "  - ${line}"
		done <<<"${tools_output}"
	else
		echo "  (none detected)"
	fi

	echo
	echo "Cache Usage:"
	echo "───────────"
	if [[ -d "${CACHE_DIR}" ]]; then
		local cache_size
		if cache_size=$(du -sh "${CACHE_DIR}" 2>/dev/null); then
			cache_size=$(echo "${cache_size}" | cut -f1)
		else
			cache_size="unknown"
		fi
		printf "%-20s: %s\n" "Cache Size" "${cache_size}"
	fi
}

show_status() {
	local status current_wallpaper changes_count last_change
	local animation_pid main_pid cache_static cache_animated

	# Auto-cleanup stale state before displaying
	_cleanup_stale_state

	# Read state (after potential cleanup)
	status=$(read_state '.status // "stopped"')
	current_wallpaper=$(read_state '.current_wallpaper // "none"')
	changes_count=$(read_state '.stats.changes_count // 0')
	last_change=$(read_state '.stats.last_change // "never"')
	main_pid=$(read_state '.processes.main_pid // null')
	animation_pid=$(read_state '.processes.animation_pid // null')
	cache_static=$(read_state '.cache.static.count // 0')
	cache_animated=$(read_state '.cache.animated.count // 0')

	# Status line with color
	local status_color=""
	case "${status}" in
	running) status_color="\033[32m" ;; # green
	paused) status_color="\033[33m" ;;  # yellow
	*) status_color="\033[31m" ;;       # red
	esac
	printf "Status:     ${status_color}%s\033[0m" "${status}"
	# Only show PID if validated (belt-and-suspenders after cleanup)
	if [[ "${main_pid}" != "null" && -n "${main_pid}" ]] && is_valid_pid "${main_pid}" && kill -0 "${main_pid}" 2>/dev/null; then
		printf " (PID %s)" "${main_pid}"
	fi
	echo

	# Uptime (calculate from PID start time)
	if [[ "${main_pid}" != "null" ]] && kill -0 "${main_pid}" 2>/dev/null; then
		local uptime_str
		uptime_str=$(ps -o etime= -p "${main_pid}" 2>/dev/null | tr -d ' ')
		[[ -n "${uptime_str}" ]] && printf "Uptime:     %s\n" "${uptime_str}"
	fi

	# Backend health check - warn if daemon running but backend dead
	if [[ "${status}" == "running" || "${status}" == "paused" ]]; then
		local backend_name=""
		local backend_running=false

		# Determine which backend should be active based on state
		local swaybg_pids swww_pid hypr_pid mpv_pids
		swaybg_pids=$(read_state '.processes.swaybg_pids // []' | jq -r '.[]' 2>/dev/null) || swaybg_pids=""
		swww_pid=$(read_state '.processes.swww_daemon_pid // null')
		hypr_pid=$(read_state '.processes.hyprpaper_pid // null')
		mpv_pids=$(read_state '.processes.mpvpaper_pids // []' | jq -r '.[]' 2>/dev/null) || mpv_pids=""

		if [[ -n "${swaybg_pids}" ]]; then
			backend_name="swaybg"
			while IFS= read -r pid; do
				[[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null && backend_running=true && break
			done <<<"${swaybg_pids}"
		elif [[ "${swww_pid}" != "null" && -n "${swww_pid}" ]]; then
			backend_name="swww"
			kill -0 "${swww_pid}" 2>/dev/null && backend_running=true
		elif [[ "${hypr_pid}" != "null" && -n "${hypr_pid}" ]]; then
			backend_name="hyprpaper"
			kill -0 "${hypr_pid}" 2>/dev/null && backend_running=true
		elif [[ -n "${mpv_pids}" ]]; then
			backend_name="mpvpaper"
			while IFS= read -r pid; do
				[[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null && backend_running=true && break
			done <<<"${mpv_pids}"
		fi

		if [[ -n "${backend_name}" ]] && ! ${backend_running}; then
			printf "Backend:    \033[31mDEAD\033[0m (was %s) - run 'wallshow restart'\n" "${backend_name}"
		elif [[ -n "${backend_name}" ]]; then
			printf "Backend:    %s\n" "${backend_name}"
		fi
	fi

	# Current wallpaper (basename only for readability)
	local wallpaper_name
	wallpaper_name=$(basename "${current_wallpaper}" 2>/dev/null || echo "none")
	printf "Wallpaper:  %s\n" "${wallpaper_name}"

	# Animation status - validate PID before display
	if [[ "${animation_pid}" != "null" && -n "${animation_pid}" ]] && is_valid_pid "${animation_pid}" && kill -0 "${animation_pid}" 2>/dev/null; then
		printf "Animation:  running (PID %s)\n" "${animation_pid}"
	fi

	# Stats
	printf "Changed:    %s times\n" "${changes_count}"
	printf "Last:       %s\n" "${last_change}"

	# Display server and tool
	local display_server tool_info
	display_server=$(detect_display_server)
	tool_info=$(get_config '.tools.preferred_static' 'auto')
	printf "Server:     %s (tool: %s)\n" "${display_server}" "${tool_info}"

	# Battery status
	local battery_opt battery_status
	battery_opt=$(get_config '.behavior.battery_optimization' 'true')
	if [[ "${battery_opt}" == "true" ]]; then
		battery_status=$(get_battery_status 2>/dev/null || echo "unknown")
		printf "Battery:    %s\n" "${battery_status}"
	fi

	# Interval
	local interval
	interval=$(get_config '.intervals.change_seconds' '300')
	printf "Interval:   %ss\n" "${interval}"

	# Cache summary
	printf "Cache:      %s static, %s animated\n" "${cache_static}" "${cache_animated}"
}

# ============================================================================
# DIAGNOSTICS CHECKS (extracted for testability)
# ============================================================================

# Returns: issues found (0 or 1)
_diag_daemon_status() {
	echo "1. Daemon Status"
	echo "   ─────────────"
	if check_instance; then
		local daemon_pid
		daemon_pid=$(read_state '.processes.main_pid // null')
		echo "   [OK] Daemon running (PID: ${daemon_pid})"
		return 0
	else
		echo "   [ERROR] Daemon not running"
		return 1
	fi
}

# Returns: issues found (0 or more)
_diag_wallpaper_dirs() {
	local issues=0
	echo "2. Wallpaper Directories"
	echo "   ──────────────────────"
	local static_dir animated_dir
	static_dir=$(get_config '.wallpaper_dirs.static' '')
	animated_dir=$(get_config '.wallpaper_dirs.animated' '')

	static_dir="${static_dir/#\~/${HOME}}"
	animated_dir="${animated_dir/#\~/${HOME}}"

	if [[ -d "${static_dir}" ]]; then
		local static_count
		static_count=$(find "${static_dir}" -type f \( -iname "*.jpg" -o -iname "*.png" -o -iname "*.jpeg" \) 2>/dev/null | wc -l)
		echo "   [OK] Static: ${static_dir} (${static_count} images)"
	else
		echo "   [ERROR] Static directory not found: ${static_dir}"
		issues=$((issues + 1))
	fi

	if [[ -d "${animated_dir}" ]]; then
		local gif_count
		gif_count=$(find "${animated_dir}" -type f -iname "*.gif" 2>/dev/null | wc -l)
		echo "   [OK] Animated: ${animated_dir} (${gif_count} GIFs)"
	else
		echo "   [WARN] Animated directory not found: ${animated_dir}"
	fi
	return "${issues}"
}

# Returns: issues found (0 or 1)
_diag_tools() {
	echo "3. Wallpaper Tools"
	echo "   ────────────────"
	local display_server
	display_server=$(detect_display_server)
	local required_tools
	if [[ "${display_server}" == "wayland" ]]; then
		required_tools=("swww" "swaybg")
	else
		required_tools=("feh" "xwallpaper")
	fi

	local tool_found=false
	for tool in "${required_tools[@]}"; do
		if command -v "${tool}" &>/dev/null; then
			echo "   [OK] ${tool} available"
			tool_found=true
		else
			echo "   [WARN] ${tool} not found"
		fi
	done

	if ! ${tool_found}; then
		echo "   [ERROR] No compatible wallpaper tool found for ${display_server}"
		return 1
	fi
	return 0
}

# Returns: issues found (0 or more)
_diag_recent_errors() {
	local issues=0
	echo "4. Recent Errors"
	echo "   ─────────────"
	local last_error
	last_error=$(read_state '.last_error // null')
	if [[ "${last_error}" != "null" ]]; then
		echo "   [ERROR] Last error: ${last_error}"
		issues=$((issues + 1))
	else
		echo "   [OK] No recent errors recorded"
	fi

	local animation_error
	animation_error=$(read_state '.animation_error // null')
	if [[ "${animation_error}" != "null" ]]; then
		echo "   [ERROR] Animation error: ${animation_error}"
		issues=$((issues + 1))
	fi
	return "${issues}"
}

# Returns: issues found (0 or 1)
_diag_process_health() {
	echo "5. Process Health"
	echo "   ───────────────"
	local animation_pid
	animation_pid=$(read_state '.processes.animation_pid // null')
	if [[ "${animation_pid}" != "null" && -n "${animation_pid}" ]]; then
		if [[ "${animation_pid}" =~ ^[0-9]+$ ]] && kill -0 "${animation_pid}" 2>/dev/null; then
			echo "   [OK] Animation process running (PID: ${animation_pid})"
		else
			echo "   [WARN] Animation PID ${animation_pid} recorded but process not running"
			return 1
		fi
	else
		echo "   [INFO] No animation currently running"
	fi
	return 0
}

# Returns: issues found (0 or 1)
_diag_last_change() {
	local issues=0
	echo "6. Last Wallpaper Change"
	echo "   ─────────────────────"
	local last_change current_wallpaper
	last_change=$(read_state '.stats.last_change // null')
	current_wallpaper=$(read_state '.current_wallpaper // null')

	if [[ "${last_change}" != "null" ]]; then
		echo "   Time: ${last_change}"
	else
		echo "   Time: Never"
	fi

	if [[ "${current_wallpaper}" != "null" ]]; then
		echo "   File: ${current_wallpaper}"
		if [[ -f "${current_wallpaper}" ]]; then
			echo "   Status: [OK] File exists"
		else
			echo "   Status: [ERROR] File no longer exists"
			issues=$((issues + 1))
		fi
	fi
	return "${issues}"
}

diagnose_issues() {
	echo "═══════════════════════════════════════════════════"
	echo " ${SCRIPT_NAME} Diagnostics Report"
	echo "═══════════════════════════════════════════════════"
	echo

	local issues_found=0
	local check_result

	_diag_daemon_status
	check_result=$?
	issues_found=$((issues_found + check_result))
	echo

	_diag_wallpaper_dirs
	check_result=$?
	issues_found=$((issues_found + check_result))
	echo

	_diag_tools
	check_result=$?
	issues_found=$((issues_found + check_result))
	echo

	_diag_recent_errors
	check_result=$?
	issues_found=$((issues_found + check_result))
	echo

	_diag_process_health
	check_result=$?
	issues_found=$((issues_found + check_result))
	echo

	_diag_last_change
	check_result=$?
	issues_found=$((issues_found + check_result))
	echo

	# Summary
	echo "═══════════════════════════════════════════════════"
	if [[ "${issues_found}" -eq 0 ]]; then
		echo " Result: No issues detected"
	else
		echo " Result: ${issues_found} issue(s) found"
	fi
	echo "═══════════════════════════════════════════════════"

	echo
	echo "For detailed logs, run: tail -100 ${LOG_FILE}"

	return "${issues_found}"
}

list_wallpapers() {
	echo "Static Wallpapers:"
	echo "─────────────────"
	local static_list
	if static_list=$(get_wallpaper_list "false"); then
		static_list=$(echo "${static_list}" | jq -r '.[]' 2>/dev/null | sed 's/^/  /')
		[[ -z "${static_list}" ]] && static_list="  (none found)"
	else
		static_list="  (error retrieving list)"
	fi
	echo "${static_list}"

	echo
	echo "Animated Wallpapers:"
	echo "───────────────────"
	local animated_list
	if animated_list=$(get_wallpaper_list "true"); then
		animated_list=$(echo "${animated_list}" | jq -r '.[]' 2>/dev/null | sed 's/^/  /')
		[[ -z "${animated_list}" ]] && animated_list="  (none found)"
	else
		animated_list="  (error retrieving list)"
	fi
	echo "${animated_list}"
}
