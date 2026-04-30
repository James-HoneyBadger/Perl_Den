# HB Perl IDE

**Linux Sysadmin Toolkit & Perl Development Environment**

HB Perl is an integrated development environment for writing, running, and
managing Perl scripts on Linux — with a focus on system administration.  It
bundles 20 ready-to-run sysadmin scripts, a GTK3 code editor, an embedded
terminal, a live system dashboard, 12 Perl tutorials, and a library of
script templates.

Three interfaces are provided:

- **GUI** (`hb_gui`) — GTK3 IDE with tabbed editor, integrated terminal, script browser, and dashboard
- **CLI** (`hb_cli`) — run any toolkit script from the command line
- **TUI** (`hb_tui`) — interactive terminal menu for browsing and running scripts

---

## Features

### Code Editor
- GtkSourceView-powered tabbed editor with Perl syntax highlighting
- Find / Find & Replace with regex support
- Syntax checking (`perl -c`), code formatting (Perl::Tidy), linting (Perl::Critic)
- POD preview, auto-indent, configurable font and colour scheme

### Toolkit Scripts (20)
| Category          | Scripts                                                     |
|-------------------|-------------------------------------------------------------|
| System Info       | SystemInfo, DiskUsage, ProcessManager, ServiceMonitor, PackageAuditor, SystemdAnalyzer |
| Log Analysis      | LogAnalyzer, FailedLoginDetector                            |
| User Management   | UserAudit, CronManager                                      |
| Network           | NetworkDiag, PortScanner, SSLChecker, BandwidthMonitor      |
| Security          | FilePermissions, FirewallAuditor                            |
| Containers        | DockerMonitor                                               |
| Backup & Config   | BackupManager, ConfigDiff, DuplicateFinder                  |

Every script has a Perl module (`lib/HBPerl/Scripts/`) with a uniform
`run(%args)` → `\%result` and `format_report(\%result)` → `$string` API,
plus a standalone runner (`scripts/*.pl`).

### Dashboard
Real-time system overview: hostname, kernel, uptime, load average, CPU,
memory, swap, disk usage, and top processes — auto-refreshing every 5 s.

### Templates & Tutorials
- 8 script templates (CLI, file processor, log parser, OOP module, HBPerl module, sysadmin, test suite, web client)
- 12 progressive Perl tutorials covering fundamentals through security hardening

### Themes
5 GTK CSS themes: dark, light, high-contrast, VS Code dark, and VS Code light.

---

## Quick Start

```bash
# Clone the repository
git clone https://github.com/James-HoneyBadger/HB_Perl.git
cd HB_Perl

# Install system dependencies (Arch Linux)
sudo pacman -S perl gtk3 vte3 gtksourceview3 gobject-introspection \
    openssl polkit iproute2 inetutils procps-ng cronie iputils

# Install Unicode fonts
sudo pacman -S noto-fonts noto-fonts-emoji noto-fonts-cjk noto-fonts-extra ttf-freefont
fc-cache -f

# Install Perl module dependencies
cpanm --installdeps .

# Launch
./hb_gui                          # GTK3 IDE
./hb_cli list                     # List all toolkit scripts
./hb_cli system_info              # Run a script
./hb_tui                          # Interactive terminal UI
```

For Debian/Ubuntu and other distros, see [docs/ENVIRONMENT.md](docs/ENVIRONMENT.md).

---

## Installation

### Option A: Run from source (recommended)

```bash
./hb_gui            # GUI IDE
./hb_cli list       # CLI
./hb_tui            # TUI
```

### Option B: Install as shell commands

```bash
# Symlinks hb_perl, hb_cli, hb_tui, hb_gui into ~/.local/bin
./install_hb_perl_command.sh --user

# Now available globally:
hb_cli system_info
hb_gui
```

---

## Project Structure

```
HB_Perl/
├── bin/                         # Perl entry points
│   ├── hb_perl_cli              #   CLI dispatcher
│   ├── hb_perl_tui              #   Terminal UI
│   └── hb_perl_ide              #   GTK3 IDE launcher
├── lib/HBPerl/                  # Core modules
│   ├── App.pm                   #   GUI application controller
│   ├── BatchRunner.pm           #   Batch script execution + HTML/JSON export
│   ├── Config.pm                #   YAML config, schema v4, HBPERL_HOME support
│   ├── Git.pm                   #   Git repository status with caching
│   ├── Runner.pm                #   Non-blocking / sync script execution
│   ├── ScriptRegistry.pm        #   Auto-discovery: built-ins + plugins + user scripts
│   ├── Scheduler.pm             #   Crontab-based job scheduling
│   ├── Util.pm                  #   Shared utilities
│   ├── GUI/                     #   GTK3 GUI components
│   └── Scripts/                 #   20 sysadmin tool modules
├── scripts/                     # Standalone .pl script runners
├── share/
│   ├── icons/                   # Application icons (SVG + PNG)
│   ├── templates/               # New-file templates (8)
│   ├── themes/                  # GTK CSS themes (5)
│   └── tutorials/               # Perl tutorials (12 POD files)
├── t/                           # Test suite (37 files)
│   ├── unit/                    #   Unit tests
│   ├── integration/             #   Integration tests
│   └── fixtures/                #   Test data files
├── docs/
│   ├── ENVIRONMENT.md           # Distro-specific install guide
│   ├── CUSTOM_SCRIPTS.md        # Guide for custom scripts and user scripts
│   ├── PLUGINS.md               # Plugin authoring guide
│   └── KEYBINDINGS.md           # GUI keyboard shortcut reference
├── CHANGELOG.md                 # Full change history
├── hb_gui / hb_cli / hb_tui    # Shell wrappers
├── hb_perl                      # Shell wrapper → hb_perl_cli
├── _hb_env.sh                   # Environment bootstrap (PATH, PERL5LIB)
├── install_hb_perl_command.sh   # Install/uninstall shell commands
├── .github/workflows/test.yml   # CI: Perl 5.28/5.36/5.38 matrix
├── cpanfile                     # CPAN dependency declaration
├── Makefile.PL                  # ExtUtils::MakeMaker build
└── LICENSE                      # MIT License
```

---

## Dependencies

**Perl:** 5.28 or later  
**System:** GTK3, VTE (≥ 2.91), GtkSourceView 3, systemd, iproute2, OpenSSL, libnotify  
**CPAN:** Glib, Gtk3, YAML::XS, JSON::MaybeXS, Try::Tiny, File::HomeDir,
  IO::Socket::SSL, Net::DNS, Proc::ProcessTable, Text::Diff

See [docs/ENVIRONMENT.md](docs/ENVIRONMENT.md) for complete specifications
with exact versions and distro-specific install commands.

---

## Running Tests

```bash
prove -l t/
```

37 test files covering all 20 script modules, configuration, utilities,
the script registry, plugin system, scheduler, batch runner, git
integration, and the execution runner.  CI runs on Perl 5.28, 5.36, and
5.38 via GitHub Actions.

---

## License

MIT License — see [LICENSE](LICENSE).

---

## Author

James Temple — james@amiga-fan.net

© 2026 Honey Badger Universe — [https://github.com/James-HoneyBadger/HB_Perl](https://github.com/James-HoneyBadger/HB_Perl)
