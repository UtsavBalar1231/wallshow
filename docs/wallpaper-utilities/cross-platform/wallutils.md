# wallutils

## Overview

**wallutils** is a collection of utilities for handling monitors, resolutions, wallpapers, and timed wallpapers across Linux systems.

- **Display Server:** Cross-platform (X11 and Wayland)
- **Stability:** Stable, written in Go
- **Performance:** Good, cross-compositor compatibility

## GIF Support

⚠️ **Timed Wallpapers (Static Images)**

wallutils does not natively support animated GIFs, but provides:
- **Timed wallpaper rotation:** Cycle through static images based on time/schedule
- **GNOME timed wallpapers:** Support for XML-based timed wallpapers
- **Simple Timed Wallpaper format:** Custom format for time-based changes

For native GIF animation, use swww or mpvpaper.

## CLI Reference

wallutils provides multiple command-line utilities:

### setwallpaper

Set a wallpaper across different compositors:

```bash
# Set wallpaper (auto-detect compositor)
setwallpaper /path/to/wallpaper.jpg

# Verbose mode
setwallpaper -v wallpaper.jpg

# Specify mode (fill, scale, center, tile, stretch)
setwallpaper -m fill wallpaper.jpg
```

**Auto-detection:** setwallpaper automatically detects:
- Wayland compositors (sway, Hyprland, etc.)
- X11 window managers
- Display server type

### settimed

Set a timed wallpaper (changes based on time of day):

```bash
# Set timed wallpaper from Simple Timed Wallpaper file
settimed wallpaper.stw

# Set GNOME-style XML timed wallpaper
settimed wallpaper-timed.xml
```

### lstimed

Launch event loop for timed wallpapers:

```bash
# Run timed wallpaper daemon
lstimed wallpaper.stw

# With verbose output
lstimed -v wallpaper.stw
```

### getdpi

Query screen DPI:

```bash
getdpi
# Output: 96 (example)
```

### lsmon

List connected monitors:

```bash
lsmon
# Output:
# DP-1: 1920x1080
# HDMI-A-1: 2560x1440
```

### res

Set screen resolution:

```bash
# Set resolution
res 1920x1080

# List available resolutions
res -l
```

### xinfo

Display X11 server information:

```bash
xinfo
```

## Timed Wallpaper Format

wallutils introduces the **Simple Timed Wallpaper** (.stw) format:

```
# wallpaper.stw
# Time | Image Path
00:00: /path/to/night.jpg
06:00: /path/to/sunrise.jpg
12:00: /path/to/day.jpg
18:00: /path/to/sunset.jpg
```

Run with:
```bash
lstimed wallpaper.stw
```

## Supported Backends

wallutils supports many wallpaper backends:

**Wayland:**
- swaybg
- wlroots
- Wayfire
- KDE (via D-Bus)
- GNOME (via gsettings)

**X11:**
- feh
- nitrogen
- xwallpaper
- hsetroot
- And more

## Wallshow Integration

### Planned Implementation

wallutils will be added as a **universal fallback** when platform-specific tools aren't available.

**Location:** `lib/wallpaper/backends.sh:set_wallpaper_wallutils()` (NEW)

**Proposed Implementation:**
```bash
set_wallpaper_wallutils() {
    local image="$1"

    # setwallpaper auto-detects compositor/WM
    if setwallpaper -m fill "${image}" 2>/dev/null; then
        log_debug "Set wallpaper with wallutils: ${image}"
        return 0
    fi

    return 1
}
```

**Priority:** LOW (use after swww, swaybg, hyprpaper, feh, xwallpaper fail)

### Configuration

```json
{
  "tools": {
    "fallback_chain": ["swww", "hyprpaper", "swaybg", "wallutils", "feh", "xwallpaper"]
  }
}
```

### Known Issues/Limitations

1. **No Native GIF Support:** Static images only
2. **Detection Overhead:** Auto-detection may fail in edge cases
3. **Timed Wallpapers:** Conflicts with wallshow's rotation logic
4. **Backend Dependency:** Still requires underlying tools (swaybg, feh, etc.)

