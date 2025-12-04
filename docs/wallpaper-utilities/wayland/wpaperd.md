# wpaperd

## Overview

**wpaperd** is a modern wallpaper daemon for Wayland with hardware-accelerated transitions, per-display configuration, and timed wallpaper rotation.

- **Display Server:** Wayland (wlr_layer_shell protocol - sway, Hyprland, river, etc., and KDE)
- **Stability:** Stable, Rust-based
- **Performance:** Hardware-accelerated OpenGL ES rendering with smooth transitions

## GIF Support

❌ **Static Images Only (Timed Rotation)**

wpaperd does not support animated GIFs natively. Instead, it provides:
- **Timed wallpaper rotation:** Automatically cycle through static images in a directory
- **Directory scanning:** Recursively find wallpapers
- **Sorting options:** Random, ascending, descending

For native GIF animation, use swww or mpvpaper.

## CLI Reference

### wpaperd Daemon

Start the daemon (reads config from `~/.config/wpaperd/config.toml`):
```bash
wpaperd
```

The daemon runs in the background and handles wallpaper rotation based on configuration.

### wpaperctl (Control Utility)

Control the running daemon via IPC:

**Pause wallpaper rotation:**
```bash
wpaperctl pause
```

**Resume wallpaper rotation:**
```bash
wpaperctl resume
```

**Toggle pause/resume:**
```bash
wpaperctl toggle-pause
```

**Show help:**
```bash
wpaperctl --help
```

## Configuration

Configuration is **TOML-based** at `~/.config/wpaperd/config.toml`.

### Example Configuration

```toml
[default]
path = "~/Pictures/wallpapers"
duration = "30m"
sorting = "random"
recursive = true

[DP-1]
path = "~/Pictures/wallpapers/left"
duration = "15m"

[HDMI-A-1]
path = "~/Pictures/wallpapers/right"
duration = "15m"
sorting = "ascending"

[any]
path = "~/Pictures/wallpapers/fallback"
```

### Configuration Keys

**Per-display sections:** `[monitor-name]` or special sections:
- **`[default]`** - Base configuration for all displays
- **`[any]`** - Configuration for displays not explicitly listed

**Keys:**
- **`path`** (string) - Path to image file or directory
- **`duration`** (string) - Time to display each wallpaper (e.g., `"30m"`, `"1h"`, `"300s"`)
- **`sorting`** (string) - Sort order: `"random"`, `"ascending"`, `"descending"` (default: `"random"`)
- **`recursive`** (bool) - Recursively search `path` directory (default: `false`)
- **`exec`** (string) - Script to execute when wallpaper changes (receives display and wallpaper path as args)

### Example: Script Execution

```toml
[default]
path = "~/wallpapers"
exec = "~/.config/wpaperd/on-change.sh"
```

Script receives:
```bash
#!/bin/bash
# $1 = display name (e.g., "DP-1")
# $2 = wallpaper path
echo "Changed wallpaper on $1 to $2"
```

## Wallshow Integration

### Planned Implementation

wpaperd will be added as a **low-priority Wayland fallback** for static wallpapers, since it requires config file manipulation.

**Location:** `lib/wallpaper/backends.sh:set_wallpaper_wpaperd()` (NEW)

**Proposed Implementation:**

wpaperd integration is **complex** due to config-file-based control. Two approaches:

**Approach 1: Config Manipulation**
```bash
set_wallpaper_wpaperd() {
    local image="$1"
    local config_file="${XDG_CONFIG_HOME:-$HOME/.config}/wpaperd/config.toml"

    # Update config file
    cat > "${config_file}" <<EOF
[default]
path = "${image}"
duration = "9999h"
sorting = "random"
EOF

    # Reload daemon (SIGHUP)
    pkill -HUP wpaperd || return 1

    log_debug "Set wallpaper with wpaperd: ${image}"
    return 0
}
```

**Approach 2: Daemon Toggle (Not Ideal)**
```bash
# Kill wpaperd, manually set wallpaper with other tool
# Not recommended - defeats purpose of daemon
```

