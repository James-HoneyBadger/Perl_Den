# Changelog

All notable changes to Perl Den are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

---

## [2.1.2] — 2026-07-16

### Added

- `install_perlden_desktop.sh` to install a freedesktop application launcher for Perl Den into the DE menu
- `share/applications/perlden.desktop` as the desktop entry template used by the installer
- README installation guidance for the desktop-menu install flow

### Changed

- Desktop launcher now installs the Perl Den icon into the local hicolor icon theme so it appears in application menus

---

## [2.1.0] — 2026-05-19

### Added

**Security Hardening**
- `BatchRunner::export_report()` now HTML-escapes all script output before embedding in the HTML template, preventing XSS in generated reports
- `Runner.pm` writes a timestamped audit entry to `~/.config/perlden/audit.log` whenever a script is executed with `as_root => 1`
- `NetworkDiag.pm` replaces deprecated `gethostbyname()` with `Socket::getaddrinfo()` and `getnameinfo()` for correct IPv6 and modern DNS resolution
- `NetworkDiag.pm` ping-host regex hardened: rejects consecutive dots, leading/trailing hyphens, and other invalid hostname patterns
- `SystemInfo.pm` guards all KB→MB divisions against undefined or zero-length `/proc/meminfo` values

**Scheduler Improvements**
- `Scheduler::_validate_cron_expr()` now enforces numeric ranges: minute (0–59), hour (0–23), day-of-month (1–31), month (1–12), day-of-week (0–7), and `*/N` step syntax
- New `disable_job($script)` / `enable_job($script)` methods add/remove a `# DISABLED:` prefix in the crontab without losing the original entry
- `list_jobs()` result now includes an `enabled` boolean field
- `perlden-cli schedule enable <script>` / `schedule disable <script>` subcommands

**CLI Enhancements**
- `--dry-run` flag for `perlden-cli batch`: resolves and prints all script names/paths without executing
- "Did you mean?" now calls `find_top_n($query, 3)` and shows up to three ranked suggestions with similarity scores
- `perlden-cli list` output includes an *enabled* status column for scheduled scripts

**TUI Enhancements**
- Paginated script menu (default 20 per page) with `n`/`p` keys and a `Page X/Y` indicator
- `/` search uses `find_top_n()` trigram matching with substring fallback; `c` clears the filter
- Highlighted entry shows a one-line description from `ScriptRegistry` metadata in the status row
- `h` key opens an in-memory execution history of the last 10 runs (script, exit code, timestamp)

**Parallel & Streaming Execution**
- `BatchRunner::run_batch_parallel($jobs, workers => N)`: fork-based worker pool with a `Storable`-encoded result pipe; enforces a per-job deadline via `alarm` + SIGKILL
- `Runner::run_stream($script, on_line => \&cb)`: streams output line-by-line to a callback instead of buffering; supports `timeout` option and SIGKILL escalation
- `BatchRunner::run_batch()` timeout: each job gets a per-entry `timeout_seconds`; timed-out jobs are recorded with `exit_code => -1` and `timed_out => 1`

**Desktop Notification Fallback Chain**
- `BatchRunner::_send_notification()` tries `notify-send` → D-Bus via `gdbus` → `dbus-send` → `warn` to stderr; logs which method succeeded in the BatchRunner result
- Controlled by the existing `notifications` config key

**ServiceMonitor JSON Parsing**
- `ServiceMonitor.pm` uses `systemctl list-units --json=short` + `JSON::MaybeXS` on systemd ≥ 247
- Transparent text-parsing fallback on older systemd; `_merge_enabled()` helper aligns `is-enabled` results between both paths

**Git Status in IDE Sidebar**
- `ScriptBrowser` header area now shows `⎇ branch  N modified` in green (clean) or amber (dirty) below the "SCRIPT LIBRARY" title
- Badge is updated immediately when the main window opens or saves a file (`MainWindow::_update_git_status`) and refreshes passively every 5 seconds via a `Glib::Timeout`
- Label is hidden entirely when the open directory is not a git repository

**Dashboard Hardware Metrics**
- New "Hardware" card row in `Dashboard.pm` with **CPU Temp**, **GPU Temp**, and **GPU Util** cards
- CPU temperature read from `/sys/class/thermal/thermal_zone*/temp` (filtered to `x86_pkg_temp`, `acpitz`, `cpu` zone types); reports highest reading
- NVIDIA GPU: `nvidia-smi --query-gpu=temperature.gpu,utilization.gpu`
- AMD GPU fallback: `rocm-smi --showtemp`
- All three values degrade gracefully to "N/A" if sensors or tools are unavailable

