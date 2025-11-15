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
# Using yay
yay -S wallshow

# Or using paru
paru -S wallshow

# Manual installation
git clone https://aur.archlinux.org/wallshow.git
cd wallshow
makepkg -si
```

### Debian/Ubuntu

```bash
# Download the .deb package from releases
wget https://github.com/UtsavBalar1231/wallshow/releases/download/v1.0.0/wallshow_1.0.0-1_all.deb

# Install with apt
sudo apt install ./wallshow_1.0.0-1_all.deb
```

### Fedora/RHEL

```bash
# Download the RPM package from releases
wget https://github.com/UtsavBalar1231/wallshow/releases/download/v1.0.0/wallshow-1.0.0-1.noarch.rpm

# Install with dnf
sudo dnf install wallshow-1.0.0-1.noarch.rpm
```

### From Source

```bash
# Clone the repository
git clone https://github.com/UtsavBalar1231/wallshow.git
cd wallshow

# Install to ~/.local (no root required)
just install

# Or manually
mkdir -p ~/.local/bin ~/.local/lib/wallshow
cp bin/wallshow ~/.local/bin/
cp -r lib/* ~/.local/lib/wallshow/
chmod +x ~/.local/bin/wallshow

# Ensure ~/.local/bin is in your PATH
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

Wallshow automatically creates a configuration file at `~/.config/wallshow/config.json` on first run.

### Default Configuration

```json
{
  "wallpaper_dirs": {
    "static": "~/Pictures/wallpapers",
    "animated": "~/Pictures/wallpapers/animated"
  },
  "intervals": {
    "change_seconds": 300,
    "transition_ms": 300,
    "gif_frame_ms": 50
  },
  "behavior": {
    "shuffle": true,
    "exclude_patterns": ["*.tmp", ".*"],
    "battery_optimization": true,
    "max_cache_size_mb": 500,
    "max_log_size_kb": 1024,
    "debug": false
  },
  "tools": {
    "preferred_static": "auto",
    "preferred_animated": "auto",
    "fallback_chain": ["swww", "swaybg", "feh", "xwallpaper"]
  }
}
```

### Configuration Options

| Section | Option | Description | Default |
|---------|--------|-------------|---------|
| **wallpaper_dirs** | `static` | Directory for static wallpapers | `~/Pictures/wallpapers` |
| | `animated` | Directory for GIF wallpapers | `~/Pictures/wallpapers/animated` |
| **intervals** | `change_seconds` | Time between wallpaper changes | `300` (5 minutes) |
| | `transition_ms` | Fade transition duration | `300` ms |
| | `gif_frame_ms` | GIF frame delay (if not using native) | `50` ms |
| **behavior** | `shuffle` | Randomize wallpaper order | `true` |
| | `exclude_patterns` | File patterns to ignore | `["*.tmp", ".*"]` |
| | `battery_optimization` | Disable GIFs on battery | `true` |
| | `max_cache_size_mb` | GIF cache size limit | `500` MB |
| | `max_log_size_kb` | Log file size limit | `1024` KB |
| | `debug` | Enable debug logging | `false` |
| **tools** | `preferred_static` | Static wallpaper backend | `auto` |
| | `preferred_animated` | Animated wallpaper backend | `auto` |
| | `fallback_chain` | Backend priority order | `["swww", "swaybg", "feh", "xwallpaper"]` |

### Reload Configuration

```bash
# Apply config changes without restarting
wallshow reload
```

## Commands

### Daemon Management

```bash
wallshow start        # Start daemon (daemonize process)
wallshow daemon       # Run daemon in foreground (debugging)
wallshow stop         # Stop daemon gracefully
wallshow restart      # Restart daemon (stop + start)
```

### Wallpaper Control

```bash
wallshow next         # Change to next random wallpaper
wallshow pause        # Pause automatic rotation
wallshow resume       # Resume automatic rotation
```

### Information

```bash
wallshow status       # Show current status (JSON format)
wallshow info         # Show detailed system information
wallshow list         # List available wallpapers
wallshow help         # Show usage information
wallshow --version    # Show version number
```

### Maintenance

```bash
wallshow reload       # Reload configuration file
wallshow clean        # Clean old GIF cache (enforce size limits)
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

## FAQ

### How do I enable GIF support?

Install ImageMagick:

```bash
# Arch Linux
sudo pacman -S imagemagick

# Debian/Ubuntu
sudo apt install imagemagick

# Fedora
sudo dnf install ImageMagick
```

Place GIF files in your animated wallpaper directory (default: `~/Pictures/wallpapers/animated`) and restart the daemon.

### Why aren't GIFs playing on battery?

Battery optimization is enabled by default. To disable:

```bash
# Edit config.json
jq '.behavior.battery_optimization = false' ~/.config/wallshow/config.json > /tmp/config.json
mv /tmp/config.json ~/.config/wallshow/config.json

# Reload config
wallshow reload
```

### How do I change wallpaper directories?

Edit `~/.config/wallshow/config.json`:

```json
{
  "wallpaper_dirs": {
    "static": "/path/to/static/wallpapers",
    "animated": "/path/to/animated/wallpapers"
  }
}
```

Then reload: `wallshow reload`

### How do I use a specific wallpaper backend?

Set `preferred_static` or `preferred_animated` in config:

```json
{
  "tools": {
    "preferred_static": "swww",
    "preferred_animated": "swww"
  }
}
```

Available backends: `swww`, `swaybg`, `feh`, `xwallpaper`

### Wallshow won't start - "Instance already locked"

A stale lock file exists. Check if wallshow is actually running:

```bash
# Check process
pgrep -f wallshow

# If no process, remove lock manually
rm /run/user/$(id -u)/wallshow/instance.lock

# Try starting again
wallshow start
```

### Where are logs stored?

```bash
# View logs in real-time
tail -f ~/.local/state/wallshow/wallpaper.log

# Enable debug logging
jq '.behavior.debug = true' ~/.config/wallshow/config.json > /tmp/config.json
mv /tmp/config.json ~/.config/wallshow/config.json
wallshow reload
```

### How do I auto-start wallshow on login?

**Systemd user service** (create `~/.config/systemd/user/wallshow.service`):

```ini
[Unit]
Description=Wallshow wallpaper daemon
After=graphical-session.target

[Service]
Type=forking
ExecStart=%h/.local/bin/wallshow start
ExecStop=%h/.local/bin/wallshow stop
Restart=on-failure

[Install]
WantedBy=default.target
```

Enable it:

```bash
systemctl --user enable --now wallshow.service
```

### GIF extraction is slow

GIF frames are cached permanently after first extraction. Subsequent playback is instant.

To pre-extract all GIFs:

```bash
for gif in ~/Pictures/wallpapers/animated/*.gif; do
    wallshow next  # Trigger extraction
    sleep 1
done
```

### How do I clear the cache?

```bash
# Automatic cleanup (respects max_cache_size_mb)
wallshow clean

# Manual cleanup (removes all cached GIF frames)
rm -rf ~/.cache/wallshow/gifs/*
```

## Troubleshooting

### Check Dependencies

```bash
# Verify required tools
command -v bash jq socat

# Check optional tools
command -v convert magick  # ImageMagick
command -v swww swaybg feh xwallpaper  # Backends
```

### Verify Installation

```bash
# Check binary location
which wallshow

# Check library path
ls -la /usr/lib/wallshow  # System install
ls -la ~/.local/lib/wallshow  # Local install
```

### Test Manually

```bash
# Run in foreground with debug output
wallshow -d daemon

# Check status
wallshow status | jq '.'

# List discovered wallpapers
wallshow list
```

### Common Issues

1. **"command not found: wallshow"**
   - Ensure `~/.local/bin` is in `$PATH` for local installs
   - Run `export PATH="$HOME/.local/bin:$PATH"`

2. **"jq: command not found"**
   - Install jq: `sudo pacman -S jq` (Arch) or `sudo apt install jq` (Debian)

3. **"No wallpaper backend found"**
   - Install at least one backend (swww, swaybg, feh, or xwallpaper)

4. **Wallpaper not changing**
   - Check daemon status: `wallshow status`
   - Verify wallpaper directory exists and contains images
   - Check logs: `tail -f ~/.local/state/wallshow/wallpaper.log`

## Development

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup, code style, and contribution guidelines.

### Quick Development Setup

```bash
# Clone and enter directory
git clone https://github.com/UtsavBalar1231/wallshow.git
cd wallshow

# Run from source (no installation)
just run help

# Build packages
just build-all
```

## Contributing

Contributions are welcome! Please read [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

- Report bugs: [GitHub Issues](https://github.com/UtsavBalar1231/wallshow/issues)
- Feature requests: [GitHub Discussions](https://github.com/UtsavBalar1231/wallshow/discussions)
- Pull requests: Fork, branch, test, submit PR

## License

[MIT License](LICENSE) - Copyright (c) 2025 UtsavBalar1231

## Acknowledgments

- Inspired by the need for a simple, scriptable wallpaper manager
- Built with modern Bash best practices and XDG compliance
- Thanks to the Wayland and X11 communities for excellent wallpaper backends
