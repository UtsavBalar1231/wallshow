# Wallpaper Utilities Reference

Comprehensive documentation for Linux CLI wallpaper utilities supported or considered for wallshow.

## Quick Comparison Table

| Tool | Display Server | GIF Support | CLI Quality | Multi-Monitor | Transitions | wallshow Status |
|------|----------------|-------------|-------------|---------------|-------------|-----------------|
| [swww](wayland/swww.md) | Wayland | ✅ Native | Excellent | ✅ | ✅ | ✅ Supported |
| [mpvpaper](wayland/mpvpaper.md) | Wayland | ✅ Native (Video) | Good | ✅ | ❌ | 🆕 NEW |
| [hyprpaper](wayland/hyprpaper.md) | Wayland | ❌ Static | Good (IPC) | ✅ | ❌ | 🆕 NEW |
| [wpaperd](wayland/wpaperd.md) | Wayland | ❌ Static | Good (daemon) | ✅ | ✅ | 🆕 NEW (low priority) |
| [swaybg](wayland/swaybg.md) | Wayland | ❌ Static | Basic | ✅ | ❌ | ✅ Supported |
| [wallutils](cross-platform/wallutils.md) | Both | ⚠️ Timed | Good | ✅ | ❌ | 🆕 NEW (fallback) |
| [feh](x11/feh.md) | X11 | ❌ Static | Good | ✅ | ❌ | ✅ Supported |
| [xwallpaper](x11/xwallpaper.md) | X11 | ❌ Static | Good | ✅ | ❌ | ✅ Supported |

## GIF Support Categories

### ✅ Native GIF/Video Support
Tools that natively play animated content without frame extraction:

- **[swww](wayland/swww.md)** - Best for animated GIFs on Wayland, hardware-accelerated, efficient caching
- **[mpvpaper](wayland/mpvpaper.md)** - Best for videos and complex animations, full mpv codec support

**Recommendation:** Use these for animated wallpapers when available.

### ❌ Static Only (Frame Extraction Required)
Tools that require external frame extraction (ImageMagick) for GIF playback:

- **[swaybg](wayland/swaybg.md)** - Can be rapidly restarted with frames
- **[hyprpaper](wayland/hyprpaper.md)** - Can preload/set frames in sequence
- **[feh](x11/feh.md)** - Can be scripted to change frames
- **[xwallpaper](x11/xwallpaper.md)** - Can be called repeatedly with frames
- **[wpaperd](wayland/wpaperd.md)** - Can rotate through extracted frames

**Recommendation:** wallshow automatically handles frame extraction for these tools.

### ⚠️ Timed Wallpapers (No GIF)
Tools designed for time-based rotation of static images:

- **[wallutils](cross-platform/wallutils.md)** - Time-of-day based wallpaper changes

**Recommendation:** Use for time-based rotation, not GIF animation.

## Display Server Support

### Wayland Tools

| Tool | Compositors | Notes |
|------|-------------|-------|
| [swww](wayland/swww.md) | wlroots (sway, Hyprland, river, etc.) | Animated GIF daemon |
| [swaybg](wayland/swaybg.md) | wlroots | Simple static backgrounds |
| [hyprpaper](wayland/hyprpaper.md) | wlroots (optimized for Hyprland) | Fast static with IPC |
| [mpvpaper](wayland/mpvpaper.md) | wlroots | Video/GIF via mpv |
| [wpaperd](wayland/wpaperd.md) | wlroots, KDE | Daemon with timed rotation |

### X11 Tools

| Tool | Notes |
|------|-------|
| [feh](x11/feh.md) | Mature, feature-rich, creates ~/.fehbg script |
| [xwallpaper](x11/xwallpaper.md) | Simple, daemon mode for hotplug |

### Cross-Platform

| Tool | Notes |
|------|-------|
| [wallutils](cross-platform/wallutils.md) | Auto-detects environment, calls underlying tools |

## wallshow Integration Status

### ✅ Currently Supported

- **[swww](wayland/swww.md)** - Primary Wayland backend with native GIF support
- **[swaybg](wayland/swaybg.md)** - Wayland fallback for static wallpapers
- **[feh](x11/feh.md)** - Primary X11 backend
- **[xwallpaper](x11/xwallpaper.md)** - X11 fallback

### 🆕 To Be Added

- **[hyprpaper](wayland/hyprpaper.md)** - High-priority Wayland static backend
- **[mpvpaper](wayland/mpvpaper.md)** - Native video/GIF playback for Wayland
- **[wpaperd](wayland/wpaperd.md)** - Low priority (daemon conflicts with wallshow)
- **[wallutils](cross-platform/wallutils.md)** - Universal fallback (lowest priority)

## Recommended Fallback Chains

### Wayland (Static Wallpapers)
```
swww → hyprpaper → swaybg → wallutils
```

### Wayland (Animated GIFs)
```
swww → mpvpaper → [frame extraction with static tools]
```

### X11
```
feh → xwallpaper → wallutils
```

## Quick CLI Reference

### Set Wallpaper Examples

```bash
# swww (Wayland, animated GIF)
swww-daemon &
swww img animated.gif --transition-type fade

# swaybg (Wayland, static)
swaybg -i wallpaper.jpg -m fill &

# hyprpaper (Wayland, static, IPC)
hyprctl hyprpaper reload ",wallpaper.jpg"

# mpvpaper (Wayland, video/GIF)
mpvpaper --fork '*' video.mp4

# feh (X11, static)
feh --bg-fill wallpaper.jpg

# xwallpaper (X11, static)
xwallpaper --zoom wallpaper.jpg

# wallutils (cross-platform)
setwallpaper wallpaper.jpg
```

