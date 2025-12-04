# xwallpaper

## Overview

**xwallpaper** is a simple, lightweight wallpaper setting utility for X11, focusing on correctness and simplicity.

- **Display Server:** X11 only
- **Stability:** Stable, minimal codebase
- **Performance:** Fast, low overhead

## GIF Support

❌ **Static Images Only**

xwallpaper does not support animated GIFs. For animations:
- **Workaround:** Extract frames and call xwallpaper repeatedly
- **wallshow approach:** Automatic frame cycling when xwallpaper is used

## CLI Reference

### Basic Syntax

```bash
xwallpaper --MODE /path/to/wallpaper.jpg
```

### Scaling/Positioning Modes

**--zoom** (default) - Zoom to fill screen, crop if needed (preserves aspect):
```bash
xwallpaper --zoom wallpaper.jpg
```

**--maximize** - Fit entire image on screen (may have black bars):
```bash
xwallpaper --maximize wallpaper.jpg
```

**--center** - Center at original size:
```bash
xwallpaper --center wallpaper.jpg
```

**--tile** - Repeat image in tiled pattern:
```bash
xwallpaper --tile texture.png
```

**--stretch** - Fill screen, ignoring aspect ratio (distorts):
```bash
xwallpaper --stretch wallpaper.jpg
```

### Detailed Mode Behavior

**Zoom vs Maximize:**
- `--zoom`: Fills screen completely, may crop edges to preserve aspect ratio
- `--maximize`: Shows entire image, adds black borders if aspect doesn't match

**Focus Option (with --zoom):**
```bash
# Not directly supported; use --zoom for basic zoom-to-fill
xwallpaper --zoom wallpaper.jpg
```

### Per-Output Control

Specify screen for multi-monitor:

```bash
# Set wallpaper for specific output
xwallpaper --output DP-1 --zoom wallpaper.jpg

# Different wallpapers per screen
xwallpaper --output DP-1 --zoom left.jpg \
           --output HDMI-A-1 --zoom right.jpg
```

### Options

- `--zoom <file>` - Zoom to fill screen (default)
- `--maximize <file>` - Fit entire image (preserve aspect)
- `--center <file>` - Center at original size
- `--tile <file>` - Tile image
- `--stretch <file>` - Stretch to fill (distort)
- `--output <name>` - Select output/screen
- `--daemon` - Run in background, wait for output changes
- `--version` - Show version
- `--help` - Show help

### Daemon Mode

Run xwallpaper as daemon to handle monitor hotplugging:

```bash
xwallpaper --daemon --zoom wallpaper.jpg
```

The daemon will reapply wallpaper when monitors are connected/disconnected.

## Wallshow Integration

### Current Implementation

xwallpaper is the **fallback X11 backend** when feh is unavailable.

**Location:** `lib/wallpaper/backends.sh:set_wallpaper_xwallpaper()`

**Implementation Details:**
1. Uses `--zoom` mode by default (fill screen, preserve aspect)
2. Captures stderr for error logging
3. For GIFs: repeated calls with extracted frames

### Configuration

```json
{
  "tools": {
    "preferred_static": "xwallpaper"
  }
}
```

### Known Issues/Limitations

1. **No Transitions:** Instant wallpaper change
2. **X11 Only:** Won't work on Wayland
3. **Limited Modes:** Fewer scaling options than feh
4. **GIF Animation:** Requires external frame extraction

## Installation

```bash
# Arch Linux
pacman -S xwallpaper

# Debian/Ubuntu
apt install xwallpaper

# Fedora
dnf install xwallpaper

# From source
git clone https://github.com/stoeckmann/xwallpaper.git
cd xwallpaper
./autogen.sh
./configure
make
sudo make install
```

**Dependencies:**
- X11 libraries (libX11, libXpm)
- pixman
- xcb libraries

## Official Documentation

- **GitHub Repository:** [stoeckmann/xwallpaper](https://github.com/stoeckmann/xwallpaper)
- **Man Page:** [xwallpaper(1)](https://man.archlinux.org/man/xwallpaper.1.en)

## Example Usage

### Basic Wallpaper Setting

```bash
# Zoom to fill (default)
xwallpaper --zoom ~/wallpapers/mountain.jpg

# Fit entire image (may have black bars)
xwallpaper --maximize ~/wallpapers/photo.jpg

# Center without scaling
xwallpaper --center ~/wallpapers/logo.png

# Tile pattern
xwallpaper --tile ~/patterns/texture.png

# Stretch (distort to fill)
xwallpaper --stretch ~/wallpapers/abstract.jpg
```

### Multi-Monitor

```bash
# Different wallpapers per monitor
xwallpaper --output DP-1 --zoom left.jpg \
           --output HDMI-A-1 --zoom right.jpg

# Same wallpaper on all screens
xwallpaper --zoom wallpaper.jpg
```

### Daemon Mode

```bash
# Run as daemon (reapply on monitor changes)
xwallpaper --daemon --zoom ~/wallpapers/default.jpg &

# Add to .xinitrc or window manager config
echo "xwallpaper --daemon --zoom ~/wallpapers/default.jpg &" >> ~/.xinitrc
```

### With wallshow

```bash
# wallshow automatically uses xwallpaper as X11 fallback
wallshow start
```

## Comparison with Other Tools

**vs feh:** xwallpaper is simpler with fewer features; feh has more modes and `~/.fehbg` script
**vs nitrogen:** xwallpaper is CLI-only; nitrogen has GUI browser
**vs hsetroot:** xwallpaper handles images better; hsetroot focuses on colors/gradients

## Best For

- Simple X11 wallpaper setting
- Users who prefer minimal tools
- Window manager configs (i3, bspwm, etc.)
- Daemon mode for monitor hotplugging

## Not Suitable For

- Animated GIFs (static only)
- Wayland (X11 only)
- Advanced scaling/positioning needs (limited modes)

## Differences from feh

| Feature | xwallpaper | feh |
|---------|-----------|-----|
| Modes | 5 (zoom, maximize, center, tile, stretch) | 5 (fill, scale, center, tile, max) |
| Daemon | Yes (`--daemon`) | No |
| Script generation | No | Yes (`~/.fehbg`) |
| Randomize | No (manual scripting) | Yes (`--randomize`) |
| Image viewer | No | Yes (full-featured) |

## Integration Notes for wallshow

**Current Status:** ✅ Already integrated as X11 fallback

**CLI Usage in wallshow:**
```bash
xwallpaper --zoom "${image}"
```

**For GIF frames:**
```bash
# Called repeatedly with each frame
xwallpaper --zoom "${frame_001.png}"
xwallpaper --zoom "${frame_002.png}"
# ...
```

**Error Handling:** wallshow captures stderr to detect failures:
```bash
xwallpaper --zoom "${image}" 2>"${error_file}"
if [ $? -ne 0 ]; then
    # Log error and try next tool
fi
```

**Fallback Chain:** On X11, wallshow tries:
1. feh (if available)
2. xwallpaper (fallback)

**No special handling needed** - xwallpaper's `--zoom` is straightforward and reliable.
