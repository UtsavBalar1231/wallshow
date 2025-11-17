# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Wallshow is a professional wallpaper manager for Wayland/X11 written in Bash. It provides automated wallpaper rotation with support for both static and animated (GIF) wallpapers, daemon mode operation, battery optimization, and IPC control via Unix sockets.

## Quick Reference

**Common Commands:**
```bash
# Development
just install          # Install to ~/.local (includes systemd service)
just uninstall        # Remove from ~/.local (stops/disables service)
just run help         # Run from source without installing
just lint             # Run shellcheck
just ci-local         # Run all CI checks locally

# Testing
wallshow -d daemon    # Run daemon in foreground with debug
wallshow status | jq  # Check current status
tail -f ~/.local/state/wallshow/wallpaper.log  # Monitor logs

# Building
just build-all        # Build all packages (Debian, Arch, RPM)
```

**Key Files to Modify:**
- State schema: `system/init.sh:init_state()`
- Config schema: `core/constants.sh:DEFAULT_CONFIG`
- Module loading order: `bin/wallshow` (top section)

## Core Architecture

### Modular Design

Wallshow uses a **feature-based modular architecture** with 17 modules organized across 6 directories:

```
wallshow/
├── bin/
│   └── wallshow              # Main entry point (sources modules)
├── lib/                      # Modular libraries
│   ├── core/                 # Core functionality
│   │   ├── constants.sh      # Global constants, XDG paths, exit codes
│   │   ├── logging.sh        # Logging system with rotation
│   │   ├── state.sh          # JSON state management (atomic updates)
│   │   └── config.sh         # Configuration loading and validation
│   ├── system/               # System-level operations
│   │   ├── locking.sh        # Instance locking with flock
│   │   ├── paths.sh          # Path validation and sanitization
│   │   └── init.sh           # Directory initialization, cleanup handlers
│   ├── wallpaper/            # Wallpaper management
│   │   ├── discovery.sh      # Find and cache wallpapers
│   │   ├── selection.sh      # Random selection, battery awareness
│   │   └── backends.sh       # Backend support (swww, swaybg, feh, xwallpaper)
│   ├── animation/            # GIF animation support
│   │   ├── gif.sh            # Frame extraction, ImageMagick interface
│   │   └── playback.sh       # Animation subprocess, frame cycling
│   ├── daemon/               # Daemon mode
│   │   ├── process.sh        # Daemonization, signal handling
│   │   ├── ipc.sh            # Unix socket IPC, command handlers
│   │   └── loop.sh           # Main wallpaper change loop
│   └── cli/                  # Command-line interface
│       ├── commands.sh       # Command dispatch, dependency checks
│       └── interface.sh      # Help text, status display
├── debian/                   # Debian packaging
├── pkg/                      # Arch Linux packaging (PKGBUILD)
├── rpm/                      # Fedora packaging (spec file)
├── docs/                     # Design documents
├── Justfile                  # Development automation
└── wallshow-legacy.sh        # Archived original (single-file version)
```

### Module Dependencies

Modules are sourced in strict dependency order in `bin/wallshow`:

1. **core** modules (no dependencies)
2. **system** modules (depend on core)
3. **wallpaper** modules (depend on core + system)
4. **animation** modules (depend on core + wallpaper)
5. **daemon** modules (depend on all previous)
6. **cli** modules (depend on all previous)

**Important**: When adding new functionality, respect this dependency hierarchy.

### State Management
- **JSON-based state**: All runtime state stored in `$XDG_STATE_HOME/wallshow/state.json`
- **Atomic updates**: State modifications use `update_state_atomic()` for concurrent safety
- **Three-tier state model**:
  - Configuration (config.json): User preferences, intervals, tool selection
  - Runtime state (state.json): Current wallpaper, history, statistics, process PIDs
  - Cache (cache dir): Extracted GIF frames, wallpaper file lists with timestamps

### Process Model
- **Daemon mode**: Main loop runs as detached process with PID tracking
- **Instance locking**: flock-based mutex prevents concurrent instances (`RUNTIME_DIR/instance.lock`)
- **Animation subprocess**: Separate background process for GIF frame cycling (PID stored in state)
- **IPC socket**: Unix domain socket using socat for daemon control commands

### XDG Compliance
All paths follow XDG Base Directory specification:
- Config: `$XDG_CONFIG_HOME/wallshow/config.json`
- State: `$XDG_STATE_HOME/wallshow/state.json`
- Cache: `$XDG_CACHE_HOME/wallshow/` (GIF frames, wallpaper lists)
- Runtime: `$XDG_RUNTIME_DIR/wallshow/` (PID, socket, lock)

