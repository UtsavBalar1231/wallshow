# Contributing to Wallshow

Thank you for your interest in contributing to Wallshow! This document provides guidelines and instructions for contributing to the project.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Setup](#development-setup)
- [Project Structure](#project-structure)
- [Code Style](#code-style)
- [Submitting Changes](#submitting-changes)
- [Reporting Issues](#reporting-issues)
- [Feature Requests](#feature-requests)

## Code of Conduct

Be respectful and constructive in all interactions. We're here to build great software together.

## Getting Started

### Prerequisites

- bash ≥ 5.0
- jq
- socat
- ImageMagick (optional, for GIF support)
- At least one wallpaper backend (swww, swaybg, feh, or xwallpaper)
- [just](https://github.com/casey/just) (recommended for development)
- shellcheck (recommended for linting)

### Fork and Clone

```bash
# Fork the repository on GitHub, then clone your fork
git clone https://github.com/YOUR_USERNAME/wallshow.git
cd wallshow

# Add upstream remote
git remote add upstream https://github.com/UtsavBalar1231/wallshow.git
```

## Development Setup

### Install to Local User Directory

```bash
# Install to ~/.local (no root required)
just install

# Or manually
mkdir -p ~/.local/bin ~/.local/lib/wallshow
cp bin/wallshow ~/.local/bin/
cp -r lib/* ~/.local/lib/wallshow/
chmod +x ~/.local/bin/wallshow

# Ensure ~/.local/bin is in PATH
export PATH="$HOME/.local/bin:$PATH"
```

### Run Without Installing

```bash
# Run directly from source directory
WALLSHOW_LIB="$(pwd)/lib" ./bin/wallshow help

# Or use the Justfile
just run help
just run info
just run daemon
```

### Uninstall

```bash
just uninstall

# Or manually
rm -f ~/.local/bin/wallshow
rm -rf ~/.local/lib/wallshow
```

## Project Structure

Wallshow uses a modular architecture organized by feature:

```
wallshow/
├── bin/
│   └── wallshow              # Main entry point
├── lib/
│   ├── core/                 # Core functionality
│   │   ├── constants.sh      # Global constants, XDG paths, exit codes
│   │   ├── logging.sh        # Logging system with rotation
│   │   ├── state.sh          # JSON state management (atomic updates)
│   │   └── config.sh         # Configuration loading and validation
│   ├── system/               # System-level operations
│   │   ├── locking.sh        # Instance locking with flock
│   │   ├── paths.sh          # Path validation and sanitization
│   │   └── init.sh           # Directory initialization, cleanup handlers
│   ├── wallpaper/            # Wallpaper management
│   │   ├── discovery.sh      # Find and cache wallpapers
│   │   ├── selection.sh      # Random selection, battery awareness
│   │   └── backends.sh       # Backend support (swww, swaybg, feh, xwallpaper)
│   ├── animation/            # GIF animation support
│   │   ├── gif.sh            # Frame extraction, ImageMagick interface
│   │   └── playback.sh       # Animation subprocess, frame cycling
│   ├── daemon/               # Daemon mode
│   │   ├── process.sh        # Daemonization, signal handling
│   │   ├── ipc.sh            # Unix socket IPC, command handlers
│   │   └── loop.sh           # Main wallpaper change loop
│   └── cli/                  # Command-line interface
│       ├── commands.sh       # Command dispatch, dependency checks
│       └── interface.sh      # Help text, status display
├── debian/                   # Debian packaging
├── pkg/                      # Arch Linux packaging
├── rpm/                      # Fedora packaging
├── docs/                     # Design documents
├── Justfile                  # Development automation
├── README.md
├── LICENSE
└── CONTRIBUTING.md
```

### Module Dependencies

Modules are sourced in dependency order in `bin/wallshow`:

1. **core** modules (no dependencies)
2. **system** modules (depend on core)
3. **wallpaper** modules (depend on core + system)
4. **animation** modules (depend on core + wallpaper)
5. **daemon** modules (depend on all previous)
6. **cli** modules (depend on all previous)

**Important**: When adding new functionality, respect this dependency hierarchy.

## Code Style

### Bash Best Practices

```bash
# Always use strict mode
set -euo pipefail

# Quote all variables
local_var="${SOME_VAR}"

# Use snake_case for functions and variables
function my_function() {
    local my_var="value"
}

# Use SCREAMING_SNAKE_CASE for constants
declare -r MY_CONSTANT="value"

# Prefer [[ ]] over [ ]
if [[ "${var}" == "value" ]]; then
    # ...
fi

# Use process substitution over pipes for loops (avoids subshells)
while IFS= read -r line; do
    # Process line
done < <(some_command)
```

### Naming Conventions

- **Functions**: `snake_case` (e.g., `change_wallpaper`, `init_directories`)
- **Variables**: `snake_case` (e.g., `wallpaper_dir`, `config_file`)
- **Constants**: `SCREAMING_SNAKE_CASE` (e.g., `LOG_FILE`, `E_SUCCESS`)
- **Files**: `lowercase.sh` (e.g., `logging.sh`, `state.sh`)

### Comments

- Use comments to explain **why**, not **what**
- Document complex algorithms and non-obvious logic
- Mark TODOs clearly: `# TODO: description`
- Add section dividers in long files:

```bash
# ============================================================================
# Wallpaper Discovery
# ============================================================================
```

### Error Handling

```bash
# Use die() for fatal errors
die "Configuration file not found" "${E_GENERAL}"

# Validate external input
validate_path "${user_input}" "${base_dir}" || die "Invalid path" "${E_USAGE}"

# Log before failing
log_error "Failed to acquire lock"
exit "${E_LOCKED}"
```

### JSON Handling

```bash
# Always escape JSON values
local escaped_value
escaped_value=$(printf '%s' "${value}" | jq -Rs .)

# Use jq for JSON construction
local json
json=$(jq -n \
    --arg key "${escaped_value}" \
    '{field: $key}')

# Use atomic updates for state
update_state_atomic '.field = "value"'
```

### Shellcheck

All shell scripts must pass `shellcheck -x`:

```bash
# Check all files
find bin lib -type f \( -name "*.sh" -o -name "wallshow" \) | xargs shellcheck -x

# Note: The following warnings are acceptable in our modular architecture:
# SC2034 - Variables unused in current file but used in others
# SC1091 - Source following not possible (dynamic paths)
# SC2153 - Misspelling detection across modules
```

### Manual Testing

Before submitting a PR, test these scenarios:

1. **Fresh install**: Remove `~/.config/wallshow`, `~/.local/state/wallshow`, test first run
2. **Daemon lifecycle**: `start`, `status`, `next`, `pause`, `resume`, `stop`
3. **IPC commands**: All socket commands work correctly
4. **Config reload**: Change config, reload, verify changes applied
5. **Battery transitions**: Test behavior on AC vs battery (if applicable)
6. **GIF handling**: Test with various GIF sizes and formats
7. **Error conditions**: Invalid config, missing directories, stale locks

## Submitting Changes

### Create a Feature Branch

```bash
# Update your fork
git fetch upstream
git checkout main
git merge upstream/main

# Create feature branch
git checkout -b feature/my-feature
# or
git checkout -b fix/my-bugfix
```

### Commit Guidelines

Follow [Conventional Commits](https://www.conventionalcommits.org/):

```
feat: add multi-monitor configuration support
fix: prevent race condition in state updates
docs: update battery optimization FAQ
refactor: extract wallpaper selection to separate module
test: add tests for GIF frame extraction
chore: update shellcheck configuration
```

**Commit message structure:**

```
<type>(<optional scope>): <description>

[optional body]

[optional footer]
```

**Types:**
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `refactor`: Code refactoring (no behavior change)
- `test`: Adding or updating tests
- `chore`: Maintenance tasks

**Examples:**

```bash
git commit -m "feat(animation): add configurable GIF loop count"

git commit -m "fix(daemon): handle SIGTERM gracefully" -m "Previously, SIGTERM would leave stale lock files. Now cleanup() is called on all signals."

git commit -m "docs(readme): add systemd autostart instructions"
```

### Push and Create PR

```bash
# Push to your fork
git push origin feature/my-feature

# Create pull request on GitHub
# Fill in the PR template with:
# - Description of changes
# - Related issue (if any)
# - Testing performed
# - Screenshots (if UI-related)
```

### PR Checklist

- [ ] Code follows project style guidelines
- [ ] All shellcheck warnings addressed or justified
- [ ] Documentation updated (README, code comments)
- [ ] Commit messages follow conventional format
- [ ] PR description is clear and complete

## Reporting Issues

### Before Creating an Issue

1. **Search existing issues**: Your issue may already be reported
2. **Check FAQ**: Review README FAQ section
3. **Verify it's a bug**: Test with default configuration
4. **Collect information**: Logs, version, system details

### Issue Template

```markdown
**Description:**
A clear and concise description of the issue.

**Steps to Reproduce:**
1. Run command X
2. Observe behavior Y
3. Expected behavior Z

**Environment:**
- Wallshow version: `wallshow --version`
- OS/Distribution: `uname -a`
- Display server: Wayland/X11
- Wallpaper backend: swww/swaybg/feh/xwallpaper
- Dependencies: `jq --version`, `socat -V`, `convert -version`

**Logs:**
```
# Paste relevant logs from ~/.local/state/wallshow/wallpaper.log
# Enable debug logging: jq '.behavior.debug = true' ~/.config/wallshow/config.json
```

**Configuration:**
```json
# Paste ~/.config/wallshow/config.json (redact sensitive paths if needed)
```

**Additional Context:**
Any other relevant information.
```

## Feature Requests

Feature requests are welcome! Please:

1. **Check existing requests**: Search issues and discussions
2. **Describe the use case**: Explain why this feature is valuable
3. **Propose a solution**: If you have implementation ideas
4. **Consider scope**: Keep features aligned with project goals

### Feature Request Template

```markdown
**Feature Description:**
Clear description of the proposed feature.

**Use Case:**
Why is this feature valuable? What problem does it solve?

**Proposed Implementation:**
(Optional) How could this be implemented?

**Alternatives Considered:**
(Optional) Other approaches you've considered.

**Additional Context:**
Any other relevant information.
```

## Development Workflow Summary

1. Fork and clone the repository
2. Create a feature branch
3. Make changes following code style guidelines
4. Test thoroughly (manual testing)
5. Commit with conventional commit messages
6. Push to your fork
7. Create pull request with clear description
8. Address review feedback
9. Celebrate when merged! 🎉

## Getting Help

- **Documentation**: See [README.md](README.md) and [CLAUDE.md](CLAUDE.md)
- **Issues**: [GitHub Issues](https://github.com/UtsavBalar1231/wallshow/issues)
- **Discussions**: [GitHub Discussions](https://github.com/UtsavBalar1231/wallshow/discussions)

## License

By contributing to Wallshow, you agree that your contributions will be licensed under the [MIT License](LICENSE).

---

Thank you for contributing to Wallshow! Your efforts help make this project better for everyone.
