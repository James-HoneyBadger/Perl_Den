# BadgerOps IDE — Linux Environment Specification

Complete specification of the runtime environment required by BadgerOps IDE.  
Reference platform: **Arch Linux ARM aarch64** (rolling release).

---

## 1. Operating System

| Requirement           | Specification                                        |
|-----------------------|------------------------------------------------------|
| **OS**                | Linux (kernel ≥ 5.x)                                 |
| **Architecture**      | aarch64 (ARM64) — also supports x86_64               |
| **Init system**       | systemd (required for ServiceMonitor, CronManager)   |
| **Locale**            | UTF-8 (e.g. `en_US.UTF-8`). **Required** for correct Unicode rendering in GUI and terminal output. Verify with `locale`. |
| **Display server**    | X11 or Wayland (GTK3 supports both)                  |

### Reference Versions

```
Arch Linux ARM (rolling)
Kernel: 6.18.2-1-aarch64-ARCH
systemd: 259
```

---

## 2. Perl Runtime

| Component             | Minimum Version | Reference Version               |
|-----------------------|-----------------|---------------------------------|
| **perl**              | 5.26+           | 5.42.0                          |
| **Threading**         | `-Dusethreads`  | `aarch64-linux-thread-multi`    |

Perl must be built with thread support (standard on Arch and most distros).

---

## 3. Perl Module Dependencies

Install all with: `cpanm --installdeps .`  
Declared in both `Makefile.PL` and `cpanfile`.

### 3.1 GUI Toolkit

| Module                         | Min Version | Purpose                          |
|--------------------------------|-------------|----------------------------------|
| `Glib`                         | 1.329       | GLib event loop, type system     |
| `Glib::Object::Introspection`  | 0.049       | GObject Introspection bindings   |
| `Gtk3`                         | 0.038       | GTK3 widget toolkit              |

> **GtkSourceView** is loaded at runtime via `Glib::Object::Introspection` (mapped to the `Gtk3::SourceView::*` namespace). No separate CPAN module is required — install the system package `gir1.2-gtksource-4` (Debian) or `gtksourceview4` (Arch) instead.

### 3.2 Sysadmin / Core

| Module                | Min Version | Purpose                                  |
|-----------------------|-------------|------------------------------------------|
| `Proc::ProcessTable`  | 0.634       | Process listing (ProcessManager)         |
| `Net::DNS`            | 1.36        | DNS lookups (NetworkDiag)                |
| `IO::Socket::SSL`     | 2.085       | SSL/TLS connections (SSLChecker)         |
| `Net::SSLeay`         | 1.92        | Low-level SSL (used by SSLChecker)       |
| `Text::Diff`          | 1.45        | File comparison (ConfigDiff)             |
| `YAML::XS`            | 0.88        | Config file persistence                  |
| `JSON::MaybeXS`       | 1.004       | JSON parsing                             |

### 3.3 Developer Tools

| Module            | Min Version | Purpose                       |
|-------------------|-------------|-------------------------------|
| `Perl::Tidy`      | 20230309    | Code formatting (Tools menu)  |
| `Perl::Critic`    | 1.152       | Linting (Tools menu)          |

### 3.4 Core Modules (shipped with Perl, no install needed)

| Module               | Purpose                          |
|----------------------|----------------------------------|
| `Archive::Tar`       | Backup creation                  |
| `IO::Compress::Gzip` | Compressed backups               |
| `Digest::SHA`        | File hashing (DuplicateFinder)   |
| `Digest::MD5`        | File hashing                     |
| `File::Temp`         | Temporary files                  |
| `File::Find`         | Directory traversal              |
| `File::Copy`         | File operations                  |
| `POSIX`              | System calls, time formatting    |
| `IPC::Open3`         | Process I/O capture              |
| `Socket`             | Network primitives               |

### 3.5 Test Dependencies

| Module              | Min Version | Purpose                     |
|---------------------|-------------|-----------------------------|
| `Test::More`        | 1.302       | Core test framework          |
| `Test::Exception`   | 0.43        | Exception testing            |
| `Test::MockModule`  | 0.177       | Module mocking               |
| `Test::Pod`         | 1.52        | POD validation               |

---

## 4. System Libraries (Native)

These are the C/system libraries required by the Perl modules and GUI.

### Arch Linux Packages