### Wallpaper Setting Strategy
Multi-tool support with intelligent fallback:
1. Try user-configured preferred tool (`config.tools.preferred_static`)
2. Display server detection (Wayland vs X11)
3. Fallback chain based on environment (swww → swaybg for Wayland, feh → xwallpaper for X11)
4. Each tool has dedicated `set_wallpaper_<tool>()` function
5. Tool availability cached via `detect_available_tools()`

### GIF Animation
- Frame extraction: Uses ImageMagick (convert/magick) to split GIFs into PNG frames
- Caching: Frames stored in `$CACHE_DIR/gifs/<sha256-hash>/frame_XXXX.png`
- Frame cycling: Background process updates wallpaper at configurable intervals
- Hash-based deduplication: Same GIF never extracted twice

## Development Workflow

### Development Setup

```bash
# Clone and enter directory
git clone https://github.com/UtsavBalar1231/wallshow.git
cd wallshow

# Install to ~/.local for testing (no root required, includes systemd service)
just install

# Enable auto-start on login (optional)
systemctl --user enable --now wallshow.service

# Or run directly from source without installing
# Note: bin/wallshow auto-detects lib/ in dev mode, so WALLSHOW_LIB is optional
just run help

# Or with explicit library path
WALLSHOW_LIB="$(pwd)/lib" ./bin/wallshow help
```

### Testing Commands

```bash
# Run lint only
just lint

# Test wallpaper setting (one-shot)
wallshow next

# Test daemon mode in foreground (debugging)
wallshow daemon

# Monitor logs in real-time
tail -f ~/.local/state/wallshow/wallpaper.log

# Check status
wallshow status | jq '.'
```

### Debugging

```bash
# Enable debug logging
wallshow -d daemon

# Inspect state file
jq '.' ~/.local/state/wallshow/state.json

# Check lock status
flock -n /run/user/$(id -u)/wallshow/instance.lock echo "unlocked" || echo "locked"

# Test wallpaper discovery
jq '.cache.static.files[]' ~/.local/state/wallshow/state.json
```

### Cache Management
```bash
# Check cache size
du -sh ~/.cache/wallshow

# Manual cache cleanup
wallshow clean

# Clear all cached GIF frames
rm -rf ~/.cache/wallshow/gifs/*
```

### Building Packages

```bash
# Build Debian package
just build-deb

# Build Arch package
just build-pkg

# Build Fedora package
just build-rpm

# Build all packages
just build-all
```

## Key Design Patterns

### Error Handling
- **Strict mode**: `set -euo pipefail` at module level
- **Exit codes**: Defined constants (E_SUCCESS, E_GENERAL, E_LOCKED, etc.) in `core/constants.sh`
- **Logging before death**: All `die()` calls log errors before exiting
- **Validation everywhere**: All external paths validated with `validate_path()` from `system/paths.sh`

### Concurrency Safety
- **File locking**: flock for instance mutex (see `system/locking.sh`)
- **Atomic state updates**: Temp file → move pattern for state.json (see `core/state.sh`)
- **Retry logic**: `update_state_atomic()` retries up to 5 times
- **PID validation**: `check_instance()` verifies process existence, not just file

### Battery Optimization
- When `behavior.battery_optimization` enabled and battery is discharging:
  - Only static wallpapers used
  - GIF animations skipped
  - Reduces CPU usage and power consumption
- Implementation: `should_use_animated()` in `wallpaper/selection.sh`

### Configuration Validation
- Config file must be valid JSON (validated on init and reload)
- Missing config auto-created from `DEFAULT_CONFIG` in `core/constants.sh`
- Corrupted state file automatically regenerated
- Tilde expansion for all directory paths

## Common Modification Patterns

### Adding New Wallpaper Tool Support
1. Add detection to `detect_available_tools()` in `wallpaper/backends.sh`
2. Create `set_wallpaper_<toolname>()` function in `wallpaper/backends.sh`
3. Add case branch in `set_wallpaper()` fallback logic
4. Update `DEFAULT_CONFIG.tools.fallback_chain` in `core/constants.sh`

### Adding IPC Commands
1. Add case branch in `handle_socket_command()` in `daemon/ipc.sh`
2. Ensure command sends response (echo "OK:..." or "ERROR:...")
3. Update `show_usage()` in `cli/interface.sh` if user-facing
4. Add corresponding CLI command in `main()` in `cli/commands.sh` if needed

### Extending State Schema
1. Update `init_state()` default_state JSON structure in `system/init.sh`
2. Add accessor functions using `read_state()` from `core/state.sh`
3. Use `update_state_atomic()` from `core/state.sh` for modifications
4. Update `show_info()` in `cli/interface.sh` if user-visible

