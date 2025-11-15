#!/usr/bin/env bash
# locking.sh - Instance locking with flock
# Part of wallshow - Professional Wallpaper Manager for Wayland/X11

# ============================================================================
# INSTANCE LOCKING
# ============================================================================

acquire_lock() {
	local timeout=${1:-0}

	# Create lock file if it doesn't exist
	touch "${LOCK_FILE}" || die "Cannot create lock file" "${E_NOPERM}"

	# Open lock file and get file descriptor
	exec {LOCK_FD}<>"${LOCK_FILE}"

	# Try to acquire exclusive lock
	if [[ ${timeout} -gt 0 ]]; then
		if ! flock -w "${timeout}" -x "${LOCK_FD}"; then
			log_error "Another instance is running (timeout after ${timeout}s)"
			exit "${E_LOCKED}"
		fi
	else
		if ! flock -n -x "${LOCK_FD}"; then
			log_error "Another instance is running"
			exit "${E_LOCKED}"
		fi
	fi

	# Write our PID to lock file
	echo $$ >"${LOCK_FILE}"

	log_debug "Lock acquired (PID: $$)"
	return 0
}

release_lock() {
	if [[ -n "${LOCK_FD}" ]]; then
		flock -u "${LOCK_FD}" 2>/dev/null || true
		exec {LOCK_FD}>&- 2>/dev/null || true
		LOCK_FD=""
		log_debug "Lock released"
	fi
}

check_instance() {
	# Defense-in-depth instance checking:
	# 1. Try to acquire lock (atomic check)
	# 2. Validate PID file if lock held
	# 3. Clean stale PID if process dead

	local test_fd
	exec {test_fd}>"${LOCK_FILE}"

	if flock -n "${test_fd}"; then
		# Lock acquired - check for stale PID file
		if [[ -f "${PID_FILE}" ]]; then
			local old_pid
			old_pid=$(cat "${PID_FILE}" 2>/dev/null)
			if [[ -n "${old_pid}" ]] && ! kill -0 "${old_pid}" 2>/dev/null; then
				log_warn "Removing stale PID file (process ${old_pid} not running)"
				rm -f "${PID_FILE}"
			fi
		fi

		# Release lock - no instance running
		flock -u "${test_fd}"
		exec {test_fd}>&-
		return 1
	else
		# Lock held - validate PID is actually alive
		if [[ -f "${PID_FILE}" ]]; then
			local running_pid
			running_pid=$(cat "${PID_FILE}" 2>/dev/null)
			if [[ -n "${running_pid}" && "${running_pid}" =~ ^[0-9]+$ ]] && kill -0 "${running_pid}" 2>/dev/null; then
				# Valid instance running
				exec {test_fd}>&-
				return 0
			fi
		fi

		# Lock held but PID invalid - possible startup race
		# Conservative: assume instance is starting
		exec {test_fd}>&-
		return 0
	fi
}