**Recommendation:** Use wpaperd for its intended purpose (timed rotation) rather than wallshow integration. Priority: **LOW** or **SKIP**.

### Configuration

```json
{
  "tools": {
    "preferred_static": "wpaperd"
  }
}
```

**Note:** Given the config-file-driven nature, wpaperd is better suited for users who want automated rotation without wallshow intervention.

### Known Issues/Limitations

1. **Config File Required:** No direct CLI wallpaper setting, must edit TOML config
2. **Daemon Required:** wpaperd must be running
3. **No GIF Support:** Static images only
4. **Reload Complexity:** Config changes require daemon reload (SIGHUP or restart)
5. **Not Ideal for wallshow:** wallshow prefers direct CLI control; wpaperd is daemon-centric

## Installation

```bash
# Arch Linux
pacman -S wpaperd

# Debian/Ubuntu (build from source)
# Install Rust toolchain first
cargo install wpaperd

# Fedora (via Cargo)
dnf install cargo
cargo install wpaperd

# From source
git clone https://github.com/danyspin97/wpaperd.git
cd wpaperd
cargo build --release
sudo cp target/release/wpaperd /usr/local/bin/
sudo cp target/release/wpaperctl /usr/local/bin/
```

**Dependencies:**
- Rust toolchain (for building)
- Wayland compositor with wlr_layer_shell protocol (or KDE)

## Official Documentation

- **GitHub Repository:** [danyspin97/wpaperd](https://github.com/danyspin97/wpaperd)
- **Man Page:** [wpaperd(1)](https://man.archlinux.org/man/extra/wpaperd/wpaperd.1.en)
- **README:** [wpaperd/README.md](https://github.com/danyspin97/wpaperd/blob/main/README.md)

## Example Usage

### Basic Setup

1. Create config file:
```toml
# ~/.config/wpaperd/config.toml
[default]
path = "~/Pictures/wallpapers"
duration = "30m"
sorting = "random"
recursive = true
```

2. Start daemon:
```bash
wpaperd &
```

### Multi-Monitor Setup

```toml
[DP-1]
path = "~/wallpapers/landscape"
duration = "15m"

[HDMI-A-1]
path = "~/wallpapers/portrait"
duration = "15m"
sorting = "ascending"
```

### Pause/Resume Control

```bash
# Pause rotation
wpaperctl pause

# Resume rotation
wpaperctl resume

# Toggle
wpaperctl toggle-pause
```

### Run Script on Wallpaper Change

```toml
[default]
path = "~/wallpapers"
exec = "notify-send 'Wallpaper Changed' '$2'"
```

## Comparison with Other Tools

**vs swww:** wpaperd has timed rotation built-in; swww requires external rotation scripts
**vs swaybg:** wpaperd is daemon-based with auto-rotation; swaybg requires manual control
**vs hyprpaper:** wpaperd automates rotation; hyprpaper requires IPC commands for changes

## Best For

- Users who want **automated wallpaper rotation**
- Daemon-based background management
- Smooth hardware-accelerated transitions
- Per-monitor wallpaper directories
- "Set it and forget it" wallpaper management

## Not Suitable For

- Direct CLI wallpaper setting (use swaybg/hyprpaper instead)
- Animated GIFs (use swww/mpvpaper)
- Integration with external wallpaper managers like wallshow (config overhead)

## Integration Notes for wallshow

**Recommendation: LOW PRIORITY or SKIP**

wpaperd's design conflicts with wallshow's use case:
- wpaperd is a **competing daemon** - it manages its own rotation
- wallshow **also manages rotation** - creates redundancy
- Config file manipulation adds complexity vs. direct CLI tools

**Better Use Case:** Users choose either wallshow OR wpaperd, not both.

If integration is desired:
- Only use wpaperd when wallshow is in "delegate mode" (user wants automated rotation)
- Modify config file to set single image with very long duration
- Complexity doesn't justify benefit over swww/swaybg/hyprpaper
