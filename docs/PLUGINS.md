# BadgerOps Plugin System

BadgerOps v2.0 supports user-installable plugins that appear alongside the
20 built-in scripts in every interface (GUI, CLI, TUI).

---

## Table of Contents

1. [Installing a Plugin](#installing-a-plugin)
2. [Plugin API](#plugin-api)
3. [Minimal Example](#minimal-example)
4. [Full Example with metadata()](#full-example-with-metadata)
5. [Disabling and Enabling Plugins](#disabling-and-enabling-plugins)
6. [Managing Plugins from the CLI](#managing-plugins-from-the-cli)
7. [Configuration](#configuration)
8. [Security Notes](#security-notes)

---

## Installing a Plugin

Drop a `.pm` file into:

```
~/.config/badgerops/plugins/
```

> **Custom base directory**: If the `BADGEROPS_HOME` environment variable is
> set, plugins live in `$BADGEROPS_HOME/plugins/` instead.

BadgerOps discovers plugins automatically on startup — no registration step
is needed.  Restart the application (or press **Reload** in the GUI) for
new plugins to appear.

---

## Plugin API

A plugin is a plain Perl module (`.pm`) that exports three functions:

| Function | Required | Signature | Purpose |
|---|---|---|---|
| `run(%args)` | **yes** | `→ \%result` | Execute the plugin's logic |
| `format_report($result)` | **yes** | `→ $string` | Format results as text |
| `metadata()` | recommended | `→ \%meta` | Provide display metadata |
| `configure($config_hr)` | optional | `→ 1` | Called with user config |

### `run(%args)`

Receives any keyword arguments the caller passes (the GUI/CLI may pass
`run_timeout`).  Must return a **hashref**.  The hashref is opaque to
BadgerOps — you define its structure and consume it in `format_report`.

### `format_report($result)`

Receives the hashref returned by `run()`.  Must return a **plain string**
suitable for display in a terminal or the GUI output pane.

### `metadata()` — recommended

Returns a hashref with display information:

```perl
sub metadata {
    return {
        name        => 'My Plugin',          # display name (required)
        filename    => 'my_plugin.pl',       # associated script name
        description => 'Does something cool',
        category    => 'Plugins',            # shown in category view
        icon        => 'extension-symbolic', # GTK icon name
        emoji       => '🔌',
        run_timeout => 30,                   # optional, seconds
    };
}
```

If `metadata()` is absent, BadgerOps falls back to reading comment headers
from the top 30 lines of the file:

```perl
# Name: My Plugin
# Description: Does something cool
# Category: Security
```

---

## Minimal Example

```perl
package BadgerOps::Plugin::HelloWorld;
use strict;
use warnings;

# Name: Hello World
# Description: Greet the user
# Category: Plugins

sub run {
    my (%args) = @_;
    return { message => 'Hello from BadgerOps!' };
}

sub format_report {
    my ($result) = @_;
    return "$result->{message}\n";
}

1;
```

Save as `~/.config/badgerops/plugins/HelloWorld.pm`.

---

## Full Example with metadata()

```perl
package BadgerOps::Plugin::DiskQuota;
use strict;
use warnings;

our $VERSION = '1.0';

sub metadata {
    return {
        name        => 'Disk Quota Monitor',
        filename    => 'disk_quota.pl',
        description => 'Check disk quota usage for all users',
        category    => 'System Info',
        icon        => 'drive-harddisk-symbolic',
        emoji       => '💾',
        run_timeout => 15,
    };
}

sub run {
    my (%args) = @_;
    my @quotas;

    if (open my $fh, '-|', 'repquota', '-a') {
        while (<$fh>) {
            next unless /^(\w+)\s+\S+\s+(\d+)\s+(\d+)/;
            push @quotas, { user => $1, used_kb => $2, soft => $3 };
        }
        close $fh;
    }

    return {
        quotas => \@quotas,
        error  => @quotas ? undef : 'repquota not available or no quotas set',
    };
}

sub format_report {
    my ($result) = @_;
    return "ERROR: $result->{error}\n" if $result->{error};

    my $out = "Disk Quota Report\n" . '=' x 40 . "\n";
    for my $q (@{ $result->{quotas} }) {
        $out .= sprintf "  %-20s %8d KB\n", $q->{user}, $q->{used_kb};
    }
    return $out;
}

1;
```

---

## Disabling and Enabling Plugins

### Via CLI

```bash
# Disable a plugin (keeps the file, just hides it)
badgerops-cli plugin disable DiskQuota

# Re-enable it
badgerops-cli plugin enable DiskQuota

# List all plugins and their status
badgerops-cli plugin list
```

### Via config file

Add the plugin base name (without `.pm`) to `disabled_plugins` in
`~/.config/badgerops/config.yml`:

```yaml
disabled_plugins:
  - DiskQuota
  - HelloWorld
```

---

## Managing Plugins from the CLI

```bash
# List installed plugins
badgerops-cli plugin list

# Show metadata for a specific plugin
badgerops-cli plugin info DiskQuota

# Run a plugin as you would any script
badgerops-cli run DiskQuota

# Include a plugin in a batch run
badgerops-cli batch system_info,DiskQuota,disk_usage

# Export the batch as HTML
badgerops-cli batch --export=html system_info,DiskQuota > report.html
```

---

## Configuration

Plugins can read the shared BadgerOps config by importing `BadgerOps::Config`:

```perl
use BadgerOps::Config;
BadgerOps::Config::load();
my $timeout = BadgerOps::Config::get('script_timeout') // 30;
```

You can also store plugin-specific settings in the config under your own
namespace key (prefix with your plugin name to avoid conflicts):

```yaml
# ~/.config/badgerops/config.yml
DiskQuota_warn_threshold: 80
```

The optional `configure($config_hr)` hook is called with the full config
hashref during plugin initialisation, before the first `run()` call.

---

## Security Notes

- Plugin files are loaded with `require` — they execute arbitrary Perl code.
  **Only install plugins from sources you trust.**
- BadgerOps validates plugin filenames against `/\A[A-Za-z0-9_]+\.pm\z/` and
  rejects files whose names contain path separators or shell metacharacters.
- Plugins lacking a `run()` function are silently skipped.
- Disabled plugins are never loaded into memory; their files are ignored
  entirely until explicitly re-enabled.
