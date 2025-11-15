#!/usr/bin/env bash
# shellcheck disable=SC2034
# constants.sh - Core constants and configuration defaults
# Part of wallshow - Professional Wallpaper Manager for Wayland/X11

# ============================================================================
# METADATA
# ============================================================================

declare -r SCRIPT_NAME="wallshow"
declare -r VERSION="1.0.0"

# ============================================================================
# XDG BASE DIRECTORY COMPLIANCE
# ============================================================================

declare -r XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
declare -r XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
declare -r XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
declare -r XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

# ============================================================================
# APPLICATION DIRECTORIES
# ============================================================================

declare -r CONFIG_DIR="${XDG_CONFIG_HOME}/${SCRIPT_NAME}"
declare -r STATE_DIR="${XDG_STATE_HOME}/${SCRIPT_NAME}"
declare -r CACHE_DIR="${XDG_CACHE_HOME}/${SCRIPT_NAME}"
declare -r RUNTIME_DIR="${XDG_RUNTIME_DIR}/${SCRIPT_NAME}"

# ============================================================================
# CRITICAL FILES
# ============================================================================

declare -g CONFIG_FILE="${CONFIG_DIR}/config.json"
declare -r STATE_FILE="${STATE_DIR}/state.json"
declare -r LOCK_FILE="${RUNTIME_DIR}/instance.lock"
declare -r SOCKET_FILE="${RUNTIME_DIR}/control.sock"
declare -r PID_FILE="${RUNTIME_DIR}/daemon.pid"
declare -r LOG_FILE="${STATE_DIR}/wallpaper.log"

# ============================================================================
# DEFAULT CONFIGURATION
# ============================================================================

declare -r DEFAULT_CONFIG='{
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
    "preferred_animated": "auto",
    "fallback_chain": ["swww", "swaybg", "feh", "xwallpaper"]
  }
}'

# ============================================================================
# EXIT CODES
# ============================================================================

declare -ri E_SUCCESS=0
declare -ri E_GENERAL=1
declare -ri E_USAGE=2
declare -ri E_NOPERM=3
declare -ri E_LOCKED=5
declare -ri E_DEPENDENCY=8

# ============================================================================
# LOGGING LEVELS
# ============================================================================

declare -ri LOG_ERROR=0
declare -ri LOG_WARN=1
declare -ri LOG_INFO=2
declare -ri LOG_DEBUG=3

# ============================================================================
# GLOBAL STATE VARIABLES
# ============================================================================

declare -g LOCK_FD=""
declare -g LOG_LEVEL="${LOG_INFO}"
declare -g IS_DAEMON=false
declare -g CLEANUP_DONE=false
declare -g CONFIG_INITIALIZED=false
