#!/usr/bin/env bash
# session.sh - Session context for wallpaper tool resolution
# Part of wallshow - Professional Wallpaper Manager for Wayland/X11
#
# Resolves wallpaper tools ONCE at daemon startup instead of on every
# set_wallpaper() call. This eliminates redundant tool detection during
# GIF animation (which calls set_wallpaper() 20+ times per second).

set -euo pipefail

# ============================================================================
# SESSION CONTEXT
# ============================================================================

# Session context (initialized once, immutable during session)
# Using associative array for clarity and extensibility
declare -gA SESSION_CONTEXT=(
	[display_server]=""
	[available_tools]=""
	[resolved_static_tool]=""
	[resolved_gif_tool]=""
	[initialized]="false"
)

# ============================================================================
# INITIALIZATION
# ============================================================================

# Initialize session context (call once at daemon startup)
# Resolves tools upfront so set_wallpaper() can use O(1) lookup
init_session_context() {
	if [[ "${SESSION_CONTEXT[initialized]}" == "true" ]]; then
		return 0
	fi

	# Detect environment (never changes during session)
	SESSION_CONTEXT[display_server]=$(detect_display_server)
	SESSION_CONTEXT[available_tools]=$(detect_available_tools)

	# Validate and resolve preferred tools from config
	local preferred_static preferred_gif
	preferred_static=$(get_config '.tools.preferred_static' 'auto')
	preferred_gif=$(get_config '.tools.preferred_animated' 'auto')

	# Resolve static tool (with display server validation)
	SESSION_CONTEXT[resolved_static_tool]=$(_resolve_tool_for_type \
		"static" "${preferred_static}" "${SESSION_CONTEXT[display_server]}" \
		"${SESSION_CONTEXT[available_tools]}")

	# Resolve GIF tool (with display server validation)
	SESSION_CONTEXT[resolved_gif_tool]=$(_resolve_tool_for_type \
		"gif" "${preferred_gif}" "${SESSION_CONTEXT[display_server]}" \
		"${SESSION_CONTEXT[available_tools]}")

	SESSION_CONTEXT[initialized]="true"

	log_info "Session context initialized:"
	log_info "  Display server: ${SESSION_CONTEXT[display_server]}"
	log_info "  Static tool: ${SESSION_CONTEXT[resolved_static_tool]}"
	log_info "  GIF tool: ${SESSION_CONTEXT[resolved_gif_tool]}"
}

# ============================================================================
# TOOL RESOLUTION
# ============================================================================

# Resolve tool for a given type with display server validation
# This validates that preferred tools are compatible with the display server
# before falling back to auto-selection
_resolve_tool_for_type() {
	local type="$1"
	local preferred="$2"
	local display_server="$3"
	local available_tools="$4"

	# If preferred tool is set and compatible, use it
	if [[ "${preferred}" != "auto" ]]; then
		local preferred_ds
		preferred_ds=$(tool_display_server "${preferred}")
		if [[ "${preferred_ds}" == "${display_server}" ]] || [[ "${preferred_ds}" == "both" ]]; then
			if echo "${available_tools}" | grep -qx "${preferred}"; then
				log_debug "Using preferred ${type} tool: ${preferred}"
				echo "${preferred}"
				return 0
			fi
			log_warn "Preferred ${type} tool '${preferred}' not available"
		else
			log_warn "Preferred ${type} tool '${preferred}' incompatible with ${display_server}, using auto"
		fi
	fi

	# Auto-select best tool using existing selection logic
	# Use dummy image path to trigger correct type detection
	local dummy_image="/tmp/dummy.png"
	[[ "${type}" == "gif" ]] && dummy_image="/tmp/dummy.gif"

	local selected
	selected=$(select_best_tool "${dummy_image}" "${available_tools}" "${display_server}")

	if [[ -n "${selected}" ]]; then
		log_debug "Auto-selected ${type} tool: ${selected}"
		echo "${selected}"
		return 0
	fi

	log_error "No suitable ${type} tool available for ${display_server}"
	return 1
}

# ============================================================================
# PUBLIC API
# ============================================================================

# Get resolved tool for image type (fast O(1) lookup)
# This is the main function called by set_wallpaper()
get_session_tool() {
	local image="$1"

	# Lazy initialization for CLI commands that don't go through daemonize()
	if [[ "${SESSION_CONTEXT[initialized]}" != "true" ]]; then
		init_session_context
	fi

	if is_gif "${image}"; then
		echo "${SESSION_CONTEXT[resolved_gif_tool]}"
	else
		echo "${SESSION_CONTEXT[resolved_static_tool]}"
	fi
}

# Get session display server
get_session_display_server() {
	if [[ "${SESSION_CONTEXT[initialized]}" != "true" ]]; then
		init_session_context
	fi
	echo "${SESSION_CONTEXT[display_server]}"
}

# Get session available tools
get_session_available_tools() {
	if [[ "${SESSION_CONTEXT[initialized]}" != "true" ]]; then
		init_session_context
	fi
	echo "${SESSION_CONTEXT[available_tools]}"
}

# Check if session is initialized
is_session_initialized() {
	[[ "${SESSION_CONTEXT[initialized]}" == "true" ]]
}

# ============================================================================
# INVALIDATION
# ============================================================================

# Invalidate session context (for config reload or tool failure recovery)
# Next call to get_session_tool() will re-initialize
invalidate_session_context() {
	SESSION_CONTEXT[initialized]="false"
	SESSION_CONTEXT[display_server]=""
	SESSION_CONTEXT[available_tools]=""
	SESSION_CONTEXT[resolved_static_tool]=""
	SESSION_CONTEXT[resolved_gif_tool]=""
	log_debug "Session context invalidated"
}
