# Changelog

All notable changes to BadgerOps are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

---

## [2.0.0] — 2026-04-30

### Added

**Plugin System**
- Drop-in plugin support: place `.pm` files in `~/.config/badgerops/plugins/`
- Plugins are auto-discovered at startup with no registration required
- Plugin API: `run()`, `format_report()`, `metadata()` (optional), `configure()` (optional)
- Comment-header fallback (`# Name:`, `# Description:`, `# Category:`) for minimal plugins
- `badgerops-cli plugin list|info|enable|disable` subcommands
- `disabled_plugins` config key to hide plugins without deleting them
- Plugins appear in the GUI sidebar, CLI list, and TUI menu alongside built-ins
- See [docs/PLUGINS.md](docs/PLUGINS.md) for the full plugin authoring guide

**Script Scheduling**
- New `BadgerOps::Scheduler` module — add/list/remove crontab entries for BadgerOps scripts
- `badgerops-cli schedule list|add|remove` subcommands
- Input validation (script name regex, 5-field cron expression check) prevents injection

**Batch Export**
- `BatchRunner::export_report($results, format => 'html|json|text')` method
- HTML export: self-contained document with inline dark-theme CSS
- JSON export: structured output via `JSON::MaybeXS` with timestamp
- CLI flag: `badgerops-cli batch --export=html|json <scripts>`

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
- `badgerops-cli batch --export=FORMAT` flag for structured output
- `badgerops-cli plugin` and `badgerops-cli schedule` subcommand groups
- Help text updated to cover all new commands

**Error Handling**
- `Try::Tiny` added throughout: `App.pm`, `BatchRunner.pm`, `Runner.pm`
- `Runner.pm`: pipe creation and `open3` call wrapped in `try/catch`
- `Git.pm`: `_run_git()` emits debug warnings on non-zero exit / unexpected errors when `BADGEROPS_DEBUG=1`

**Timeout Protection**
- `alarm()`-based run-timeout guard in `NetworkDiag`, `PortScanner`,
  `BandwidthMonitor`, and `SSLChecker`
- `run_timeout` exposed in `metadata()` for each of those four scripts
- `run_sync()` in `Runner.pm` supports `{ timeout => $seconds }` option

**Configuration (schema v4)**
- New keys: `notifications` (string), `disabled_plugins` (array), `dashboard_refresh_seconds` (integer)
- Automatic migration from v3 configs sets sensible defaults for all three keys
- `BADGEROPS_HOME` environment variable overrides `~/.config/badgerops/` in both `Config.pm` and `ScriptRegistry.pm`

**Script Discovery**
- `ScriptRegistry` rewritten: auto-discovers built-in scripts by calling `metadata()` on each
- User scripts loaded from `~/.config/badgerops/scripts/*.pl` via comment-header parsing
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
- `BadgerOps::Util::run_command($string)` now emits a `Carp::carp` deprecation
  warning when `BADGEROPS_DEBUG=1` or `BADGEROPS_WARN_DEPRECATED=1` is set
  (will be removed in v3.0; use the list-form API instead)
- `cpanfile` now declares `requires 'perl', '5.028'` and adds `Try::Tiny`
- `Makefile.PL` sets `MIN_PERL_VERSION => '5.028'` and adds `Try::Tiny` to `PREREQ_PM`
- All module `$VERSION` strings bumped to `'2.00'`

### Deprecated

- `BadgerOps::Util::run_command($string)` — single-string (shell-form) invocation is
  deprecated; use the list-form `run_command(@list)` instead

---

## [1.0.0] — 2025-01-15

### Added

- Initial release: 20 bundled sysadmin scripts
- GTK3 GUI with syntax-highlighted editor (GtkSourceView)
- CLI (`badgerops-cli`) with `list`, `run`, `batch`, `ide` subcommands
- TUI (`badgerops-tui`) with numbered script menu
- YAML-based config with schema migration
- Async script runner with Glib IO watches
- Sync runner with `IPC::Open3` and `IO::Select` deadlock avoidance
- `BatchRunner` for sequential multi-script runs
- Git status integration (`BadgerOps::Git`)
- 12 tutorial POD files in `share/tutorials/`
- 8 script templates in `share/templates/`
- Dark/light/high-contrast/VSCode themes in `share/themes/`

---

[2.0.0]: https://github.com/James-HoneyBadger/BadgerOps/compare/v1.0.0...v2.0.0
[1.0.0]: https://github.com/James-HoneyBadger/BadgerOps/releases/tag/v1.0.0
