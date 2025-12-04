# hyprpaper

## Overview

**hyprpaper** is a blazing fast wallpaper utility for Hyprland with IPC controls, though it works on all wlroots-based compositors.

- **Display Server:** Wayland only (optimized for Hyprland, compatible with wlroots)
- **Stability:** Stable, actively maintained by Hyprland project
- **Performance:** Very fast, memory-efficient with preload/unload system

## GIF Support

❌ **Static Images Only**

hyprpaper does not support animated GIFs or videos. It's designed for static wallpapers only.

For animated wallpapers on Hyprland, use swww or mpvpaper instead.

## CLI Reference

### IPC Control via hyprctl

hyprpaper is controlled through Hyprland's `hyprctl` IPC interface:

```bash
hyprctl hyprpaper <command> [args...]
```

### Core Commands

**Preload an image into memory:**
```bash
hyprctl hyprpaper preload /path/to/wallpaper.jpg
```

**Set wallpaper for a monitor:**
```bash
# Syntax: wallpaper <monitor>,<path>
hyprctl hyprpaper wallpaper "DP-1,/path/to/wallpaper.jpg"

# Use empty monitor name for all monitors
hyprctl hyprpaper wallpaper ",/path/to/wallpaper.jpg"
```

**Unload image from memory:**
```bash
hyprctl hyprpaper unload /path/to/wallpaper.jpg
```

**List preloaded wallpapers:**
```bash
hyprctl hyprpaper listloaded
```

**List active wallpapers:**
```bash
hyprctl hyprpaper listactive
```

**Reload with new wallpaper (combines preload + set + unload old):**
```bash
# The "reload" command automates the full workflow
hyprctl hyprpaper reload "DP-1,/path/to/new.jpg"
```

### Memory Management

The preload/set/unload pattern ensures efficient memory usage:

```bash
# Manual workflow:
hyprctl hyprpaper preload wallpaper_new.jpg
hyprctl hyprpaper wallpaper ",wallpaper_new.jpg"
hyprctl hyprpaper unload wallpaper_old.jpg

# Automatic workflow (recommended):
hyprctl hyprpaper reload ",wallpaper_new.jpg"
```

## Configuration File

hyprpaper can be configured via `~/.config/hypr/hyprpaper.conf` (optional):

```conf
# Preload wallpapers at startup
preload = /path/to/wallpaper1.jpg
preload = /path/to/wallpaper2.jpg

# Set wallpapers for monitors
wallpaper = DP-1,/path/to/wallpaper1.jpg
wallpaper = HDMI-A-1,/path/to/wallpaper2.jpg

# Splash text (disable recommended for wallshow)
splash = false

# IPC socket (enable for runtime control)
ipc = on
```

**Note:** wallshow will use IPC commands, not the config file.

## Scaling/Positioning Modes

Set fitting mode in the config or via `contain:` prefix:

```bash
# Default is cover (zoom to fill)
hyprctl hyprpaper wallpaper "DP-1,/path/to/wallpaper.jpg"

# Use contain mode (fit entire image)
hyprctl hyprpaper wallpaper "DP-1,contain:/path/to/wallpaper.jpg"
```

**Modes:**
- **Default (cover):** Zoom to fill screen, preserving aspect ratio (may crop)
- **contain:** Fit entire image, preserving aspect ratio (may show borders)

## Wallshow Integration

### Planned Implementation

hyprpaper will be added as a **high-priority Wayland backend** for static wallpapers.

**Location:** `lib/wallpaper/backends.sh:set_wallpaper_hyprpaper()` (NEW)

**Proposed Implementation:**
```bash
set_wallpaper_hyprpaper() {
    local image="$1"

    # Get list of previously loaded wallpapers
    local old_wallpapers
    old_wallpapers=$(hyprctl hyprpaper listloaded 2>/dev/null || echo "")

    # Preload new wallpaper
    hyprctl hyprpaper preload "${image}" || return 1

    # Set for all monitors
    hyprctl hyprpaper wallpaper ",${image}" || return 1

    # Unload old wallpapers (cleanup)
    while IFS= read -r old_wp; do
        [[ "${old_wp}" != "${image}" ]] && \
            hyprctl hyprpaper unload "${old_wp}" 2>/dev/null || true
    done <<<"${old_wallpapers}"

    log_debug "Set wallpaper with hyprpaper: ${image}"
    return 0
}
```

Alternatively, use the simpler `reload` command:
```bash
set_wallpaper_hyprpaper() {
    local image="$1"
    hyprctl hyprpaper reload ",${image}" || return 1
    log_debug "Set wallpaper with hyprpaper: ${image}"
    return 0
}
```

### Configuration

```json
{
  "tools": {
    "preferred_static": "hyprpaper"
  }
}
```

### Known Issues/Limitations

1. **Static Only:** No GIF or video support
2. **Hyprland IPC Required:** Needs `hyprctl` command available
3. **No Transitions:** Instant wallpaper change
4. **Monitor Names:** Requires correct monitor names (get via `hyprctl monitors`)

## Installation

```bash
# Arch Linux
pacman -S hyprpaper

# Debian/Ubuntu (build from source or use Hyprland repos)
# Not in official Debian repos as of 2025

# Fedora (via Hyprland COPR or source)
dnf copr enable solopasha/hyprland
dnf install hyprpaper

# From source
git clone https://github.com/hyprwm/hyprpaper.git
cd hyprpaper
cmake --no-warn-unused-cli -DCMAKE_BUILD_TYPE:STRING=Release -S . -B ./build
cmake --build ./build --config Release --target hyprpaper -j$(nproc)
sudo cmake --install build
```

**Dependencies:**
- Hyprland or wlroots-based compositor
- cairo
- pango
- file (libmagic)

## Official Documentation

- **GitHub Repository:** [hyprwm/hyprpaper](https://github.com/hyprwm/hyprpaper)
- **Hyprland Wiki:** [hyprpaper Documentation](https://wiki.hypr.land/Hypr-Ecosystem/hyprpaper/)
- **IPC Reference:** [Hyprland Wiki - hyprpaper](https://wiki.hypr.land/hyprland-wiki/pages/Hypr-Ecosystem/hyprpaper/)

## Example Usage

```bash
# Start hyprpaper daemon (usually via Hyprland config)
hyprpaper &

# Preload wallpaper
hyprctl hyprpaper preload ~/wallpapers/mountain.jpg

# Set for all monitors
hyprctl hyprpaper wallpaper ",~/wallpapers/mountain.jpg"

# Set different wallpapers per monitor
hyprctl hyprpaper preload ~/wallpapers/left.jpg
hyprctl hyprpaper preload ~/wallpapers/right.jpg
hyprctl hyprpaper wallpaper "DP-1,~/wallpapers/left.jpg"
hyprctl hyprpaper wallpaper "HDMI-A-1,~/wallpapers/right.jpg"

# Quick reload (recommended for wallshow)
hyprctl hyprpaper reload ",~/wallpapers/new.jpg"

# Check what's loaded
hyprctl hyprpaper listloaded
hyprctl hyprpaper listactive
```

## Comparison with Other Tools

**vs swww:** hyprpaper is faster for static images, but lacks GIF support and transitions
**vs swaybg:** hyprpaper has better memory management (preload/unload), fewer orphaned processes
**vs wpaperd:** hyprpaper requires manual control; wpaperd automates timed rotation

## Best For

- Hyprland users wanting fast static wallpapers
- Users who need efficient memory management
- Multi-monitor setups with IPC control
- Static wallpaper rotation without daemon overhead