### Adding Configuration Options
1. Update `DEFAULT_CONFIG` JSON in `core/constants.sh`
2. Access via `get_config()` from `core/config.sh`
3. Reload support via `reload_config()` if dynamic change needed
4. Validate in `init_config()` if critical

### Adding New Modules
1. Create new file in appropriate directory (core/system/wallpaper/animation/daemon/cli)
2. Respect dependency hierarchy (new module can only depend on modules loaded before it)
3. Add source line to `bin/wallshow` in correct dependency order
4. Document module responsibility in this file

## Critical Implementation Details

### JSON Escaping
When building JSON with dynamic values, always escape properly:
```bash
# WRONG: Will break on special characters
files_json="[\"${file}\"]"

# CORRECT: Use jq for escaping
escaped_file=$(printf '%s' "${file}" | jq -Rs .)
files_json=$(echo "${files_json}" | jq ". += [${escaped_file}]")
```

### State File Race Conditions
Never write directly to STATE_FILE:
```bash
# WRONG: Concurrent writes corrupt file
jq '.status = "running"' "$STATE_FILE" > "$STATE_FILE"

# CORRECT: Use update_state_atomic() (temp file + atomic move)
update_state_atomic '.status = "running"'
```

### Process Cleanup
Always clean up child processes:
- Stop animation subprocess before changing wallpapers
- Kill swaybg instances spawned by this script (track PIDs in state)
- Release locks in cleanup() trap
- Implementation: `cleanup()` and `cleanup_all_processes()` in `system/init.sh`

### Daemon Output
When IS_DAEMON=true, logs go to file only (not stderr), because:
- Stdout/stderr redirected to `daemon.out`/`daemon.err`
- Console output would pollute detached process

## Dependencies

**Required:**
- bash 5.0+
- jq (JSON processing)
- flock (instance locking, usually in util-linux)
- socat (IPC socket control)
- At least one wallpaper tool (swww, swaybg, feh, xwallpaper, etc.)

**Optional:**
- ImageMagick (convert/magick) - required for GIF support

**Development:**
- shellcheck (linting)
- just (task automation)

## Configuration Structure

The config.json schema:
```json
{
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
}
```

## Testing Considerations

**Note**: Wallshow currently has no automated test suite. All testing is manual.

**Before submitting changes, test these scenarios:**

1. **Fresh install**: Remove `~/.config/wallshow`, `~/.local/state/wallshow`, test first run
2. **Daemon lifecycle**: `start`, `status`, `next`, `pause`, `resume`, `stop`
3. **Concurrent starts**: Run two instances simultaneously (should fail with E_LOCKED)
4. **State corruption**: Delete/corrupt state.json while running (should auto-recover)
5. **IPC commands**: Test all socket commands work correctly
6. **Config reload**: Change config, reload, verify changes applied
7. **Tool availability**: Test with only one wallpaper tool available
8. **GIF handling**: Test with large GIFs (cache size limits, extraction failures)
9. **Battery transitions**: Simulate AC ↔ battery changes (animated should pause)
10. **Signal handling**: Send HUP (config reload), TERM (graceful shutdown)
11. **Error conditions**: Invalid config, missing directories, stale locks

## Code Style

This codebase follows strict Bash best practices:
- Functions use snake_case naming
- Constants use SCREAMING_SNAKE_CASE with `declare -r`
- All variables quoted: `"${var}"` not `$var`
- Process substitution preferred over pipes for loops (avoids subshells)
- Comprehensive error checking (exit code validation, file existence, etc.)
- Heavy commenting with section dividers
- Shellcheck compliance required for all shell code

See CONTRIBUTING.md for detailed code style guidelines.

### Commit Messages