## Documentation Index

### Wayland
- **[swww.md](wayland/swww.md)** - Animated wallpaper daemon with native GIF support
- **[swaybg.md](wayland/swaybg.md)** - Simple static background utility
- **[hyprpaper.md](wayland/hyprpaper.md)** - Fast wallpaper with IPC controls
- **[mpvpaper.md](wayland/mpvpaper.md)** - Video/GIF wallpaper via mpv
- **[wpaperd.md](wayland/wpaperd.md)** - Modern daemon with timed rotation

### X11
- **[feh.md](x11/feh.md)** - Mature image viewer with wallpaper setting
- **[xwallpaper.md](x11/xwallpaper.md)** - Simple wallpaper utility with daemon mode

### Cross-Platform
- **[wallutils.md](cross-platform/wallutils.md)** - Collection of utilities for monitors and timed wallpapers

## Performance Comparison

### Animated GIF Playback

| Method | CPU Usage | Memory Usage | Smoothness | Tools |
|--------|-----------|--------------|------------|-------|
| Native (swww) | Low | Medium | Excellent | swww |
| Native (mpv) | Medium | Medium-High | Excellent | mpvpaper |
| Frame extraction | High | High | Good | swaybg, feh, others |

**Recommendation:** Use swww or mpvpaper for GIFs when available. Frame extraction is resource-intensive.

### Static Wallpaper Setting

| Tool | Speed | Resource Usage | Best For |
|------|-------|----------------|----------|
| hyprpaper | Very Fast | Low (preload/unload) | Hyprland users |
| swaybg | Fast | Low | wlroots compositors |
| feh | Fast | Low | X11 |
| xwallpaper | Fast | Low | X11 |
| swww | Fast | Medium (daemon) | Wayland + transitions |

## Installation Quick Reference

### Arch Linux
```bash
pacman -S swww swaybg hyprpaper mpvpaper wpaperd feh xwallpaper wallutils
```

### Debian/Ubuntu
```bash
# Most tools require building from source or external repos
apt install feh swaybg xwallpaper  # Available in repos
# Others: build from source (see individual docs)
```

### Fedora
```bash
dnf install feh swww swaybg wpaperd wallutils
# hyprpaper, mpvpaper: COPR or source
```

## Feature Matrix

| Feature | swww | mpvpaper | hyprpaper | wpaperd | swaybg | wallutils | feh | xwallpaper |
|---------|------|----------|-----------|---------|--------|-----------|-----|------------|
| Animated GIF | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| Video playback | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| Transitions | ✅ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ |
| Multi-monitor | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Daemon mode | ✅ | ✅ | ✅ | ✅ | ❌* | ⚠️ | ❌ | ⚠️ |
| IPC control | ❌ | ⚠️ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ |
| Timed rotation | ❌ | ❌ | ❌ | ✅ | ❌ | ✅ | ❌ | ❌ |
| CLI simplicity | Good | Good | Medium (IPC) | Complex (config) | Excellent | Excellent | Excellent | Excellent |

*swaybg runs in background but isn't a daemon (each invocation is separate process)
⚠️xwallpaper has `--daemon` for hotplug, wallutils has lstimed daemon

## Common Use Cases

### "I want smooth animated GIF wallpapers"
**Wayland:** Use [swww](wayland/swww.md) (best) or [mpvpaper](wayland/mpvpaper.md)
**X11:** Use wallshow's frame extraction with [feh](x11/feh.md)

### "I want fast static wallpaper switching"
**Wayland:** Use [hyprpaper](wayland/hyprpaper.md) (Hyprland) or [swaybg](wayland/swaybg.md)
**X11:** Use [feh](x11/feh.md)

### "I want automatic wallpaper rotation"
**Timed (time of day):** Use [wallutils](cross-platform/wallutils.md) lstimed
**Interval-based:** Use wallshow (this project)

### "I want video wallpapers"
**Wayland:** Use [mpvpaper](wayland/mpvpaper.md)
**X11:** Not supported (use frame extraction or Wayland)

### "I want cross-platform wallpaper scripts"
Use [wallutils](cross-platform/wallutils.md) setwallpaper

## Troubleshooting

### Wallpaper not showing
1. Check if display server is X11 or Wayland: `echo $XDG_SESSION_TYPE`
2. Verify tool is installed: `which swww` / `which feh`
3. Check compositor compatibility (some tools are wlroots-only)
4. Look for errors in wallshow logs: `~/.local/state/wallshow/wallpaper.log`

### GIF animation not playing
1. Verify tool has native GIF support (swww or mpvpaper)
2. Check if wallshow is using frame extraction (look for ImageMagick in logs)
3. Ensure GIF file is valid: `file animated.gif`

### Multiple wallpaper processes
1. Kill orphaned processes: `pkill swaybg` / `pkill swww`
2. wallshow tracks PIDs - check state: `jq '.processes' ~/.local/state/wallshow/state.json`

## Contributing

Found an issue or want to add documentation for another wallpaper utility?

1. Follow the documentation template used in existing files
2. Include all CLI options with examples
3. Specify GIF support clearly
4. Add wallshow integration notes
5. Submit PR to wallshow repository

## Sources

All documentation is based on official sources:
- Official repositories and man pages
- ArchWiki and official wikis
- Project documentation (as of November 2025)

See individual utility docs for specific source links.
