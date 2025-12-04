# mpvpaper

## Overview

**mpvpaper** is a video wallpaper program for wlroots-based Wayland compositors that uses mpv to play videos, GIFs, and images as wallpapers.

- **Display Server:** Wayland only (wlroots-based compositors)
- **Stability:** Stable, actively maintained
- **Performance:** Hardware-accelerated via mpv, frame callback optimization

## GIF Support

✅ **Native Video and GIF Playback**

mpvpaper leverages mpv's full codec support for native animated wallpaper playback:
- **GIF animations** - Full frame rate, no extraction needed
- **Video files** - MP4, MKV, WebM, etc.
- **Image sequences** - For complex animations
- **Static images** - Also supported via mpv

**Performance:** Excellent for both GIFs and videos. Uses Wayland's frame callback feature to render only when needed, conserving resources.

## CLI Reference

### Basic Syntax

```bash
mpvpaper [options] <output> <media_file>
```

**Arguments:**
- `<output>` - Monitor name (e.g., `DP-1`, `HDMI-A-1`) or `*` for all monitors
- `<media_file>` - Path to video, GIF, or image file

### Basic Commands

Play video on specific monitor:
```bash
mpvpaper DP-1 /path/to/video.mp4
```

Play GIF on all monitors:
```bash
mpvpaper '*' /path/to/animated.gif
```

Static image:
```bash
mpvpaper DP-1 /path/to/wallpaper.jpg
```

### Options

**Daemon & Background:**
```bash
# Fork to background
mpvpaper -f DP-1 video.mp4

# Don't fork (foreground)
mpvpaper --no-fork DP-1 video.mp4
```

**Pause & Loop:**
```bash
# Start paused
mpvpaper -p DP-1 video.mp4

# No loop (play once)
mpvpaper --no-loop DP-1 video.mp4

# Loop (default behavior)
mpvpaper DP-1 video.mp4
```

**Scaling & Fitting:**
```bash
# Stop slideshow mode
mpvpaper --slideshow 0 DP-1 image.jpg

# Panscan (adjust cropping)
mpvpaper --panscan 0.5 DP-1 video.mp4

# Layer (z-index: overlay, top, bottom, background)
mpvpaper --layer bottom DP-1 video.mp4
```

**mpv Options:**
```bash
# Pass options directly to mpv
mpvpaper -o "loop-file=inf --speed=0.5" DP-1 video.mp4
mpvpaper -o "mute=yes --brightness=10" DP-1 video.mp4
```

### IPC Control

Use mpv's IPC socket for runtime control:

```bash
# Enable IPC socket
mpvpaper -o "input-ipc-server=/tmp/mpvpaper.sock" DP-1 video.mp4

# Control via socat/echo
echo '{"command": ["set_property", "pause", true]}' | \
    socat - /tmp/mpvpaper.sock

# Seek to position
echo '{"command": ["seek", "30", "absolute"]}' | \
    socat - /tmp/mpvpaper.sock
```

### Complete Options Reference

- `-f, --fork` - Fork to background
- `-p, --pause` - Start paused
- `-n <name>, --name <name>` - Set output name
- `-l <layer>, --layer <layer>` - Set layer shell layer (overlay, top, bottom, background)
- `-o <opts>, --mpv-options <opts>` - Pass options to mpv
- `--panscan <float>` - Panscan value
- `--slideshow <seconds>` - Slideshow interval for image directories
- `--no-loop` - Don't loop video
- `--no-audio` - Disable audio
- `--no-config` - Don't load mpv config
- `-h, --help` - Show help
- `-v, --verbose` - Verbose logging

## Wallshow Integration

### Planned Implementation

mpvpaper will be added as the **preferred animated wallpaper backend** for Wayland when native GIF support is desired.

**Location:** `lib/wallpaper/backends.sh:set_wallpaper_mpvpaper()` (NEW)

