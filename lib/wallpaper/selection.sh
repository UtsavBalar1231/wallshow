#!/usr/bin/env bash
# selection.sh - Random wallpaper selection with battery awareness
# Part of wallshow - Professional Wallpaper Manager for Wayland/X11

# ============================================================================
# WALLPAPER SELECTION
# ============================================================================

select_random_wallpaper() {
	local use_animated="${1:-false}"
	local wallpapers
	wallpapers=$(get_wallpaper_list "${use_animated}")

	if [[ "${wallpapers}" == "[]" || -z "${wallpapers}" ]]; then
		log_error "No wallpapers found"
		return 1
	fi

	# Try selecting a valid wallpaper (retry if file was deleted)
	local selected
	local attempts=0
	while [[ ${attempts} -lt ${RETRY_WALLPAPER_SELECT} ]]; do
		if ! selected=$(echo "${wallpapers}" | jq -r '.[] | select(. != null)' | shuf -n1); then
			log_error "Failed to select wallpaper"
			return 1
		fi

		if [[ -z "${selected}" ]]; then
			log_error "Failed to select wallpaper"
			return 1
		fi

		# Validate file exists (cache may be stale)
		if [[ -f "${selected}" ]]; then
			echo "${selected}"
			return 0
		fi

		log_warn "Cached wallpaper no longer exists: ${selected}"
		attempts=$((attempts + 1))
	done

	log_error "Failed to find valid wallpaper after ${RETRY_WALLPAPER_SELECT} attempts (cache may be stale)"
	return 1
}

# ============================================================================
# BATTERY DETECTION & OPTIMIZATION
# ============================================================================

# Cache for battery status file path (discovered once, never changes during session)
declare -g _BATTERY_STATUS_PATH=""
declare -g _BATTERY_PATH_DISCOVERED=false

# Discover and cache battery status path (one-time operation)
_discover_battery_path() {
	if [[ "${_BATTERY_PATH_DISCOVERED}" == "true" ]]; then
		return
	fi
	_BATTERY_PATH_DISCOVERED=true

	# Dynamic battery discovery - scan all power supply devices
	local supply
	for supply in /sys/class/power_supply/*/; do
		[[ -d "${supply}" ]] || continue

		local type_file="${supply}type"
		if [[ -r "${type_file}" ]]; then
			local supply_type
			supply_type=$(cat "${type_file}" 2>/dev/null || echo "")
			if [[ "${supply_type}" == "Battery" ]]; then
				local status_file="${supply}status"
				if [[ -r "${status_file}" ]]; then
					_BATTERY_STATUS_PATH="${status_file}"
					log_debug "Discovered battery path: ${_BATTERY_STATUS_PATH}"
					return
				fi
			fi
		fi
	done

	# Fallback paths if type-based discovery fails
	local battery_paths=(
		"/sys/class/power_supply/BAT0/status"
		"/sys/class/power_supply/BAT1/status"
		"/sys/class/power_supply/BATT/status"
	)
	for path in "${battery_paths[@]}"; do
		if [[ -r "${path}" ]]; then
			_BATTERY_STATUS_PATH="${path}"
			log_debug "Discovered battery path (fallback): ${_BATTERY_STATUS_PATH}"
			return
		fi
	done

	log_debug "No battery found on this system"
}

get_battery_status() {
	# Ensure battery path is discovered (cached after first call)
	_discover_battery_path

	# If no battery path discovered, return unknown
	if [[ -z "${_BATTERY_STATUS_PATH}" ]]; then
		echo "unknown"
		return
	fi

	# Read status from cached path (fast - single file read)
	if [[ -r "${_BATTERY_STATUS_PATH}" ]]; then
		tr '[:upper:]' '[:lower:]' <"${_BATTERY_STATUS_PATH}"
	else
		echo "unknown"
	fi
}

should_use_animated() {
	local battery_optimization
	battery_optimization=$(get_config '.behavior.battery_optimization' 'true')

	if [[ "${battery_optimization}" != "true" ]]; then
		echo "true"
		return
	fi

	# Use cached battery status with 30s TTL
	local battery_status
	battery_status=$(get_battery_status_cached)

	if [[ "${battery_status}" == "discharging" ]]; then
		echo "false"
	else
		echo "true"
	fi
}