Follow [Conventional Commits](https://www.conventionalcommits.org/):

**Format:**
```
<type>(<optional scope>): <description>

[optional body]
```

**Types:**
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `refactor`: Code refactoring (no behavior change)
- `test`: Adding or updating tests
- `chore`: Maintenance tasks

**Examples:**
```bash
feat(animation): add configurable GIF loop count
fix(daemon): handle SIGTERM gracefully
docs(readme): add systemd autostart instructions
refactor(state): extract atomic update logic to helper function
```

## Common Issues and Solutions

### "Instance already locked" error
```bash
# Check if wallshow is actually running
pgrep -f wallshow

# If no process, remove stale lock
rm /run/user/$(id -u)/wallshow/instance.lock
```

### "command not found: wallshow" after local install
```bash
# Ensure ~/.local/bin is in PATH
export PATH="$HOME/.local/bin:$PATH"
```

### Wallpaper not changing
1. Check daemon status: `wallshow status`
2. Verify wallpaper directory exists and contains images
3. Check logs: `tail -f ~/.local/state/wallshow/wallpaper.log`
4. Test wallpaper discovery: `jq '.cache.static.files[]' ~/.local/state/wallshow/state.json`

### GIFs not playing on battery
Battery optimization is enabled by default. To disable:
```bash
jq '.behavior.battery_optimization = false' ~/.config/wallshow/config.json > /tmp/config.json
mv /tmp/config.json ~/.config/wallshow/config.json
wallshow reload
```

## Packaging

Wallshow includes native packaging for:

- **Debian/Ubuntu**: `debian/` directory with debhelper build system
- **Arch Linux**: `pkg/PKGBUILD` for makepkg
- **Fedora/RHEL**: `rpm/wallshow.spec` for rpmbuild

All packages install to:
```
/usr/bin/wallshow                    # Main executable
/usr/lib/wallshow/                   # Library modules (preserved structure)
/usr/share/doc/wallshow/             # Documentation
/etc/logrotate.d/wallshow            # Logrotate configuration
/usr/lib/systemd/user/wallshow.service  # Systemd user service
```

Build with:
```bash
just build-deb    # Debian package
just build-pkg    # Arch package
just build-rpm    # Fedora package
just build-all    # All packages
```

## Development Automation (Justfile)

Common tasks are automated via `just`:

- `just install` - Install to ~/.local for testing
- `just uninstall` - Remove local installation
- `just lint` - Run shellcheck on all shell code
- `just pre-commit` - Run pre-commit hooks manually
- `just ci-local` - Run all CI checks locally
- `just run <args>` - Run from source without installing
- `just build-deb` - Build Debian package
- `just build-pkg` - Build Arch package
- `just build-rpm` - Build Fedora package
- `just build-all` - Build all packages
- `just clean` - Remove build artifacts

See `just --list` for all available commands.

## Log Rotation

Wallshow uses **logrotate** for professional log management (custom rotation logic was removed in favor of logrotate):

**Configuration**: `/etc/logrotate.d/wallshow`
- Daily rotation, keeps 7 days
- Gzip compression (delayed)
- Uses `copytruncate` to avoid interrupting daemon
- Handles all `*.log` files in `~/.local/state/wallshow/`

**Manual rotation test**:
```bash
logrotate -d /etc/logrotate.d/wallshow  # Dry run
```

The configuration is installed automatically by all packages and marked as `config(noreplace)` to preserve local modifications.

## Systemd Integration

Wallshow can run as a **systemd user service** for automatic startup:

**Enable and start**:
```bash
systemctl --user enable wallshow.service
systemctl --user start wallshow.service
```

**Check status**:
```bash
systemctl --user status wallshow.service
```

**View logs**:
```bash
journalctl --user -u wallshow.service -f
```

The service file is installed to `/usr/lib/systemd/user/wallshow.service` by all packages.

## CI/CD Pipeline

Wallshow uses **GitHub Actions** for automated testing and releases:

**Workflows**:
- **lint.yml**: Runs on push/PR - shellcheck, shfmt, YAML validation, packaging checks
- **build.yml**: Builds all packages (Debian, Arch, RPM) on push/PR, uploads artifacts
- **release.yml**: Triggered by git tags (v*.*.*) - builds packages, creates GitHub release with assets

**Local CI simulation**:
```bash
just ci-local  # Run all CI checks locally
```

## Pre-commit Hooks

Wallshow includes **pre-commit** configuration for automated code quality checks:

**Setup**:
```bash
pip install pre-commit
pre-commit install
```

**Manual run**:
```bash
pre-commit run --all-files
# or
just pre-commit
```

**Hooks configured**:
- shellcheck (linting)
- shfmt (formatting)
- trailing whitespace removal
- end-of-file newline fixer
- large file detection
- YAML/JSON validation

See `.pre-commit-config.yaml` for full configuration.

## Future Enhancements

Planned features for future releases:

- Man page generation from README
- Multi-monitor configuration support
- Additional backends (hyprpaper, mpvpaper)

See GitHub issues for current feature requests and roadmap.

## Legacy Code

The original single-file version (`wallshow-legacy.sh`) is archived for reference. All new development should use the modular architecture.

## References

- XDG Base Directory Specification
- Debian Policy Manual (packaging)
- Arch PKGBUILD guidelines
- Fedora RPM Packaging Guidelines
- shellcheck documentation
- Just command runner documentation
