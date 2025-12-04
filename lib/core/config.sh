#!/usr/bin/env bash
# shellcheck disable=SC2034
# config.sh - Configuration loading, validation, and reload
# Part of wallshow - Professional Wallpaper Manager for Wayland/X11

# ============================================================================
# CONFIGURATION MANAGEMENT
# ============================================================================

init_config() {
	# Guard: only initialize once to avoid excessive logging
	if [[ "${CONFIG_INITIALIZED}" == "true" ]]; then
		return 0
	fi

	if [[ ! -f "${CONFIG_FILE}" ]]; then
		log_info "Creating default configuration at ${CONFIG_FILE}"
		echo "${DEFAULT_CONFIG}" | jq '.' >"${CONFIG_FILE}" || die "Failed to create config file"
		chmod 600 "${CONFIG_FILE}"
	fi

	# Validate config
	if ! jq -e '.' "${CONFIG_FILE}" >/dev/null 2>&1; then
		die "Invalid JSON in config file: ${CONFIG_FILE}"
	fi

	CONFIG_INITIALIZED=true
}

get_config() {
	local query="$1"
	local default="${2:-}"

	if [[ ! -f "${CONFIG_FILE}" ]]; then
		init_config
	fi

	# Try cache first for common config keys (removes leading dot from query)
	local cache_key="${query#.}"
	local cached_value
	cached_value=$(get_config_cached "${cache_key}" "")

	if [[ -n "${cached_value}" && "${cached_value}" != "null" ]]; then
		echo "${cached_value}"
		return
	fi

	# Cache miss - fall back to jq (for uncached keys or first call before cache init)
	local config_value
	config_value=$(jq -r "${query}" "${CONFIG_FILE}" 2>/dev/null || echo "null")

	if [[ "${config_value}" == "null" || -z "${config_value}" ]]; then
		echo "${default}"
	else
		echo "${config_value}"
	fi
}

reload_config() {
	# Validate config file
	if ! jq -e '.' "${CONFIG_FILE}" >/dev/null 2>&1; then
		log_error "Invalid configuration file, keeping current config"
		return 1
	fi

	# Invalidate and rebuild config cache
	invalidate_config_cache
	cache_config

	# Update log level if changed
	local debug_flag
	debug_flag=$(get_config '.behavior.debug' 'false')
	if [[ "${debug_flag}" == "true" ]]; then
		LOG_LEVEL=${LOG_DEBUG}
	else
		LOG_LEVEL=${LOG_INFO}
	fi

	log_info "Configuration reloaded"
	return 0
}