**Installer**
- `install_perlden.sh --no-gui` skips GTK3/GtkSourceView dependency installation and GUI make targets
- `install_perlden.sh --uninstall` removes all installed symlinks from the prefix and optionally removes `~/.config/perlden/` after confirmation

**Test Coverage**
- `t/29_new_features.t`: 9 passing subtests covering `find_top_n()`, Scheduler enable/disable, BatchRunner timeout, parallel batch, and `Runner::run_stream`

### Fixed

- `BatchRunner::format_report()` now returns an explicit `"ERROR: no format_report for <name>"` string instead of an empty string when a result has no formatter
- `Runner.pm` error messages now include the command name, PID, and `errno` string (previously just "exec failed")
- Scheduler `enable_job` bug: second regex match inside the `if` condition clobbered `$1` from the first match before it was used; fixed by capturing to a local variable first

### Changed

- `ScriptRegistry::find_top_n($query, $n)` added to `@EXPORT_OK`; used throughout CLI and TUI for consistent ranked suggestions
- `perlden-tui` history list persists for the lifetime of the TUI session (in-memory; not written to disk)
- All `GUI/*.pm` `apply_settings()` methods now refresh Hardware and Git-status labels in addition to existing card colours

---

## [2.0.0] — 2026-04-30

### Added

**Plugin System**
- Drop-in plugin support: place `.pm` files in `~/.config/perlden/plugins/`
- Plugins are auto-discovered at startup with no registration required
- Plugin API: `run()`, `format_report()`, `metadata()` (optional), `configure()` (optional)
- Comment-header fallback (`# Name:`, `# Description:`, `# Category:`) for minimal plugins
- `perlden-cli plugin list|info|enable|disable` subcommands
- `disabled_plugins` config key to hide plugins without deleting them
- Plugins appear in the GUI sidebar, CLI list, and TUI menu alongside built-ins
- See [docs/PLUGINS.md](docs/PLUGINS.md) for the full plugin authoring guide

**Script Scheduling**
- New `PerlDen::Scheduler` module — add/list/remove crontab entries for Perl Den scripts
- `perlden-cli schedule list|add|remove` subcommands
- Input validation (script name regex, 5-field cron expression check) prevents injection

**Batch Export**
- `BatchRunner::export_report($results, format => 'html|json|text')` method
- HTML export: self-contained document with inline dark-theme CSS
- JSON export: structured output via `JSON::MaybeXS` with timestamp
- CLI flag: `perlden-cli batch --export=html|json <scripts>`

**Desktop Notifications**
- `notify-send` integration after batch runs (non-blocking, best-effort)
- Controlled by new `notifications` config key: `always`, `errors` (default), `off`

**TUI Search/Filter**
- Press `/` in the script menu to enter a live search query
- Filter matches script name or description (case-insensitive)
- Press `c` to clear the filter; count shown in the main menu
- Script category shown as a dim column in the script list

**CLI Improvements**
- "Did you mean?" suggestion when an unknown script name is given (trigram similarity)
- `perlden-cli batch --export=FORMAT` flag for structured output
- `perlden-cli plugin` and `perlden-cli schedule` subcommand groups
- Help text updated to cover all new commands

**Error Handling**
- `Try::Tiny` added throughout: `App.pm`, `BatchRunner.pm`, `Runner.pm`
- `Runner.pm`: pipe creation and `open3` call wrapped in `try/catch`
- `Git.pm`: `_run_git()` emits debug warnings on non-zero exit / unexpected errors when `PERLDEN_DEBUG=1`

**Timeout Protection**
- `alarm()`-based run-timeout guard in `NetworkDiag`, `PortScanner`,
  `BandwidthMonitor`, and `SSLChecker`
- `run_timeout` exposed in `metadata()` for each of those four scripts
- `run_sync()` in `Runner.pm` supports `{ timeout => $seconds }` option

**Configuration (schema v4)**
- New keys: `notifications` (string), `disabled_plugins` (array), `dashboard_refresh_seconds` (integer)
- Automatic migration from v3 configs sets sensible defaults for all three keys
- `PERLDEN_HOME` environment variable overrides `~/.config/perlden/` in both `Config.pm` and `ScriptRegistry.pm`

