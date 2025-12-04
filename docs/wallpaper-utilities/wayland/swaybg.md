# swaybg

## Overview

**swaybg** is a simple, lightweight wallpaper utility for Wayland compositors, originally developed for sway but compatible with all wlroots-based compositors.

- **Display Server:** Wayland only (wlroots-based compositors)
- **Stability:** Very mature, stable
- **Performance:** Minimal resource usage for static backgrounds

## GIF Support

❌ **Static Images Only**

swaybg does not support animated GIFs natively. For animated wallpapers:
- **Workaround:** Extract GIF frames with ImageMagick, then rapidly restart swaybg with new frames
- **wallshow approach:** Automatically handles frame extraction and cycling when swaybg is used

**Performance Note:** Frequent restarts for GIF animation incurs overhead. For native GIF support, use swww or mpvpaper instead.

## CLI Reference

### Basic Commands

Set wallpaper with fill mode (most common):
```bash
swaybg -i /path/to/wallpaper.jpg -m fill
```

Stop swaybg:
```bash
killall swaybg
# or
pkill swaybg
```

### Scaling/Positioning Modes

Available modes via `-m, --mode`:

- **`fill`** - Scale image to fill screen, preserving aspect ratio (may crop)
- **`fit`** - Scale image to fit screen, preserving aspect ratio (may show black bars)
- **`stretch`** - Stretch image to fill screen, ignoring aspect ratio
- **`center`** - Center image at original size (black bars if smaller than screen)
- **`tile`** - Repeat image in a tiled pattern
- **`solid_color`** - Display only background color (no image)

```bash
# Examples
swaybg -i wallpaper.jpg -m fill      # Default, best for photos
swaybg -i wallpaper.jpg -m fit       # Show entire image
swaybg -i wallpaper.jpg -m stretch   # Distort to fill
swaybg -i wallpaper.jpg -m center    # Original size, centered
swaybg -i wallpaper.jpg -m tile      # Repeat pattern
```

### Background Color

Set background color (shown when image doesn't fill screen):
```bash
# Hex color (rrggbb or rrggbbaa format)
swaybg -c 000000                     # Black
swaybg -c ff5555                     # Red
swaybg -c ff5555ff                   # Red with full opacity

# Solid color without image
swaybg -c 222222 -m solid_color
```

### Per-Monitor Control

Specify output for multi-monitor setups:
```bash
# Set wallpaper for specific output
swaybg -o DP-1 -i wallpaper1.jpg -m fill

# Run multiple instances for different monitors
swaybg -o DP-1 -i left.jpg -m fill &
swaybg -o HDMI-A-1 -i right.jpg -m fill &

# Apply to all outputs (default)
swaybg -o '*' -i wallpaper.jpg -m fill
```

### Complete Syntax

```bash
swaybg -i <image> -m <mode> [-c <color>] [-o <output>]
```

**Options:**
- `-i, --image <path>` - Path to image file
- `-m, --mode <mode>` - Scaling mode (fill, fit, stretch, center, tile, solid_color)
- `-c, --color <rrggbb[aa]>` - Background color in hex
- `-o, --output <name>` - Output name (monitor), use `*` for all
- `-h, --help` - Show help
- `-v, --version` - Show version

## Wallshow Integration

### Current Implementation

swaybg is the **fallback Wayland backend** when swww is unavailable.

**Location:** `lib/wallpaper/backends.sh:set_wallpaper_swaybg()`

**Implementation Details:**
1. Kills previous swaybg instances spawned by wallshow (PID tracking)
2. Starts new swaybg instance in background
3. Uses `-m fill` mode by default
4. Stores PID in state.json for cleanup
5. For GIF animation: kills/restarts swaybg with each frame

### Configuration

```json
{
  "tools": {
    "preferred_static": "swaybg"
  }
}
```

### Known Issues/Limitations

1. **No Transitions:** Instant wallpaper change, no fade effects
2. **Process Management:** Each wallpaper change spawns a new process
3. **GIF Inefficiency:** Frequent restarts for animation are resource-intensive
4. **Multiple Instances:** Running multiple instances for multi-monitor can accumulate orphaned processes if not cleaned up properly

wallshow addresses #4 by tracking PIDs and ensuring cleanup.

## Installation

```bash
# Arch Linux
pacman -S swaybg

# Debian/Ubuntu
apt install swaybg

# Fedora
dnf install swaybg

# From source
git clone https://github.com/swaywm/swaybg.git
cd swaybg
meson build
ninja -C build
sudo ninja -C build install
```

**Dependencies:**
- wlroots-based Wayland compositor
- cairo (image rendering)
- gdk-pixbuf2 (image loading)

## Official Documentation

- **GitHub Repository:** [swaywm/swaybg](https://github.com/swaywm/swaybg)
- **Man Page:** [swaybg(1)](https://www.mankier.com/1/swaybg)
- **sway Wiki:** [Sway - ArchWiki](https://wiki.archlinux.org/title/Sway)

## Example Usage

```bash
# Simple wallpaper
swaybg -i ~/wallpapers/nature.jpg -m fill

# Tiled pattern
swaybg -i ~/patterns/texture.png -m tile

# Dual monitors
swaybg -o DP-1 -i ~/wallpapers/left.jpg -m fill &
swaybg -o HDMI-A-1 -i ~/wallpapers/right.jpg -m fill &

# Solid color background
swaybg -c 1e1e2e -m solid_color

# With wallshow (automatic fallback if swww unavailable)
wallshow start
```

## Comparison with Other Tools

**vs swww:** swaybg is simpler and more lightweight, but lacks GIF support and transitions
**vs hyprpaper:** swaybg has better mode options (fit, stretch, etc.); hyprpaper has better memory management
**vs wpaperd:** swaybg requires manual control; wpaperd is a full daemon with timed rotation

## Best For

- Simple static wallpapers on Wayland
- Minimal resource usage
- Users who don't need animations or transitions
- Fallback option when feature-rich tools aren't available
