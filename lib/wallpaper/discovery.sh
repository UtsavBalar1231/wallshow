#!/usr/bin/env bash
# discovery.sh - Wallpaper discovery and caching
# Part of wallshow - Professional Wallpaper Manager for Wayland/X11

# ============================================================================
# DISCOVERY HELPERS
# ============================================================================

# Check if cached wallpaper list is still valid
# Returns: 0 if cache hit (outputs cached list), 1 if cache miss
_check_wallpaper_cache() {
	local cache_key="$1"
	local force_refresh="$2"

	if [[ "${force_refresh}" == "true" ]]; then
		return 1
	fi

	local cached_list last_scan cache_result
	cache_result=$(jq -r "[(.cache.${cache_key}.files // []), (.cache.${cache_key}.last_scan // 0)] | @tsv" "${STATE_FILE}" 2>/dev/null) || cache_result=$'[]\t0'
	IFS=$'\t' read -r cached_list last_scan <<<"${cache_result}"

	local now
	printf -v now '%(%s)T' -1
	local cache_age=$((now - last_scan))

	if [[ "${cache_age}" -lt "${INTERVAL_CACHE_REFRESH}" && "${cached_list}" != "[]" ]]; then
		log_debug "Using cached wallpaper list for ${cache_key}"
		echo "${cached_list}"
		return 0
	fi

	return 1
}

# Build find exclude arguments from config patterns
# Returns: exclude args via nameref
_build_exclude_args() {
	local -n _exclude_ref=$1

	_exclude_ref=()
	local exclude_patterns
	exclude_patterns=$(jq -r '.behavior.exclude_patterns[]?' "${CONFIG_FILE}" 2>/dev/null || echo "")

	if [[ -n "${exclude_patterns}" ]]; then
		while IFS= read -r pattern; do
			if [[ -n "${pattern}" ]]; then
				# Validate pattern for security (safe shell glob only)
				if [[ "${pattern}" =~ ^[a-zA-Z0-9.*_-]+$ ]]; then
					_exclude_ref+=("!" "-name" "${pattern}")
				else
					log_warn "Skipping invalid exclude pattern (security): ${pattern}"
				fi
			fi
		done <<<"${exclude_patterns}"
	fi
}

# Scan directory for wallpaper files
# Returns: JSON array of file paths
_scan_wallpaper_directory() {
	local dir="$1"
	local -a exclude_args=()
	_build_exclude_args exclude_args

	local -a file_array=()
	local count=0

	local find_errors
	if ! find_errors=$(mktemp); then
		log_error "Failed to create temp file for find errors"
		echo "[]"
		return 1
	fi

	local find_output
	if find_output=$(find "${dir}" -type f \( \
		-iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \
		-o -iname "*.webp" -o -iname "*.gif" -o -iname "*.bmp" \
		\) "${exclude_args[@]}" 2>"${find_errors}"); then
		while IFS= read -r file; do
			[[ -z "${file}" ]] && continue
			file_array+=("${file}")
			count=$((count + 1))
		done <<<"${find_output}"
	fi

	# Log permission errors
	if [[ -s "${find_errors}" ]]; then
		while IFS= read -r err_line; do
			log_warn "find: ${err_line}"
		done <"${find_errors}"
	fi
	rm -f "${find_errors}"

	log_info "Found ${count} wallpapers in ${dir}"

	# Convert to JSON
	if [[ "${count}" -eq 0 ]]; then
		echo "[]"
	else
		printf '%s\n' "${file_array[@]}" | jq -Rs 'split("\n") | map(select(length > 0))'
	fi
}

# ============================================================================
# WALLPAPER DISCOVERY & CACHING
# ============================================================================

discover_wallpapers() {
	local dir="$1"
	local cache_key="$2"
	local force_refresh="${3:-false}"

	# Validate directory
	dir=$(validate_path "${dir}" "") || {
		log_error "Invalid directory: ${dir}"
		return 1
	}

	# Check cache first
	if _check_wallpaper_cache "${cache_key}" "${force_refresh}"; then
		return 0
	fi

	log_info "Scanning directory: ${dir}"

	# Scan directory
	local files_json
	files_json=$(_scan_wallpaper_directory "${dir}")

	# Get current timestamp and count
	local now count
	printf -v now '%(%s)T' -1
	count=$(echo "${files_json}" | jq 'length')

	# Update cache
	update_state_atomic ".cache.${cache_key} = {
        \"files\": ${files_json},
        \"last_scan\": ${now},
        \"count\": ${count}
    }"

	echo "${files_json}"
}

get_wallpaper_list() {
	local use_animated="${1:-false}"
	local wallpaper_dir

	if [[ "${use_animated}" == "true" ]]; then
		wallpaper_dir=$(get_config '.wallpaper_dirs.animated' "${HOME}/Pictures/wallpapers/animated")
		wallpaper_dir="${wallpaper_dir/#\~/${HOME}}"
		discover_wallpapers "${wallpaper_dir}" "animated" "false"
	else
		wallpaper_dir=$(get_config '.wallpaper_dirs.static' "${HOME}/Pictures/wallpapers")
		wallpaper_dir="${wallpaper_dir/#\~/${HOME}}"
		discover_wallpapers "${wallpaper_dir}" "static" "false"
	fi
}
