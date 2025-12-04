# feh

## Overview

**feh** is a fast, lightweight image viewer for X11 that includes robust wallpaper setting capabilities.

- **Display Server:** X11 only
- **Stability:** Very mature, stable (20+ years of development)
- **Performance:** Fast, minimal resource usage

## GIF Support

❌ **Static Images Only**

feh does not support animated GIFs for wallpapers. For animated wallpapers:
- **Workaround:** Extract GIF frames and rapidly call `feh --bg-*` with new frames
- **wallshow approach:** Automatic frame extraction and cycling when feh is used

## CLI Reference

### Wallpaper Background Modes

feh uses `--bg-*` options to set wallpapers:

```bash
feh --bg-fill /path/to/wallpaper.jpg
```

### Available Background Modes

- **`--bg-fill`** - Fill screen, preserving aspect ratio (may crop) - **RECOMMENDED**
- **`--bg-scale`** - Scale image to fit screen exactly (may distort)
- **`--bg-center`** - Center image at original size
- **`--bg-tile`** - Tile image across screen
- **`--bg-max`** - Show at maximum size that fits on screen

```bash
# Most common mode - fill screen, preserve aspect
feh --bg-fill wallpaper.jpg

# Scale to exact screen size (distorts)
feh --bg-scale wallpaper.jpg

# Center without scaling
feh --bg-center wallpaper.jpg

# Tile pattern
feh --bg-tile texture.png

# Maximum size without cropping
feh --bg-max wallpaper.jpg
```

### Multi-Monitor Support

Pass multiple files for multi-monitor setups:

```bash
# Dual monitors
feh --bg-fill left.jpg right.jpg

# Triple monitors
feh --bg-fill monitor1.jpg monitor2.jpg monitor3.jpg
```

**Order:** Files are applied to monitors in X11 screen order.

### Random Wallpaper

```bash
# Random wallpaper from directory
feh --bg-fill --randomize ~/wallpapers/*

# or
feh --bg-fill --randomize ~/wallpapers/*.jpg
```

### ~/.fehbg Script

feh automatically creates `~/.fehbg`, a script to restore the last wallpaper:

```bash
# Restore last wallpaper
~/.fehbg

# Add to startup (.xinitrc, .xsession, etc.)
echo "~/.fehbg &" >> ~/.xinitrc
```

**Disable script creation:**
```bash
feh --no-fehbg --bg-fill wallpaper.jpg
```

### Complete Wallpaper Syntax

```bash
feh [--bg-MODE] [--no-fehbg] [--randomize] IMAGE_FILE(S)
```

## Wallshow Integration

### Current Implementation

feh is the **primary X11 wallpaper backend**.

**Location:** `lib/wallpaper/backends.sh:set_wallpaper_feh()`

**Implementation Details:**
1. Uses `--bg-fill` mode by default (best aspect ratio preservation)
2. Captures stderr to temp file for error logging
3. For GIFs: rapid `feh --bg-fill` calls with extracted frames

### Configuration

```json
{
  "tools": {
    "preferred_static": "feh"
  }
}
```

### Known Issues/Limitations

1. **No Transitions:** Instant wallpaper change
2. **~/.fehbg Created:** Automatic script generation (can disable with `--no-fehbg`)
3. **GIF Inefficiency:** Repeated feh calls for animation overhead
4. **X11 Only:** Won't work on Wayland

## Installation

```bash
# Arch Linux
pacman -S feh

# Debian/Ubuntu
apt install feh

# Fedora
dnf install feh

# From source
git clone https://github.com/derf/feh.git
cd feh
make
sudo make install
```

**Dependencies:**
- X11 libraries
- imlib2 (image loading)

## Official Documentation

- **Official Website:** [feh.finalrewind.org](https://feh.finalrewind.org/)
- **Man Page:** [feh(1)](https://man.archlinux.org/man/feh.1.en)
- **ArchWiki:** [feh - ArchWiki](https://wiki.archlinux.org/title/Feh)

## Example Usage

### Basic Wallpaper Setting

```bash
# Set wallpaper (fill mode)
feh --bg-fill ~/wallpapers/mountain.jpg

# Different modes
feh --bg-center ~/wallpapers/logo.png
feh --bg-tile ~/patterns/texture.png
feh --bg-scale ~/wallpapers/photo.jpg
```

### Multi-Monitor

```bash
# Dual monitors (different wallpapers)
feh --bg-fill left.jpg right.jpg

# Dual monitors (same wallpaper)
feh --bg-fill wallpaper.jpg wallpaper.jpg
```

### Random Wallpaper

```bash
# Random from directory
feh --bg-fill --randomize ~/wallpapers/*
```

### Restore on Startup

Add to `~/.xinitrc` or window manager config:
```bash
~/.fehbg &
```

### With wallshow

```bash
# wallshow automatically uses feh on X11
wallshow start
```

## Comparison with Other Tools

**vs nitrogen:** feh is CLI-focused, faster; nitrogen has GUI browser
**vs xwallpaper:** feh has more modes and features; xwallpaper is simpler
**vs hsetroot:** feh supports more image formats; hsetroot is more basic

## Best For

- X11 users wanting reliable wallpaper setting
- CLI-based wallpaper management
- Multi-monitor setups
- Users familiar with feh as image viewer
- Integration with window manager configs

## Not Suitable For

- Animated GIFs (use frame extraction workaround)
- Wayland (X11 only)
- Users who want GUI wallpaper picker (use nitrogen instead)

## feh as Image Viewer

Beyond wallpaper setting, feh is a powerful image viewer:

```bash
# View images
feh image1.jpg image2.jpg

# Slideshow
feh --slideshow-delay 5 ~/photos/*

# Fullscreen
feh --fullscreen image.jpg

# Thumbnail mode
feh --thumbnails ~/photos/
```

See `man feh` for complete viewing options.

## Integration Notes for wallshow

**Current Status:** ✅ Already integrated and working

**CLI Usage in wallshow:**
```bash
feh --bg-fill "${image}"
```

**For GIF frames:**
```bash
# Called repeatedly with each frame
feh --bg-fill "${frame_001.png}"
feh --bg-fill "${frame_002.png}"
# ...
```

**Error Handling:** wallshow captures stderr to detect failures:
```bash
feh --bg-fill "${image}" 2>"${error_file}"
if [ $? -ne 0 ]; then
    # Log error
fi
```

**No special handling needed** - feh's `--bg-fill` is simple and reliable.
