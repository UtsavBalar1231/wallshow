#!/usr/bin/env bash
# shellcheck disable=SC2034
# constants.sh - Core constants and configuration defaults
# Part of wallshow - Professional Wallpaper Manager for Wayland/X11

# ============================================================================
# METADATA
# ============================================================================

declare -gr SCRIPT_NAME="wallshow"
declare -gr VERSION="1.0.0"

# ============================================================================
# XDG BASE DIRECTORY COMPLIANCE
# ============================================================================

declare -gr XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-${HOME}/.config}"
declare -gr XDG_STATE_HOME="${XDG_STATE_HOME:-${HOME}/.local/state}"
declare -gr XDG_CACHE_HOME="${XDG_CACHE_HOME:-${HOME}/.cache}"
declare -gr XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

# ============================================================================
# APPLICATION DIRECTORIES
# ============================================================================

declare -gr CONFIG_DIR="${XDG_CONFIG_HOME}/${SCRIPT_NAME}"
declare -gr STATE_DIR="${XDG_STATE_HOME}/${SCRIPT_NAME}"
declare -gr CACHE_DIR="${XDG_CACHE_HOME}/${SCRIPT_NAME}"
declare -gr RUNTIME_DIR="${XDG_RUNTIME_DIR}/${SCRIPT_NAME}"

# ============================================================================
# CRITICAL FILES
# ============================================================================

declare -g CONFIG_FILE="${CONFIG_DIR}/config.json"
declare -gr STATE_FILE="${STATE_DIR}/state.json"
declare -gr LOCK_FILE="${RUNTIME_DIR}/instance.lock"
declare -gr SOCKET_FILE="${RUNTIME_DIR}/control.sock"
declare -gr PID_FILE="${RUNTIME_DIR}/daemon.pid"
declare -gr LOG_FILE="${STATE_DIR}/wallpaper.log"

# ============================================================================
# DEFAULT CONFIGURATION
# ============================================================================

declare -gr DEFAULT_CONFIG='{
  "wallpaper_dirs": {
    "static": "~/Pictures/wallpapers",
    "animated": "~/Pictures/wallpapers/animated"
  },
  "intervals": {
    "change_seconds": 300,
    "transition_ms": 300,
    "gif_frame_ms": 50
  },
  "behavior": {
    "shuffle": true,
    "exclude_patterns": ["*.tmp", ".*"],
    "battery_optimization": true,
    "max_cache_size_mb": 500,
    "max_log_size_kb": 1024,
    "debug": false
  },
  "tools": {
    "preferred_static": "auto",
    "preferred_animated": "auto"
  }
}'

# ============================================================================
# RETRY LIMITS
# ============================================================================

declare -gri RETRY_STATE_UPDATE=5
declare -gri RETRY_WALLPAPER_SELECT=10
declare -gri RETRY_STATUS_UPDATE=3
declare -gri RETRY_ANIMATION_FAILURES=10

# ============================================================================
# INTERVALS (seconds unless noted)
# ============================================================================

declare -gri INTERVAL_CACHE_REFRESH=3600
declare -gri INTERVAL_CACHE_CLEANUP=3600
declare -gri INTERVAL_PID_CHECK=60
declare -gri INTERVAL_GRACEFUL_EXIT_DS=20 # deciseconds (2 seconds)

# ============================================================================
# LIMITS
# ============================================================================

declare -gri LIMIT_HISTORY_ENTRIES=100
declare -gri LIMIT_MIN_FRAME_DELAY_MS=10
declare -gri LIMIT_COMMAND_LOCK_TIMEOUT=30
declare -gri LIMIT_STATE_LOCK_TIMEOUT=5

# ============================================================================
# SUPPORTED TOOLS
# ============================================================================

declare -gra WALLPAPER_TOOLS=("swww" "swaybg" "hyprpaper" "mpvpaper" "wallutils" "feh" "xwallpaper")

# ============================================================================
# EXIT CODES
# ============================================================================

declare -gri E_SUCCESS=0
declare -gri E_GENERAL=1
declare -gri E_USAGE=2
declare -gri E_NOPERM=3
declare -gri E_LOCKED=5
declare -gri E_DEPENDENCY=8

# ============================================================================
# LOGGING LEVELS
# ============================================================================

declare -gri LOG_ERROR=0
declare -gri LOG_WARN=1
declare -gri LOG_INFO=2
declare -gri LOG_DEBUG=3

# ============================================================================
# GLOBAL STATE VARIABLES
# ============================================================================

declare -g LOCK_FD=""
declare -g LOG_LEVEL="${LOG_INFO}"
declare -g IS_DAEMON=false
declare -g CLEANUP_DONE=false
declare -g CONFIG_INITIALIZED=false
