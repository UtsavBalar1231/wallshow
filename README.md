# Wallshow

> Professional wallpaper manager for Wayland/X11 with GIF animation support

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-1.0.0-green.svg)](https://github.com/UtsavBalar1231/wallshow/releases)

## Features

- **Daemon Mode**: Automated wallpaper rotation with configurable intervals
- **Animated Wallpapers**: Native GIF support with frame extraction and playback
- **Battery Optimization**: Automatically disables animations when on battery power
- **Multi-Backend Support**: Works with swww, swaybg, feh, xwallpaper, and more
- **IPC Control**: Unix socket-based daemon control (next, pause, resume, stop)
- **XDG Compliant**: Follows XDG Base Directory specification for config/state/cache
- **Smart Caching**: Intelligent wallpaper discovery with timestamp-based caching
- **Modular Architecture**: Clean, maintainable codebase with feature-based organization

## Requirements

### Required Dependencies

- **bash** ≥ 5.0
- **jq** - JSON processing
- **socat** - IPC socket communication

### Optional Dependencies

- **ImageMagick** (`convert` or `magick`) - Required for GIF animation support

### Wallpaper Backends (at least one required)

**Wayland:**
- `swww` - Animated wallpaper support (recommended)
- `swaybg` - Lightweight static wallpaper daemon

**X11:**
- `feh` - Feature-rich wallpaper setter
- `xwallpaper` - Minimalist alternative

## Installation

### Arch Linux (AUR)

```bash
yay -S wallshow
# or: paru -S wallshow
```

### Other Distributions

Download packages from [releases](https://github.com/UtsavBalar1231/wallshow/releases) (Debian/Ubuntu `.deb`, Fedora/RHEL `.rpm`).

### From Source

```bash
git clone https://github.com/UtsavBalar1231/wallshow.git
cd wallshow
just install  # Installs to ~/.local (includes systemd service)

# Ensure ~/.local/bin is in PATH
export PATH="$HOME/.local/bin:$PATH"
```

## Quick Start

```bash
# Start the daemon (auto-rotates wallpapers)
wallshow start

# Change wallpaper immediately
wallshow next

# Check status
wallshow status

# Pause rotation (keeps current wallpaper)
wallshow pause

# Resume rotation
wallshow resume

# Stop the daemon
wallshow stop
```

## Configuration

Configuration file: `~/.config/wallshow/config.json` (auto-created on first run)

### Key Settings

```json
{
  "wallpaper_dirs": {
    "static": "~/Pictures/wallpapers",
    "animated": "~/Pictures/wallpapers/animated"
  },
  "intervals": {
    "change_seconds": 300
  },
  "behavior": {
    "battery_optimization": true,
    "debug": false
  }
}
```

**Common options:**
- `wallpaper_dirs.static/animated` - Wallpaper directories
- `intervals.change_seconds` - Time between changes (default: 300s)
- `behavior.battery_optimization` - Disable GIFs on battery (default: true)
- `tools.preferred_static/animated` - Backend preference (default: "auto")

Reload config: `wallshow reload`

## Commands

```bash
# Daemon
wallshow start/stop/restart    # Manage daemon
wallshow daemon                # Run in foreground (debug mode)

# Control
wallshow next                  # Change wallpaper immediately
wallshow pause/resume          # Pause/resume rotation

# Info
wallshow status                # Current status (JSON)
wallshow info                  # System information
wallshow list                  # Available wallpapers

# Maintenance
wallshow reload                # Reload configuration
wallshow clean                 # Clean GIF cache
```

## File Locations

Wallshow follows the XDG Base Directory specification:

| Type | Path | Purpose |
|------|------|---------|
| **Config** | `~/.config/wallshow/config.json` | User configuration |
| **State** | `~/.local/state/wallshow/state.json` | Runtime state (current wallpaper, history, stats) |
| **Cache** | `~/.cache/wallshow/` | GIF frames, wallpaper lists |
| **Logs** | `~/.local/state/wallshow/wallpaper.log` | Application logs |
| **Runtime** | `/run/user/$(id -u)/wallshow/` | PID file, socket, instance lock |

## Common Questions

### "command not found: wallshow"
Ensure `~/.local/bin` is in PATH: `export PATH="$HOME/.local/bin:$PATH"`

### "Instance already locked"
```bash
pgrep -f wallshow  # Check if running
rm /run/user/$(id -u)/wallshow/instance.lock  # Remove stale lock if not running
```

### How to enable GIF support?
Install ImageMagick (`sudo pacman -S imagemagick` on Arch, `sudo apt install imagemagick` on Debian), then place GIFs in `~/Pictures/wallpapers/animated`.

### Wallpaper not changing?
1. Check status: `wallshow status`
2. Verify wallpaper directory exists and has images
3. Check logs: `tail -f ~/.local/state/wallshow/wallpaper.log`

### Auto-start on login?
```bash
systemctl --user enable --now wallshow.service
```
(Systemd service installed automatically with packages and `just install`)

## Development

```bash
git clone https://github.com/UtsavBalar1231/wallshow.git && cd wallshow
just run help      # Run from source
just build-all     # Build packages
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for detailed guidelines.

## Contributing

Contributions welcome! See [CONTRIBUTING.md](CONTRIBUTING.md) for details.
- [Report bugs](https://github.com/UtsavBalar1231/wallshow/issues)
- [Request features](https://github.com/UtsavBalar1231/wallshow/discussions)

## License

[MIT License](LICENSE) - Copyright (c) 2025 UtsavBalar1231

## Acknowledgments

- Inspired by the need for a simple, scriptable wallpaper manager
- Built with modern Bash best practices and XDG compliance
- Thanks to the Wayland and X11 communities for excellent wallpaper backends