```bash
# GTK3 toolkit and related
sudo pacman -S gtk3 vte3 gtksourceview4

# GObject Introspection (required by Perl Glib/Gtk3 bindings)
sudo pacman -S gobject-introspection gobject-introspection-runtime

# SSL/TLS
sudo pacman -S openssl

# Privilege escalation (for "Run as Root" feature)
sudo pacman -S polkit

# Network tools
sudo pacman -S iproute2     # ip, ss commands
sudo pacman -S iputils      # ping

# Process tools
sudo pacman -S procps-ng    # ps, top

# Hostname
sudo pacman -S inetutils    # hostname command

# Cron
sudo pacman -S cronie       # crontab command

# Core system
sudo pacman -S coreutils    # df, uname, etc.
```

### Reference Versions

| Package                    | Version          |
|----------------------------|------------------|
| gtk3                       | 3.24.51          |
| vte3                       | 0.82.2           |
| gtksourceview4             | 4.8.x            |
| gobject-introspection      | 1.86.0           |
| openssl                    | 3.6.0            |
| polkit                     | 127              |
| iproute2                   | 6.18.0           |
| inetutils                  | 2.7              |
| procps-ng                  | 4.0.5            |
| cronie                     | 1.7.2            |
| systemd                    | 259              |

---

## 5. Unicode Fonts

**Required** for correct rendering of emoji, symbols, box-drawing characters,
and CJK text used throughout the GUI (Dashboard, ScriptBrowser, report output).

### Arch Linux

```bash
sudo pacman -S noto-fonts noto-fonts-emoji noto-fonts-cjk noto-fonts-extra ttf-freefont
```

After installation, rebuild the font cache:

```bash
fc-cache -f
```

### Debian / Ubuntu

```bash
sudo apt install fonts-noto fonts-noto-color-emoji fonts-noto-cjk fonts-freefont-ttf
```

### Fedora / RHEL

```bash
sudo dnf install google-noto-fonts-common google-noto-emoji-fonts google-noto-sans-cjk-fonts google-noto-serif-cjk-fonts gnu-free-fonts-common
```

### What Gets Installed

| Package               | Coverage                                                  |
|-----------------------|-----------------------------------------------------------|
| `noto-fonts`          | Latin, Cyrillic, Greek, Arabic, Hebrew, Thai, and more    |
| `noto-fonts-emoji`    | Color emoji (🖥 📋 👤 🌐 🔒 💾 etc.)                     |
| `noto-fonts-cjk`      | Chinese, Japanese, Korean ideographs                      |
| `noto-fonts-extra`    | Additional scripts (Georgian, Armenian, Tibetan, etc.)    |
| `ttf-freefont`        | Broad Unicode fallback coverage (GNU FreeFont)            |

### Unicode Characters Used by BadgerOps

| Character(s)          | Location                       | Purpose                    |
|-----------------------|--------------------------------|----------------------------|
| 🖥 📋 👤 🌐 🔒 💾    | ScriptRegistry → ScriptBrowser | Category labels in sidebar |
| ⊞                    | Dashboard title                | Window grid symbol         |
| ╔ ═ ╗ ║ ╚ ╝ ─        | Script `format_report()` output| Box-drawing report banners |
| ●                    | GUI status/tree indicators     | Visual markers             |

### Verification

```bash
# Confirm emoji font is active
fc-match emoji
# Expected: NotoColorEmoji.ttf: "Noto Color Emoji" "Regular"

# Confirm total font families available
fc-list : family | sort -u | wc -l
# Expected: 2000+ families

# Confirm CJK coverage
fc-list :lang=ja family | head -3
# Expected: Noto Sans CJK / Noto Serif CJK entries

# Test rendering in terminal
echo '🖥 📋 👤 🌐 🔒 💾 ╔═══╗'
```

---

## 6. System Commands

The toolkit scripts shell out to these Linux commands. All must be on `$PATH`.

### Required

| Command        | Package (Arch)  | Used By                              |
|----------------|-----------------|--------------------------------------|
| `perl`         | `perl`          | All script execution                 |
| `bash`         | `bash`          | Shell command execution              |
| `hostname`     | `inetutils`     | Dashboard                            |
| `uname`        | `coreutils`     | Dashboard, SystemInfo                |
| `df`           | `coreutils`     | Dashboard, DiskUsage                 |
| `ps`           | `procps-ng`     | Dashboard, ProcessManager            |
| `ip`           | `iproute2`      | NetworkDiag, SystemInfo              |
| `ss`           | `iproute2`      | PortScanner                          |
| `ping`         | `iputils`       | NetworkDiag                          |
| `systemctl`    | `systemd`       | ServiceMonitor, CronManager, SystemdAnalyzer |
| `journalctl`   | `systemd`       | FailedLoginDetector, LogAnalyzer     |
| `openssl`      | `openssl`       | SSLChecker (local cert scanning)     |
| `crontab`      | `cronie`        | CronManager                          |
| `pod2text`     | `perl`          | Tutorial browser (POD rendering)     |

