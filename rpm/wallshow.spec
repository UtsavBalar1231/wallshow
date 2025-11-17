Name:           wallshow
Version:        1.0.0
Release:        1%{?dist}
Summary:        Professional wallpaper manager for Wayland/X11

License:        MIT
URL:            https://github.com/UtsavBalar1231/wallshow
Source0:        %{url}/archive/v%{version}/%{name}-%{version}.tar.gz

BuildArch:      noarch
BuildRequires:  bash
BuildRequires:  jq
BuildRequires:  socat

Requires:       bash >= 5.0
Requires:       jq
Requires:       socat

Recommends:     ImageMagick
Recommends:     logrotate

%description
Wallshow is a wallpaper manager for Wayland and X11 window systems written
in Bash. It provides automated wallpaper rotation with support for both
static and animated (GIF) wallpapers.

Features:
* Daemon mode with automatic wallpaper rotation
* Support for static images and animated GIFs
* Battery optimization (disable animations on battery)
* IPC control via Unix sockets
* Multiple backend support (swww, swaybg, feh, xwallpaper)
* XDG Base Directory specification compliance
* JSON-based configuration and state management

%prep
%autosetup

%build
# No build step needed for shell scripts

%install
# Install main executable
install -Dm755 bin/wallshow %{buildroot}%{_bindir}/wallshow

# Install library modules (preserving directory structure)
mkdir -p %{buildroot}%{_prefix}/lib/wallshow
cp -r lib/* %{buildroot}%{_prefix}/lib/wallshow/

# Set proper permissions for library files
find %{buildroot}%{_prefix}/lib/wallshow -type f -exec chmod 644 {} \;
find %{buildroot}%{_prefix}/lib/wallshow -type d -exec chmod 755 {} \;

# Install logrotate configuration
install -Dm644 logrotate.d/wallshow %{buildroot}%{_sysconfdir}/logrotate.d/wallshow

# Install systemd user service
install -Dm644 systemd/wallshow.service %{buildroot}%{_userunitdir}/wallshow.service

# Install documentation
install -Dm644 README.md %{buildroot}%{_docdir}/%{name}/README.md
install -Dm644 LICENSE %{buildroot}%{_datadir}/licenses/%{name}/LICENSE

%files
%license LICENSE
%doc README.md
%{_bindir}/wallshow
%{_prefix}/lib/wallshow/
%config(noreplace) %{_sysconfdir}/logrotate.d/wallshow
%{_userunitdir}/wallshow.service

%post
# Reload systemd user daemon for all users (best effort)
systemctl --global daemon-reload 2>/dev/null || true

%changelog
* Fri Nov 15 2025 UtsavBalar1231 <utsavbalar1231@gmail.com> - 1.0.0-1
- Initial release
- Modular architecture with feature-based organization
- Support for static and animated (GIF) wallpapers
- Daemon mode with automatic rotation
- Battery optimization support
- IPC control via Unix sockets
- Multiple backend support (swww, swaybg, feh, xwallpaper)
- XDG Base Directory specification compliance
