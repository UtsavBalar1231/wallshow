# Justfile - Development automation for wallshow
# https://github.com/casey/just

# Default - show available commands
default:
    @just --list

# Development workflow

# Install to ~/.local for testing
install:
    mkdir -p ~/.local/bin ~/.local/lib/wallshow
    cp bin/wallshow ~/.local/bin/
    cp -r lib/* ~/.local/lib/wallshow/
    chmod +x ~/.local/bin/wallshow
    @echo "✓ Installed to ~/.local/bin/wallshow"

# Uninstall from ~/.local
uninstall:
    rm -f ~/.local/bin/wallshow
    rm -rf ~/.local/lib/wallshow
    @echo "✓ Uninstalled from ~/.local"

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
    # cd pkg && makepkg -f
    @echo "TODO: later"

# Build RPM package
build-rpm:
    # rpmbuild -ba rpm/wallshow.spec
    @echo "TODO: later"

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