### Optional

| Command            | Package (Arch)  | Used By                          |
|--------------------|-----------------|----------------------------------|
| `pkexec`           | `polkit`        | "Run as Root" feature            |
| `fail2ban-client`  | `fail2ban`      | FailedLoginDetector (ban status) |
| `resolvectl`       | `systemd`       | NetworkDiag (DNS server fallback)|
| `last`             | `util-linux`    | UserAudit (login history)        |
| `docker`           | `docker`        | DockerMonitor (container status) |
| `nft`              | `nftables`      | FirewallAuditor (nftables rules) |
| `iptables`         | `iptables`      | FirewallAuditor (iptables rules) |
| `systemd-analyze`  | `systemd`       | SystemdAnalyzer (boot analysis)  |
| `rpm` / `dpkg` / `pacman` | (distro) | PackageAuditor (package listing) |
| `dnf` / `apt` / `pacman`  | (distro) | PackageAuditor (update checking) |

---

## 7. File System Paths

### Application Layout

```
BadgerOps/                     # Project root ($BADGEROPS_ROOT_DIR)
├── bin/                     # Perl entry points (badgerops-cli, badgerops-tui, badgerops-ide)
├── lib/BadgerOps/              # Perl modules
│   ├── App.pm               # GUI application controller
│   ├── BatchRunner.pm       # Batch/parallel script execution
│   ├── Config.pm            # YAML-based config persistence
│   ├── Git.pm               # Git repository status with caching
│   ├── Runner.pm            # Non-blocking script execution
│   ├── ScriptRegistry.pm    # Canonical script index
│   ├── Util.pm              # Shared utilities
│   ├── GUI/                 # GTK3 GUI modules
│   └── Scripts/             # Sysadmin tool modules (20)
├── scripts/                 # Standalone .pl scripts
├── share/
│   ├── icons/               # Application icons (SVG + PNG)
│   ├── templates/           # New-file templates (8)
│   ├── themes/              # GTK CSS themes (5: dark, light, high-contrast, vscode-dark, vscode-light)
│   └── tutorials/           # 12 Perl tutorial POD files
| t/                       # Test suite (29 top-level + unit/ + integration/)
│   ├── unit/                # Unit tests
│   ├── integration/         # Integration tests
│   └── fixtures/            # Test data files
├── docs/                    # Documentation
├── .github/workflows/       # CI configuration
├── _badgerops_env.sh               # Environment bootstrap
├── cpanfile                  # CPAN dependency declaration
└── Makefile.PL               # Build system
```

### Runtime Configuration

| Path                                  | Purpose                            |
|---------------------------------------|-------------------------------------|
| `~/.config/badgerops/`                 | Config directory (auto-created)     |
| `~/.config/badgerops/config.yml`       | User preferences (theme, font, etc.)|
| `~/.config/badgerops/session.yml`      | Session state (window size, tabs)   |
| `~/.config/badgerops/baselines/`       | ConfigDiff baseline copies          |

### System Paths Read by Scripts

| Path                    | Script(s)                              | Requires Root |
|-------------------------|----------------------------------------|---------------|
| `/proc/cpuinfo`         | SystemInfo                             | No            |
| `/proc/meminfo`         | SystemInfo, Dashboard                  | No            |
| `/proc/uptime`          | Dashboard                              | No            |
| `/proc/loadavg`         | Dashboard                              | No            |
| `/proc/stat`            | Dashboard                              | No            |
| `/etc/passwd`           | UserAudit                              | No            |
| `/etc/shadow`           | UserAudit, ConfigDiff                  | Yes           |
| `/etc/group`            | UserAudit                              | No            |
| `/etc/hostname`         | ConfigDiff                             | No            |
| `/var/log/auth.log`     | FailedLoginDetector (fallback¹)        | Yes           |
| `/var/log/secure`       | FailedLoginDetector (fallback¹)        | Yes           |
| `/var/log/messages`     | FailedLoginDetector / LogAnalyzer (fallback²) | Yes    |
| `/var/log/syslog`       | LogAnalyzer (fallback²)                | Yes           |
| `/` (filesystem root)   | FilePermissions (default scan target)  | Partial³      |

