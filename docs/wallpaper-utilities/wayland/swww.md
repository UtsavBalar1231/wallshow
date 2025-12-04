# swww

## Overview

**swww** (Solution to your Wayland Wallpaper Woes) is an efficient animated wallpaper daemon for Wayland compositors, controlled at runtime.

- **Display Server:** Wayland only (wlroots-based compositors)
- **Stability:** Mature, actively maintained
- **Performance:** Hardware-accelerated, optimized for minimal CPU usage during animation

## GIF Support

✅ **Native Animated GIF/APNG Support**

swww natively supports animated GIFs and APNGs without requiring external frame extraction:
- Built-in frame caching for efficient playback
- Significantly more memory efficient than oguri
- Lower CPU usage once frames are cached
- Smooth playback with configurable transition effects

**Performance:** Ideal for animated wallpapers - no need for ImageMagick frame extraction or rapid wallpaper switching.

## CLI Reference

### Basic Commands

Start the swww daemon:
```bash
swww-daemon
```

Set a wallpaper (static or animated):
```bash
swww img /path/to/wallpaper.png
swww img /path/to/animated.gif
```

Stop the daemon:
```bash
swww kill
```

### Advanced Options

**Transitions:**
```bash
# Random transition effect
swww img wallpaper.jpg --transition-type random

# Specific transition types
swww img wallpaper.jpg --transition-type fade
swww img wallpaper.jpg --transition-type wipe

# Custom transition duration (in seconds)
swww img wallpaper.jpg --transition-duration 2.5
```

**Per-Monitor Control:**
```bash
# Set wallpaper for specific output
swww img -o DP-1 wallpaper1.jpg
swww img -o HDMI-A-1 wallpaper2.jpg
```

**Transition Speed:**
```bash
# Control frame rate and step size
swww img wallpaper.jpg \
  --transition-step 90 \
  --transition-fps 60
```

### Daemon Options

```bash
# Start daemon with specific pixel format (default: xrgb)
swww-daemon --format argb
swww-daemon --format xrgb
swww-daemon --format rgb
```

## Scaling/Positioning Modes

swww automatically scales images to fit the screen while preserving aspect ratio (similar to "fill" mode). Positioning is centered by default.

## Wallshow Integration

### Current Implementation

wallshow uses swww as the **primary Wayland wallpaper backend** when available.

**Location:** `lib/wallpaper/backends.sh:set_wallpaper_swww()`

**Implementation Details:**
1. Checks if `swww-daemon` is running
2. Starts daemon if needed (with `--format argb`)
3. Tracks daemon PID in state for cleanup
4. Uses `swww img` with configurable transition settings
5. Supports both static images and animated GIFs natively

### Configuration

```json
{
  "tools": {
    "preferred_static": "swww",
    "preferred_animated": "swww"
  },
  "intervals": {
    "transition_ms": 300
  }
}
```

The `transition_ms` config value is converted to seconds with decimal precision:
```bash
# transition_ms=300 becomes:
swww img wallpaper.jpg --transition-duration 0.300
```

### Known Issues/Limitations

1. **Daemon Persistence:** swww-daemon must remain running for wallpapers to persist
2. **Startup Time:** Brief delay (~300ms) when starting daemon from stopped state
3. **Compositor Compatibility:** Requires wlroots-based compositor (works with sway, Hyprland, river, etc.)

## Installation

```bash
# Arch Linux
pacman -S swww

# Debian/Ubuntu (via external repos or build from source)
# Not in official repos as of 2025

# Fedora
dnf install swww

# From source (Rust required)
cargo install swww
```

**Dependencies:**
- Rust toolchain (for building from source)
- wlroots-based Wayland compositor

## Official Documentation

- **GitHub Repository:** [LGFae/swww](https://github.com/LGFae/swww)
- **Man Page:** [swww(1)](https://man.archlinux.org/man/swww.1.en)
- **Arch Wiki Reference:** [Wayland#Wallpapers](https://wiki.archlinux.org/title/Wayland#Wallpapers)

## Example Usage

```bash
# Start daemon
swww-daemon &

# Set animated GIF as wallpaper
swww img ~/wallpapers/animated.gif --transition-type fade

# Set different wallpapers for dual monitors
swww img -o DP-1 ~/wallpapers/left.jpg
swww img -o HDMI-A-1 ~/wallpapers/right.jpg

# Use with wallshow
wallshow start  # Automatically uses swww if available
```

## Comparison with Other Tools

**vs swaybg:** swww supports animated wallpapers natively; swaybg is static-only
**vs hyprpaper:** swww has native GIF support and transitions; hyprpaper is faster for static images
**vs mpvpaper:** swww is more efficient for GIFs; mpvpaper is better for full videos

## Best For

- Animated GIF/APNG wallpapers on Wayland
- Smooth transitions between wallpapers
- Multi-monitor setups with different wallpapers per display
- Users who want efficient, hardware-accelerated wallpaper management