**Proposed Implementation:**
```bash
set_wallpaper_mpvpaper() {
    local image="$1"
    local is_animated="${2:-false}"

    # Kill previous mpvpaper instances
    pkill -f "mpvpaper.*${PREVIOUS_WALLPAPER}" 2>/dev/null || true
    sleep 0.1

    # Detect all outputs or use primary
    local output="*"

    # For static images, don't loop
    local loop_opt=""
    if [[ "${is_animated}" != "true" ]]; then
        loop_opt="--no-loop"
    fi

    # Start mpvpaper in background
    mpvpaper --fork ${loop_opt} --layer background \
        -o "no-audio --loop-file=inf" \
        "${output}" "${image}" &

    local mpv_pid=$!
    update_state_atomic ".processes.mpvpaper_pid = ${mpv_pid}"

    log_debug "Set wallpaper with mpvpaper: ${image} (PID: ${mpv_pid})"
    return 0
}
```

### Configuration

```json
{
  "tools": {
    "preferred_animated": "mpvpaper"
  }
}
```

wallshow should prefer mpvpaper for GIFs and videos when native playback is desired.

### Known Issues/Limitations

1. **Audio Disabled:** mpvpaper typically runs with `--no-audio` for wallpapers
2. **Process Management:** Must track PIDs to kill previous instances
3. **Output Detection:** May need logic to determine correct monitor names
4. **Static Images:** Less efficient than hyprpaper/swaybg for static wallpapers
5. **CPU Usage:** Higher than swww for GIFs (video decoding overhead)

## Installation

```bash
# Arch Linux
pacman -S mpvpaper

# Debian/Ubuntu (build from source)
# Install dependencies first
apt install libmpv-dev libwayland-dev

# Fedora
dnf install mpvpaper

# From source
git clone https://github.com/GhostNaN/mpvpaper.git
cd mpvpaper
meson build
ninja -C build
sudo ninja -C build install
```

**Dependencies:**
- mpv (>= 0.27.0)
- wlroots-based compositor
- wayland client libraries

## Official Documentation

- **GitHub Repository:** [GhostNaN/mpvpaper](https://github.com/GhostNaN/mpvpaper)
- **Man Page:** [mpvpaper.man](https://github.com/GhostNaN/mpvpaper/blob/master/mpvpaper.man)
- **mpv Documentation:** [mpv.io](https://mpv.io)

## Example Usage

```bash
# Play animated GIF as wallpaper
mpvpaper --fork '*' ~/wallpapers/animated.gif

# Play video on specific monitor
mpvpaper --fork DP-1 ~/videos/nature.mp4

# Static image (with mpv)
mpvpaper --fork --no-loop '*' ~/wallpapers/photo.jpg

# With custom mpv options
mpvpaper --fork \
    -o "loop-file=inf --brightness=20 --contrast=10" \
    '*' video.mp4

# Muted video
mpvpaper --fork --no-audio '*' video.mp4

# Pause and resume via IPC
mpvpaper --fork -o "input-ipc-server=/tmp/mpv.sock" '*' video.mp4
# (then control via socat)

# Directory slideshow
mpvpaper --slideshow 300 '*' ~/wallpapers/
```

## Comparison with Other Tools

**vs swww:** mpvpaper supports full videos; swww is more efficient for GIFs alone
**vs hyprpaper:** mpvpaper has native video/GIF; hyprpaper is faster for static images
**vs swaybg:** mpvpaper handles animations; swaybg is lightweight static-only

## Best For

- Video wallpapers (MP4, WebM, MKV)
- Animated GIFs with complex frame sequences
- Users who want mpv's full codec support
- Artistic/animated backgrounds on Wayland
- Users comfortable with mpv options

## Integration Notes for wallshow

**When to use mpvpaper:**
- User explicitly requests video wallpaper support
- GIF file detected and native playback preferred
- swww unavailable but GIF animation desired

**When NOT to use mpvpaper:**
- Static wallpapers only (use hyprpaper/swaybg instead)
- Battery optimization enabled (frame extraction cheaper than video decode)
- swww available (swww more efficient for GIFs specifically)
