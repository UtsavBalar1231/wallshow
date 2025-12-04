# Justfile - Development automation for wallshow
# https://github.com/casey/just

# Default - show available commands
default:
    @just --list

# Development workflow

# Install to ~/.local for testing
install:
    mkdir -p ~/.local/bin ~/.local/lib/wallshow ~/.config/systemd/user
    cp bin/wallshow ~/.local/bin/
    cp -r lib/* ~/.local/lib/wallshow/
    chmod +x ~/.local/bin/wallshow
    sed -i 's|WALLSHOW_LIB="/usr/lib/wallshow"|WALLSHOW_LIB="{{ env_var('HOME') }}/.local/lib/wallshow"|' ~/.local/bin/wallshow
    sed 's|/usr/bin/wallshow|{{ env_var('HOME') }}/.local/bin/wallshow|' systemd/wallshow.service > ~/.config/systemd/user/wallshow.service
    systemctl --user daemon-reload
    @echo "✓ Installed to ~/.local/bin/wallshow"
    @echo "✓ Installed systemd service to ~/.config/systemd/user/wallshow.service"
    @echo ""
    @echo "To enable auto-start on login:"
    @echo "  systemctl --user enable --now wallshow.service"

# Uninstall from ~/.local
uninstall:
    -systemctl --user stop wallshow.service 2>/dev/null || true
    -systemctl --user disable wallshow.service 2>/dev/null || true
    rm -f ~/.local/bin/wallshow
    rm -rf ~/.local/lib/wallshow
    rm -f ~/.config/systemd/user/wallshow.service
    systemctl --user daemon-reload
    @echo "✓ Uninstalled from ~/.local"
    @echo "✓ Removed systemd service"

# Testing

# Shellcheck all files
lint:
    @echo "Running shellcheck..."
    @find bin lib -type f \( -name "*.sh" -o -name "wallshow" \) | xargs shellcheck -x 2>&1 || echo "✓ Shellcheck passed"

# Packaging

# Build Debian package
build-deb:
    dpkg-buildpackage -b --no-sign -d

# Build Arch package
build-pkg:
    cd pkg && makepkg -sf --noconfirm

# Build RPM package
build-rpm:
    rpmbuild -ba rpm/wallshow.spec

# Build all packages
build-all: build-deb build-pkg build-rpm

# Version management

# Update version in all files
version-bump VERSION:
    sed -i 's/VERSION=".*"/VERSION="{{ VERSION }}"/' bin/wallshow
    sed -i 's/declare -r VERSION=".*"/declare -r VERSION="{{ VERSION }}"/' lib/core/constants.sh
    @echo "✓ Updated version to {{ VERSION }}"
    @echo "TODO: Update debian/changelog, PKGBUILD, and spec file manually"

# CI/CD helpers

# Run pre-commit hooks manually
pre-commit:
    @command -v pre-commit >/dev/null || (echo "pre-commit not installed. Run: pip install pre-commit" && exit 1)
    pre-commit run --all-files

# Run all CI checks locally (lint, format, pre-commit)
ci-local:
    @echo "Running local CI checks..."
    @echo ""
    @echo "==> Running shellcheck..."
    @just lint
    @echo ""
    @echo "==> Running format check..."
    @just format-check
    @echo ""
    @echo "==> Running pre-commit hooks..."
    @just pre-commit || true
    @echo ""
    @echo "✓ All local CI checks complete"

# Format check (optional)
format-check:
    @command -v shfmt >/dev/null && find bin lib -type f | xargs shfmt -d || echo "shfmt not installed, skipping format check"

# Clean build artifacts
clean:
    @echo "Cleaning build artifacts..."
    rm -rf debian/.debhelper debian/wallshow debian/files debian/*.debhelper.log debian/*.substvars
    rm -rf pkg/*.pkg.tar.zst pkg/src pkg/pkg
    rm -rf rpm/BUILD rpm/RPMS rpm/SRPMS
    @echo "✓ Cleaned"

# Maintenance

# Rotate logs manually (keeps 5 rotated files)
rotate-logs:
    #!/usr/bin/env bash
    LOG_FILE="${XDG_STATE_HOME:-$HOME/.local/state}/wallshow/wallpaper.log"
    if [[ -f "$LOG_FILE" ]]; then
        for i in 4 3 2 1; do
            [[ -f "$LOG_FILE.$i" ]] && mv -f "$LOG_FILE.$i" "$LOG_FILE.$((i+1))"
        done
        mv -f "$LOG_FILE" "$LOG_FILE.1"
        touch "$LOG_FILE"
        chmod 600 "$LOG_FILE"
        echo "✓ Rotated logs"
    else
        echo "No log file found at $LOG_FILE"
    fi

# Clear all logs
clear-logs:
    #!/usr/bin/env bash
    LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/wallshow"
    rm -f "$LOG_DIR"/wallpaper.log* 2>/dev/null
    touch "$LOG_DIR/wallpaper.log"
    chmod 600 "$LOG_DIR/wallpaper.log"
    echo "✓ Cleared all logs"

# Show log file size
log-size:
    #!/usr/bin/env bash
    LOG_FILE="${XDG_STATE_HOME:-$HOME/.local/state}/wallshow/wallpaper.log"
    if [[ -f "$LOG_FILE" ]]; then
        ls -lh "$LOG_FILE" | awk '{print "Log size: " $5}'
        ls -lh "$LOG_FILE".* 2>/dev/null | awk '{print "  " $9 ": " $5}' || true
    else
        echo "No log file found"
    fi

# Development helpers

# Run wallshow from local directory (dev mode)
run *ARGS:
    WALLSHOW_LIB="$(pwd)/lib" ./bin/wallshow {{ ARGS }}

# Show info about modular structure
info:
    @echo "Wallshow Modular Structure"
    @echo "=========================="
    @echo ""
    @echo "Entry point: bin/wallshow"
    @echo ""
    @echo "Modules:"
    @echo "  Core:      $(ls lib/core/*.sh | wc -l) files"
    @echo "  System:    $(ls lib/system/*.sh | wc -l) files"
    @echo "  Wallpaper: $(ls lib/wallpaper/*.sh | wc -l) files"
    @echo "  Animation: $(ls lib/animation/*.sh | wc -l) files"
    @echo "  Daemon:    $(ls lib/daemon/*.sh | wc -l) files"
    @echo "  CLI:       $(ls lib/cli/*.sh | wc -l) files"
    @echo ""
    @echo "Total: $(find lib -name "*.sh" | wc -l) modules"
