# Writing Custom BadgerOps Scripts

This guide explains how to create your own sysadmin scripts that integrate with the BadgerOps IDE.

## Quick Start

1. Copy the template: `share/templates/badgerops_module.pl`
2. Save it to `~/.config/badgerops/scripts/your_script.pl`
3. Restart the IDE — your script appears in the **User Scripts** category

## Script Convention

Every BadgerOps script follows a two-function pattern:

```perl
sub run {
    my (%args) = @_;
    # Collect data, return a hashref
    return \%result;
}

sub format_report {
    my ($result) = @_;
    # Format the hashref as a readable string
    return $report;
}
```

### `run(%args)`

- Accepts named arguments (optional parameters for your script)
- Performs all data collection (read files, run commands, parse output)
- Returns a **hashref** with structured results
- Should **never print** — all output goes through `format_report`

### `format_report($result)`

- Accepts the hashref returned by `run()`
- Returns a formatted **string** (the report text)
- Use the box-drawing header convention for consistency:

```perl
my $report = <<"EOF";
╔══════════════════════════════════════════════════════════════╗
║                   YOUR REPORT TITLE                          ║
╚══════════════════════════════════════════════════════════════╝

EOF
```

## Auto-Registration

The IDE automatically discovers scripts in `~/.config/badgerops/scripts/`.

### Metadata Headers

Add these comments at the top of your script file:

```perl
#!/usr/bin/env perl
# Name: My Custom Script
# Description: Brief description of what this script does
```

If omitted, the filename is used as the display name.

### Requirements

- File must have a `.pl` extension
- File must be readable
- Only files in the top-level directory are scanned (no subdirectories)

## Module-Based Scripts

For reusable scripts, create a proper Perl module:

```
lib/BadgerOps/Scripts/MyModule.pm    # Module with run() and format_report()
scripts/my_module.pl               # Thin wrapper that calls the module
```

### Module Pattern

```perl
package BadgerOps::Scripts::MyModule;
use strict;
use warnings;

sub run {
    my (%args) = @_;
    my %result;
    # ... data collection ...
    return \%result;
}

sub format_report {
    my ($result) = @_;
    my $report = "...";
    return $report;
}

1;
```

### Wrapper Script

```perl
#!/usr/bin/env perl
use strict;
use warnings;
use FindBin qw($RealBin);
use lib "$RealBin/../lib";
use BadgerOps::Scripts::MyModule;

my $result = BadgerOps::Scripts::MyModule::run();
print BadgerOps::Scripts::MyModule::format_report($result);
```

### Registering in ScriptRegistry

To add your module to the built-in script list, add an entry to `@SCRIPTS` in
`lib/BadgerOps/ScriptRegistry.pm`:

```perl
['My Module', 'my_module.pl', 'BadgerOps::Scripts::MyModule', 'Description', 'Category'],
```

Available categories: System Info, Log Analysis, User Management, Network,
Security, Containers, Backup & Config.

## Batch Execution

Scripts registered in ScriptRegistry can be run in batch mode via the CLI:

```bash
badgerops-cli batch system_info,disk_usage,my_module
```

For this to work, your module must be loadable and export `run()` and
`format_report()` as package functions.

## Testing Your Script

Create a test file in `t/`:

```perl
#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use FindBin qw($RealBin);
use lib "$RealBin/../lib";

use_ok('BadgerOps::Scripts::MyModule');

my $result = BadgerOps::Scripts::MyModule::run();
is(ref $result, 'HASH', 'run returns hashref');

my $report = BadgerOps::Scripts::MyModule::format_report($result);
ok(length($report) > 0, 'report is non-empty');

done_testing();
```

Run with: `prove -lv t/your_test.t`

## Best Practices

- **Don't shell out unnecessarily** — use Perl builtins when possible
  (e.g., read `/proc/` files directly instead of running `cat`)
- **Handle missing commands gracefully** — check `which` before running
  external tools; return partial results rather than dying
- **Use SKIP blocks in tests** — wrap system-dependent tests in
  `SKIP: { skip 'reason', $count unless $condition; ... }`
- **Keep run() side-effect free** — don't modify system state unless
  that's the explicit purpose of the script
- **Validate arguments** — use `//` defaults for optional parameters

## Example: Complete Custom Script

See the following built-in scripts for reference:

| Script | Module | Features |
|--------|--------|----------|
| `system_info.pl` | `SystemInfo.pm` | Reading `/proc` files |
| `port_scanner.pl` | `PortScanner.pm` | Socket connections, two modes |
| `config_diff.pl` | `ConfigDiff.pm` | File comparison with Text::Diff |
| `bandwidth_monitor.pl` | `BandwidthMonitor.pm` | Rate calculation with interval |
| `docker_monitor.pl` | `DockerMonitor.pm` | External tool availability check |
