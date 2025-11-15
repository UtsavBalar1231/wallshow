#!/usr/bin/env bash
# discovery.sh - Wallpaper discovery and caching
# Part of wallshow - Professional Wallpaper Manager for Wayland/X11

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

	# Check cache
	local cached_list
	local last_scan
	cached_list=$(jq -r ".cache.${cache_key}.files // []" "${STATE_FILE}" 2>/dev/null || echo "[]")
	last_scan=$(jq -r ".cache.${cache_key}.last_scan // 0" "${STATE_FILE}" 2>/dev/null || echo "0")

	local now
	now=$(date +%s)
	local cache_age=$((now - last_scan))
	local max_age=3600 # 1 hour

	if [[ "${force_refresh}" == "false" && ${cache_age} -lt ${max_age} && "${cached_list}" != "[]" ]]; then
		log_debug "Using cached wallpaper list for ${cache_key}"
		echo "${cached_list}"
		return 0
	fi

	log_info "Scanning directory: ${dir}"

	# Build exclude pattern arguments as an array
	local -a exclude_args=()
	local exclude_patterns
	# Get exclude patterns as a JSON array then extract values
	exclude_patterns=$(jq -r '.behavior.exclude_patterns[]?' "${CONFIG_FILE}" 2>/dev/null || echo "")

	if [[ -n "${exclude_patterns}" ]]; then
		while IFS= read -r pattern; do
			if [[ -n "${pattern}" ]]; then
				# Validate pattern contains only safe shell glob characters to prevent command injection
				if [[ "${pattern}" =~ ^[a-zA-Z0-9.*_-]+$ ]]; then
					exclude_args+=("!" "-name" "${pattern}")
				else
					log_warn "Skipping invalid exclude pattern (security): ${pattern}"
				fi
			fi
		done <<<"${exclude_patterns}"
	fi

	# Execute find and build file array, then convert to JSON once (O(n) instead of O(n²))
	local -a file_array=()
	local count=0

	# Find wallpaper files - log permission errors instead of suppressing
	local find_errors
	find_errors=$(mktemp)
	while IFS= read -r file; do
		[[ -z "${file}" ]] && continue
		file_array+=("${file}")
		count=$((count + 1))
	done < <(find "${dir}" -type f \( \
		-iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \
		-o -iname "*.webp" -o -iname "*.gif" -o -iname "*.bmp" \
		\) "${exclude_args[@]}" 2>"${find_errors}")

	# Log any permission or access errors from find
	if [[ -s "${find_errors}" ]]; then
		while IFS= read -r err_line; do
			log_warn "find: ${err_line}"
		done <"${find_errors}"
	fi
	rm -f "${find_errors}"

	log_info "Found ${count} wallpapers in ${dir}"

	# Convert file array to JSON in one operation
	local files_json
	if [[ ${count} -eq 0 ]]; then
		files_json="[]"
	else
		files_json=$(printf '%s\n' "${file_array[@]}" | jq -Rs 'split("\n") | map(select(length > 0))')
	fi

	# Update cache (use atomic for consistency)
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
		wallpaper_dir=$(get_config '.wallpaper_dirs.animated' "$HOME/Pictures/wallpapers/animated")
		wallpaper_dir="${wallpaper_dir/#\~/$HOME}"
		discover_wallpapers "${wallpaper_dir}" "animated" "false"
	else
		wallpaper_dir=$(get_config '.wallpaper_dirs.static' "$HOME/Pictures/wallpapers")
		wallpaper_dir="${wallpaper_dir/#\~/$HOME}"
		discover_wallpapers "${wallpaper_dir}" "static" "false"
	fi
}
