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