¹ FailedLoginDetector tries `journalctl` first, then falls back to log files in order.  
² LogAnalyzer tries `/var/log/syslog`, `/var/log/messages`, then `journalctl`.  
³ FilePermissions traverses the filesystem checking SUID/SGID/world-writable files; some directories require root.

---

## 8. Environment Variables

Set automatically by `_badgerops_env.sh` when launching via the wrapper scripts.

| Variable              | Value                              | Purpose                       |
|-----------------------|------------------------------------|-------------------------------|
| `BADGEROPS_ROOT_DIR`        | Project root (auto-detected)       | Base path for all lookups     |
| `BADGEROPS_SHARE_DIR`  | `$BADGEROPS_ROOT_DIR/share`              | Templates, themes, tutorials  |
| `BADGEROPS_SCRIPTS_DIR`| `$BADGEROPS_ROOT_DIR/scripts`            | Toolkit script directory      |
| `BADGEROPS_LAUNCH_NAME`     | `basename $0` of wrapper script    | Display name in CLI/TUI help  |
| `PERL5LIB`           | Prepended with `$BADGEROPS_ROOT_DIR/lib` | Module resolution             |
| `PATH`               | Prepended with `$BADGEROPS_ROOT_DIR/bin` | Command resolution            |
| `DISPLAY` / `WAYLAND_DISPLAY` | (system-set)            | Required for GUI mode (also required for `badgerops-ide --version` due to compile-time `Gtk3 -init`) |

---

## 9. Installation Quick Reference

### Arch Linux (Full Setup)

```bash
# 1. System dependencies
sudo pacman -S perl gtk3 vte3 gtksourceview4 gobject-introspection \
    openssl polkit iproute2 inetutils procps-ng cronie iputils

# 2. Unicode fonts
sudo pacman -S noto-fonts noto-fonts-emoji noto-fonts-cjk noto-fonts-extra ttf-freefont
fc-cache -f

# 3. Perl module dependencies
cpanm --installdeps .

# 4. Verify
perl -c lib/BadgerOps/App.pm       # Compile check
prove -l t/00_compile.t          # Module compile test

# 5. Install commands (optional — adds badgerops, badgerops-cli, etc. to PATH)
./install_badgerops_command.sh --user

# 6. Launch
./badgerops-gui                        # GTK3 IDE
./badgerops-cli list                   # CLI — list scripts
./badgerops-tui                        # Terminal UI
```

### Debian / Ubuntu (Full Setup)

```bash
# 1. System dependencies
sudo apt install perl libgtk3-perl libvte-2.91-dev libgtksourceview-4-dev \
    gir1.2-vte-2.91 gir1.2-gtksource-4 libglib-object-introspection-perl \
    openssl policykit-1 iproute2 procps cron iputils-ping

# 2. Unicode fonts
sudo apt install fonts-noto fonts-noto-color-emoji fonts-noto-cjk fonts-freefont-ttf
fc-cache -f

# 3. Perl module dependencies
sudo apt install cpanminus
cpanm --installdeps .
```

---

## 10. Verification Checklist

Run these commands to confirm the environment is ready:

```bash
# Perl version (≥ 5.26)
perl -v | grep version

# All Perl modules loadable
perl -I lib -e '
    use Glib;
    use Gtk3;
    use Glib::Object::Introspection;
    Glib::Object::Introspection->setup(
        basename => "GtkSource", version => "4", package => "Gtk3::SourceView",
    );
    use Proc::ProcessTable;
    use Net::DNS;
    use IO::Socket::SSL;
    use Text::Diff;
    use YAML::XS;
    use JSON::MaybeXS;
    use Perl::Tidy;
    use Perl::Critic;
    print "All modules OK\n";
'

# VTE terminal widget (GObject Introspection)
perl -e '
    use Glib::Object::Introspection;
    Glib::Object::Introspection->setup(
        basename => "Vte", version => "2.91", package => "Vte",
    );
    print "VTE OK\n";
'

# Emoji font
fc-match emoji | grep -q Noto && echo "Emoji font OK" || echo "MISSING: noto-fonts-emoji"

# Key commands on PATH
for cmd in perl bash hostname uname df ps ip ss ping systemctl journalctl openssl pod2text; do
    command -v $cmd >/dev/null && printf "%-14s OK\n" "$cmd" || printf "%-14s MISSING\n" "$cmd"
done

# UTF-8 locale
locale | grep -q UTF-8 && echo "Locale OK (UTF-8)" || echo "WARNING: locale is not UTF-8"

# Run test suite
prove -l t/
```