## Installation

```bash
# Arch Linux
pacman -S wallutils

# Fedora
dnf install wallutils

# FreeBSD
pkg install wallutils

# From source (Go required)
go install github.com/xyproto/wallutils/cmd/setwallpaper@latest
go install github.com/xyproto/wallutils/cmd/settimed@latest
go install github.com/xyproto/wallutils/cmd/lstimed@latest
go install github.com/xyproto/wallutils/cmd/lsmon@latest
```

**Dependencies:**
- Go toolchain (for building)
- Underlying wallpaper tools (swaybg, feh, etc.) for actual wallpaper setting

## Official Documentation

- **GitHub Repository:** [xyproto/wallutils](https://github.com/xyproto/wallutils)
- **Go Package Docs:** [pkg.go.dev/wallutils](https://pkg.go.dev/github.com/xyproto/wallutils)

## Example Usage

### Basic Wallpaper Setting

```bash
# Auto-detect and set wallpaper
setwallpaper ~/wallpapers/mountain.jpg

# Explicit mode
setwallpaper -m fill ~/wallpapers/photo.jpg
setwallpaper -m center ~/wallpapers/logo.png
setwallpaper -m tile ~/patterns/texture.png
```

### Timed Wallpapers

Create `day-night.stw`:
```
00:00: ~/wallpapers/night.jpg
06:00: ~/wallpapers/sunrise.jpg
12:00: ~/wallpapers/day.jpg
18:00: ~/wallpapers/sunset.jpg
22:00: ~/wallpapers/dusk.jpg
```

Run daemon:
```bash
lstimed ~/day-night.stw &
```

### Monitor Information

```bash
# List monitors
lsmon

# Get DPI
getdpi

# Available resolutions
res -l

# Change resolution
res 1920x1080
```

### GNOME XML Timed Wallpapers

```bash
# Set GNOME-style timed wallpaper
settimed /usr/share/backgrounds/gnome/adwaita-timed.xml

# Run as daemon
lstimed /usr/share/backgrounds/gnome/adwaita-timed.xml &
```

## Comparison with Other Tools

**vs swww:** wallutils is cross-platform but lacks native GIF; swww is Wayland-only with GIFs
**vs wpaperd:** wallutils has timed wallpapers; wpaperd is daemon-based with transitions
**vs feh/xwallpaper:** wallutils works on both X11 and Wayland; those are X11-only

## Best For

- Cross-platform wallpaper scripts
- Users switching between X11 and Wayland
- Timed wallpaper rotation based on time of day
- Universal fallback when other tools aren't available
- Monitor/resolution management

## Not Suitable For

- Animated GIFs (static only)
- Direct Wayland performance (uses swaybg underneath)
- Primary wallpaper tool (better to use native tools directly)

## Integration Notes for wallshow

**Recommendation: UNIVERSAL FALLBACK**

wallutils is best used as a **last-resort fallback**:

**Pros:**
- Cross-platform (X11 + Wayland)
- Auto-detection of environment
- Single command for multiple backends

**Cons:**
- Adds dependency layer (calls swaybg/feh underneath)
- No native GIF support
- Timed wallpaper feature conflicts with wallshow's rotation

**Use Case:**
- User has wallutils installed but lacks swww/swaybg/feh/xwallpaper
- Portable scripts that work across environments
- Fallback after all platform-specific tools fail

**Priority:** Last in fallback chain

**Fallback Order:**
```
Wayland: swww → hyprpaper → mpvpaper → swaybg → wallutils
X11: feh → xwallpaper → wallutils
```

## Timed Wallpapers vs wallshow

**Conflict:** Both wallutils (lstimed) and wallshow manage wallpaper rotation.

**Resolution:**
- If user wants timed rotation by time of day → use wallutils lstimed
- If user wants interval-based rotation → use wallshow
- Don't run both simultaneously (redundant daemons)

**Recommendation:** Document the difference, let users choose one approach.
