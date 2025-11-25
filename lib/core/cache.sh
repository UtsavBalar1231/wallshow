#!/usr/bin/env bash
# cache.sh - Centralized in-memory caching for performance optimization
# Part of wallshow - Professional Wallpaper Manager for Wayland/X11
#
# This module provides caching to reduce subprocess spawning (jq calls, file I/O).
# Cache invalidation strategies:
# - Config cache: Invalidated on SIGHUP (reload command)
# - Tool cache: Invalidated manually (rare - tools don't change during session)
# - Battery cache: TTL-based (30 seconds)

# ============================================================================
# CONFIGURATION CACHE
# ============================================================================

# Associative array for cached config values
declare -gA _CONFIG_CACHE=()
declare -g _CONFIG_CACHE_VALID=false

# Load entire config into cache (call in main shell context, not in subshell!)
cache_config() {
	if [[ "${_CONFIG_CACHE_VALID}" == "true" ]]; then
		return 0
	fi

	if [[ ! -f "${CONFIG_FILE}" ]]; then
		return 1
	fi

	# Extract commonly used config values in a single jq call
	# Output format: key=value lines for eval
	local cache_data
	if ! cache_data=$(jq -r '
		"wallpaper_dirs.static=" + (.wallpaper_dirs.static // "~/Pictures/wallpapers"),
		"wallpaper_dirs.animated=" + (.wallpaper_dirs.animated // "~/Pictures/wallpapers/animated"),
		"intervals.change_seconds=" + ((.intervals.change_seconds // 300) | tostring),
		"intervals.transition_ms=" + ((.intervals.transition_ms // 300) | tostring),
		"intervals.gif_frame_ms=" + ((.intervals.gif_frame_ms // 50) | tostring),
		"behavior.shuffle=" + ((.behavior.shuffle // true) | tostring),
		"behavior.battery_optimization=" + ((.behavior.battery_optimization // true) | tostring),
		"behavior.max_cache_size_mb=" + ((.behavior.max_cache_size_mb // 500) | tostring),
		"behavior.debug=" + ((.behavior.debug // false) | tostring),
		"tools.preferred_static=" + (.tools.preferred_static // "auto"),
		"tools.preferred_animated=" + (.tools.preferred_animated // "auto")
	' "${CONFIG_FILE}" 2>/dev/null); then
		return 1
	fi

	# Parse key=value lines into associative array
	while IFS='=' read -r key value; do
		[[ -z "${key}" ]] && continue
		_CONFIG_CACHE["${key}"]="${value}"
	done <<<"${cache_data}"

	_CONFIG_CACHE_VALID=true
	return 0
}

# Get config value from cache, falling back to jq if not cached
get_config_cached() {
	local key="${1#.}" # Remove leading dot if present
	local default="${2:-}"

	# Try cache first
	if [[ "${_CONFIG_CACHE_VALID}" == "true" ]]; then
		if [[ -v "_CONFIG_CACHE[\"${key}\"]" ]]; then
			local value="${_CONFIG_CACHE["${key}"]}"
			if [[ -n "${value}" && "${value}" != "null" ]]; then
				echo "${value}"
				return 0
			fi
		fi
	fi

	# Cache miss or not initialized - fall back to direct read
	# (This also handles keys not in the predefined set)
	echo "${default}"
}

# Invalidate config cache (call on SIGHUP/reload)
invalidate_config_cache() {
	_CONFIG_CACHE_VALID=false
	_CONFIG_CACHE=()
}

# ============================================================================
# TOOL DETECTION CACHE
# ============================================================================

declare -ga _AVAILABLE_TOOLS_CACHE=()
declare -g _TOOLS_CACHE_VALID=false

# Cache available wallpaper tools (call once at startup)
cache_available_tools() {
	if [[ "${_TOOLS_CACHE_VALID}" == "true" ]]; then
		return 0
	fi

	_AVAILABLE_TOOLS_CACHE=()
	for tool in "${WALLPAPER_TOOLS[@]}"; do
		if command -v "${tool}" &>/dev/null; then
			_AVAILABLE_TOOLS_CACHE+=("${tool}")
		fi
	done

	_TOOLS_CACHE_VALID=true
}

# Get available tools from cache
get_available_tools_cached() {
	cache_available_tools
	printf '%s\n' "${_AVAILABLE_TOOLS_CACHE[@]}"
}

# Check if a specific tool is available (fast lookup)
is_tool_available() {
	local tool="$1"
	cache_available_tools

	local cached_tool
	for cached_tool in "${_AVAILABLE_TOOLS_CACHE[@]}"; do
		if [[ "${cached_tool}" == "${tool}" ]]; then
			return 0
		fi
	done
	return 1
}

# Invalidate tool cache (rarely needed)
invalidate_tools_cache() {
	_TOOLS_CACHE_VALID=false
	_AVAILABLE_TOOLS_CACHE=()
}

# ============================================================================
# BATTERY STATUS CACHE (TTL-based)
# ============================================================================

declare -g _BATTERY_CACHE_VALUE=""
declare -g _BATTERY_CACHE_TIMESTAMP=0
declare -gri _BATTERY_CACHE_TTL=30 # 30 seconds

# Get battery status with TTL caching
get_battery_status_cached() {
	local now
	printf -v now '%(%s)T' -1

	# Return cached value if still valid
	if [[ -n "${_BATTERY_CACHE_VALUE}" ]] && [[ $((now - _BATTERY_CACHE_TIMESTAMP)) -lt ${_BATTERY_CACHE_TTL} ]]; then
		echo "${_BATTERY_CACHE_VALUE}"
		return
	fi

	# Cache expired or empty - get fresh value
	# Use the actual get_battery_status function from selection.sh
	_BATTERY_CACHE_VALUE=$(get_battery_status)
	_BATTERY_CACHE_TIMESTAMP=${now}

	echo "${_BATTERY_CACHE_VALUE}"
}

# Invalidate battery cache (force fresh read on next call)
invalidate_battery_cache() {
	_BATTERY_CACHE_VALUE=""
	_BATTERY_CACHE_TIMESTAMP=0
}

# ============================================================================
# INITIALIZATION
# ============================================================================

# Initialize all caches (call once at daemon startup, in main shell context)
init_caches() {
	cache_config
	cache_available_tools
	# Battery cache is lazy-loaded on first use
}

# Invalidate all caches (call on reload)
invalidate_all_caches() {
	invalidate_config_cache
	invalidate_tools_cache
	invalidate_battery_cache
}