**Script Discovery**
- `ScriptRegistry` rewritten: auto-discovers built-in scripts by calling `metadata()` on each
- User scripts loaded from `~/.config/perlden/scripts/*.pl` via comment-header parsing
- `find_closest($query)` — trigram similarity for "did you mean?" (threshold 0.4)
- New exports: `find_closest`, `plugins_dir`, `invalidate_cache`
- All 20 built-in `Scripts/*.pm` modules now export `metadata()`

**POD Documentation**
- All 20 `Scripts/*.pm` modules gain a `=head1 RETURNS` section documenting the `run()` hashref
- Five scripts gain full `=head1 SYNOPSIS` and `=head1 EXPORTED FUNCTIONS` sections
- `BatchRunner.pm` gains a `=head1 METHODS` section
- `Scheduler.pm` has inline function-level POD
- New [docs/PLUGINS.md](docs/PLUGINS.md) plugin authoring guide
- New [docs/KEYBINDINGS.md](docs/KEYBINDINGS.md) keyboard shortcut reference

**Testing & CI**
- `t/25_plugin_system.t` — 9 test groups: discovery, metadata, comment headers,
  API validation, security rejection, enable/disable
- `t/26_scheduler.t` — 10 test groups with mocked crontab (no real system changes)
- `t/27_mocked_system.t` — 20 tests for system-command-dependent scripts
  (ServiceMonitor, DockerMonitor, PortScanner, NetworkDiag, BandwidthMonitor,
  FirewallAuditor, SystemdAnalyzer, PackageAuditor) without a live Linux system
- `t/28_gui_headless.t` — 30 tests: Config round-trips for GUI keys, ScriptRegistry
  plugin install/discovery, Util::shell_quote, Scheduler input validation,
  Runner and BatchRunner construction; all skipped gracefully without CPAN deps
- `.github/workflows/test.yml` — matrix: Perl 5.28/5.36/5.38, cpanm caching,
  advisory `Perl::Critic` lint job

### Fixed

- `Dialogs.pm` Plugin Manager save loop: `iter_next($iter)` returns bool and
  modifies `$iter` in-place in Gtk3-Perl; the assignment `$iter = ... ? $iter : undef`
  was semantically wrong. Replaced with `last unless $plugin_store->iter_next($iter)`
- `Dashboard.pm` config key mismatch: `dashboard_interval` → `dashboard_refresh_seconds`

### Changed

- Minimum Perl version bumped from 5.16 to **5.28**
- `PerlDen::Util::run_command($string)` now emits a `Carp::carp` deprecation
  warning when `PERLDEN_DEBUG=1` or `PERLDEN_WARN_DEPRECATED=1` is set
  (will be removed in v3.0; use the list-form API instead)
- `cpanfile` now declares `requires 'perl', '5.028'` and adds `Try::Tiny`
- `Makefile.PL` sets `MIN_PERL_VERSION => '5.028'` and adds `Try::Tiny` to `PREREQ_PM`
- All module `$VERSION` strings bumped to `'2.00'`

### Deprecated

- `PerlDen::Util::run_command($string)` — single-string (shell-form) invocation is
  deprecated; use the list-form `run_command(@list)` instead

---

## [1.0.0] — 2025-01-15

### Added

- Initial release: 20 bundled sysadmin scripts
- GTK3 GUI with syntax-highlighted editor (GtkSourceView)
- CLI (`perlden-cli`) with `list`, `run`, `batch`, `ide` subcommands
- TUI (`perlden-tui`) with numbered script menu
- YAML-based config with schema migration
- Async script runner with Glib IO watches
- Sync runner with `IPC::Open3` and `IO::Select` deadlock avoidance
- `BatchRunner` for sequential multi-script runs
- Git status integration (`PerlDen::Git`)
- 12 tutorial POD files in `share/tutorials/`
- 8 script templates in `share/templates/`
- Dark/light/high-contrast/VSCode themes in `share/themes/`

---

[2.1.0]: https://github.com/James-HoneyBadger/Perl Den/compare/v2.0.0...v2.1.0
[2.0.0]: https://github.com/James-HoneyBadger/Perl Den/compare/v1.0.0...v2.0.0
[1.0.0]: https://github.com/James-HoneyBadger/Perl Den/releases/tag/v1.0.0
