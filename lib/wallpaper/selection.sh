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
	while [[ ${attempts} -lt 10 ]]; do
		selected=$(echo "${wallpapers}" | jq -r '.[] | select(. != null)' | shuf -n1)

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

	log_error "Failed to find valid wallpaper after 10 attempts (cache may be stale)"
	return 1
}

# ============================================================================
# BATTERY DETECTION & OPTIMIZATION
# ============================================================================

get_battery_status() {
	local battery_status="unknown"

	# Try multiple battery paths
	local battery_paths=(
		"/sys/class/power_supply/BAT0/status"
		"/sys/class/power_supply/BAT1/status"
		"/sys/class/power_supply/BATT/status"
	)

	for path in "${battery_paths[@]}"; do
		if [[ -r "${path}" ]]; then
			battery_status=$(tr '[:upper:]' '[:lower:]' <"${path}")
			log_debug "Battery status from ${path}: ${battery_status}"
			break
		fi
	done

	echo "${battery_status}"
}

should_use_animated() {
	local battery_optimization
	battery_optimization=$(get_config '.behavior.battery_optimization' 'true')

	if [[ "${battery_optimization}" != "true" ]]; then
		echo "true"
		return
	fi

	local battery_status
	battery_status=$(get_battery_status)

	if [[ "${battery_status}" == "discharging" ]]; then
		echo "false"
	else
		echo "true"
	fi
}
