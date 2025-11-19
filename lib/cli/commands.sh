#!/usr/bin/env bash
# commands.sh - Command dispatch and dependency checks
# Part of wallshow - Professional Wallpaper Manager for Wayland/X11

# ============================================================================
# MAIN ENTRY POINT
# ============================================================================

main() {
	# Check for socket handler
	if [[ "${1:-}" == "--socket-handler" ]]; then
		handle_socket_command
		exit 0
	fi

	# Parse options and extract command (options can appear anywhere)
	local cmd=""
	while [[ $# -gt 0 ]]; do
		case "$1" in
		-h | --help)
			show_usage
			exit 0
			;;
		-v | --version)
			echo "${SCRIPT_NAME} v${VERSION}"
			exit 0
			;;
		-d | --debug)
			export LOG_LEVEL=${LOG_DEBUG}
			log_debug "Debug mode enabled"
			shift
			;;
		-c | --config)
			if [[ -z "${2:-}" ]]; then
				echo "[ERROR] --config requires a path argument" >&2
				show_usage
				exit "${E_USAGE}"
			fi
			export CONFIG_FILE="$2"
			shift 2
			;;
		-*)
			log_error "Unknown option: $1"
			show_usage
			exit "${E_USAGE}"
			;;
		*)
			# Not an option, must be the command (take first non-option)
			if [[ -z "${cmd}" ]]; then
				cmd="$1"
			fi
			shift
			;;
		esac
	done

	# Default to help if no command specified
	cmd="${cmd:-help}"

	# Check required dependencies
	if ! command -v jq &>/dev/null; then
		echo "[ERROR] jq is required but not installed" >&2
		echo "Install: sudo pacman -S jq" >&2
		exit "${E_DEPENDENCY}"
	fi

	if ! command -v socat &>/dev/null; then
		echo "[ERROR] socat is required but not installed" >&2
		echo "Install: sudo pacman -S socat" >&2
		exit "${E_DEPENDENCY}"
	fi

	# Check optional dependencies
	if ! command -v convert &>/dev/null && ! command -v magick &>/dev/null; then
		echo "[WARN] ImageMagick not found - GIF animations will not work" >&2
		echo "Install: sudo pacman -S imagemagick" >&2
	fi

	# Initialize
	init_directories
	init_config
	init_state

	# Handle commands
	case "${cmd}" in
	start)
		# Set up cleanup for persistent commands only
		trap 'cleanup' EXIT
		acquire_lock
		create_socket
		main_loop
		;;
	stop)
		send_socket_command "stop" || die "Daemon not running. Nothing to stop." "${E_GENERAL}"
		echo "Stopping wallpaper manager..."
		;;
	restart)
		"${SCRIPT_PATH}" stop

		# Wait for daemon to exit (max 10 seconds)
		log_info "Waiting for daemon to exit..."
		local max_attempts=20
		local attempt=0
		while ((attempt < max_attempts)); do
			if ! check_instance; then
				log_info "Daemon stopped after $((attempt * 500))ms"
				break
			fi
			sleep 0.5
			attempt=$((attempt + 1))
		done

		if ((attempt >= max_attempts)); then
			die "Daemon failed to stop within 10 seconds" "${E_GENERAL}"
		fi

		"${SCRIPT_PATH}" start
		;;
	daemon)
		# Cleanup trap is set inside daemon child process
		# Socket created inside daemonize() after lock acquisition
		daemonize
		;;
	next)
		send_socket_command "next" || die "Daemon not running. Start with: $0 daemon" "${E_GENERAL}"
		;;
	pause)
		send_socket_command "pause" || die "Daemon not running. Start with: $0 daemon" "${E_GENERAL}"
		;;
	resume)
		send_socket_command "resume" || die "Daemon not running. Start with: $0 daemon" "${E_GENERAL}"
		;;
	status)
		if ! send_socket_command "status" 2>/dev/null; then
			# Daemon not running, read state from file directly
			if [[ -f "${STATE_FILE}" ]]; then
				read_state '.'
			else
				die "State file not found. Run 'wallshow daemon' first." "${E_GENERAL}"
			fi
		fi
		;;
	info)
		show_info
		;;
	list)
		list_wallpapers
		;;
	reload)
		send_socket_command "reload" || die "Daemon not running. Start with: $0 daemon" "${E_GENERAL}"
		;;
	clean)
		cleanup_cache
		;;
	help)
		show_usage
		;;
	*)
		log_error "Unknown command: ${cmd}"
		show_usage
		exit "${E_USAGE}"
		;;
	esac
}
