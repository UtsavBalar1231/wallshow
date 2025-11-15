#!/usr/bin/env bash
# paths.sh - Path validation and sanitization
# Part of wallshow - Professional Wallpaper Manager for Wayland/X11

# ============================================================================
# PATH VALIDATION & SECURITY
# ============================================================================

validate_path() {
	local path="$1"
	local base_dir="$2"

	# Expand tilde and resolve path
	path="${path/#\~/$HOME}"
	local resolved
	resolved=$(readlink -f "${path}" 2>/dev/null) || return 1

	# Ensure path exists
	[[ -e "${resolved}" ]] || return 1

	# If base_dir provided, ensure path is within it
	if [[ -n "${base_dir}" ]]; then
		base_dir="${base_dir/#\~/$HOME}"
		base_dir=$(readlink -f "${base_dir}" 2>/dev/null) || return 1

		# Check if resolved path starts with base_dir
		[[ "${resolved}" == "${base_dir}"/* || "${resolved}" == "${base_dir}" ]] || return 1
	fi

	echo "${resolved}"
	return 0
}

sanitize_filename() {
	local filename="$1"
	# Remove path components and dangerous characters
	basename "${filename}" | tr -d '\0' | sed 's/[^a-zA-Z0-9._-]/_/g'
}
