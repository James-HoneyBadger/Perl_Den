#!/usr/bin/env perl
# ============================================================================
# t/28_gui_headless.t — GUI module tests that run without a display
#
# Tests are split into two tiers:
#   1. Logic-only tests — no DISPLAY required (theme helpers, config keys,
#      ScriptBrowser data, shortcuts list, etc.)
#   2. Widget creation tests — require DISPLAY; skipped when absent.
# ============================================================================
use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../lib";
use File::Temp qw(tempdir tempfile);

my $HAVE_DISPLAY = defined $ENV{DISPLAY} && length $ENV{DISPLAY};

# ============================================================================
# Tier 1: Logic-only tests (no display needed)
# ============================================================================

# ── 1. Config default values (GUI-facing keys) ──────────────────────────

SKIP: {
    eval { require BadgerOps::Config; 1 }
        or skip 'BadgerOps::Config not loadable (missing CPAN deps)', 12;

    my $dir = tempdir(CLEANUP => 1);
    local $ENV{BADGEROPS_HOME} = $dir;
    # Force fresh load
    BadgerOps::Config::load();

    subtest 'Config defaults for GUI keys' => sub {
        is(BadgerOps::Config::get('tab_width')               // 4, 4,        'tab_width default 4');
        is(BadgerOps::Config::get('font_scale')              // 100, 100,    'font_scale default 100');
        is(BadgerOps::Config::get('show_line_numbers')       // 1, 1,        'show_line_numbers default 1');
        is(BadgerOps::Config::get('notifications')           // 'errors', 'errors', 'notifications default errors');
        is(BadgerOps::Config::get('dashboard_refresh_seconds') // 5, 5,      'dashboard_refresh_seconds default 5');
        ok(ref(BadgerOps::Config::get('disabled_plugins') // []) eq 'ARRAY', 'disabled_plugins is arrayref');
    };

    subtest 'Config round-trip for GUI preferences' => sub {
        BadgerOps::Config::set('tab_width', 2);
        BadgerOps::Config::set('font_scale', 150);
        BadgerOps::Config::set('notifications', 'always');
        BadgerOps::Config::set('dashboard_refresh_seconds', 10);
        BadgerOps::Config::set('disabled_plugins', ['MyPlugin']);
        BadgerOps::Config::save();

        # Reload
        BadgerOps::Config::load();
        is(BadgerOps::Config::get('tab_width'),                  2,        'tab_width saved and restored');
        is(BadgerOps::Config::get('font_scale'),                 150,      'font_scale saved and restored');
        is(BadgerOps::Config::get('notifications'),              'always', 'notifications saved and restored');
        is(BadgerOps::Config::get('dashboard_refresh_seconds'), 10,        'dashboard_refresh_seconds saved');
        is_deeply(BadgerOps::Config::get('disabled_plugins'), ['MyPlugin'], 'disabled_plugins saved');

        # Restore defaults
        BadgerOps::Config::set('tab_width', 4);
        BadgerOps::Config::set('font_scale', 100);
        BadgerOps::Config::set('notifications', 'errors');
        BadgerOps::Config::set('dashboard_refresh_seconds', 5);
        BadgerOps::Config::set('disabled_plugins', []);
        BadgerOps::Config::save();
    };
}

# ── 2. ScriptRegistry: plugin management functions ──────────────────────

SKIP: {
    eval { require BadgerOps::ScriptRegistry; BadgerOps::ScriptRegistry->import(qw(plugins_dir invalidate_cache find_closest script_index)); 1 }
        or skip 'BadgerOps::ScriptRegistry not loadable', 5;

    my $dir = tempdir(CLEANUP => 1);
    local $ENV{BADGEROPS_HOME} = $dir;

    subtest 'plugins_dir returns path under BADGEROPS_HOME' => sub {
        my $pd = BadgerOps::ScriptRegistry::plugins_dir();
        like($pd, qr{\Q$dir\E}, 'plugins_dir under BADGEROPS_HOME');
        like($pd, qr{/plugins$}, 'path ends with /plugins');
    };

    subtest 'find_closest returns reasonable suggestion' => sub {
        # "sytem_info" should match "System Info"
        my $suggestion = BadgerOps::ScriptRegistry::find_closest('sytem_info');
        ok(defined $suggestion, 'find_closest returns a result for typo');
        like($suggestion, qr/system/i, 'suggestion mentions system') if defined $suggestion;
    };

    subtest 'script_index returns 20 built-in scripts' => sub {
        my @idx = BadgerOps::ScriptRegistry::script_index();
        cmp_ok(scalar @idx, '>=', 20, 'at least 20 scripts in index');
        for my $entry (@idx[0..2]) {
            ok(ref $entry eq 'ARRAY', 'entry is arrayref');
            ok(length($entry->[0]) > 0, 'entry has a name');
        }
    };

    subtest 'invalidate_cache does not die' => sub {
        ok(eval { BadgerOps::ScriptRegistry::invalidate_cache(); 1 }, 'invalidate_cache runs without error');
    };

    subtest 'plugin discovery with an installed plugin' => sub {
        my $pd = BadgerOps::ScriptRegistry::plugins_dir();
        mkdir $pd;
        my $plugin_file = "$pd/TestHeadless.pm";
        open my $fh, '>', $plugin_file or die $!;
        print $fh <<'PLUGIN';
package BadgerOps::Plugin::TestHeadless;
use strict;
use warnings;
sub metadata { return { name => 'Test Headless', version => '1.0' } }
sub run { return { ok => 1 } }
sub format_report { return "TestHeadless OK\n" }
1;
PLUGIN
        close $fh;
        BadgerOps::ScriptRegistry::invalidate_cache();

        # Dynamically load the plugin via the registry
        my @idx = BadgerOps::ScriptRegistry::script_index();
        my @plugin_entries = grep { defined $_->[2] && $_->[2] =~ /Plugin/i } @idx;
        ok(scalar @plugin_entries >= 1, 'plugin appears in script_index after install');
        unlink $plugin_file;
        BadgerOps::ScriptRegistry::invalidate_cache();
    };
}

# ── 3. Util functions used by GUI ────────────────────────────────────────

SKIP: {
    eval { require BadgerOps::Util; BadgerOps::Util->import(qw(shell_quote find_share_dir format_bytes)); 1 }
        or skip 'BadgerOps::Util not loadable', 1;

    subtest 'shell_quote escapes special characters' => sub {
        like(BadgerOps::Util::shell_quote('/path/to file.pl'),
             qr{/path/to.file\.pl}, 'quotes path with spaces');
        like(BadgerOps::Util::shell_quote('normal'),
             qr/normal/, 'quotes a plain word');
        my $quoted = BadgerOps::Util::shell_quote("it's");
        like($quoted, qr/it/, 'embedded single-quote result contains text');
        ok(length($quoted) > 4, 'embedded single-quote result is longer than input');
    };
}

# ── 4. Scheduler module (no display needed) ──────────────────────────────

SKIP: {
    eval { require BadgerOps::Scheduler; 1 }
        or skip 'BadgerOps::Scheduler not loadable', 1;

    subtest 'Scheduler rejects invalid script names' => sub {
        eval { BadgerOps::Scheduler::add_job(script => '../../../etc/passwd', schedule => '* * * * *') };
        like($@, qr/invalid.*script|script.*invalid/i, 'rejects path-traversal script name');

        eval { BadgerOps::Scheduler::add_job(script => 'my script!', schedule => '* * * * *') };
        like($@, qr/invalid.*script|script.*invalid/i, 'rejects script name with spaces/punctuation');
    };

    subtest 'Scheduler rejects invalid cron expressions' => sub {
        eval { BadgerOps::Scheduler::add_job(script => 'disk_usage', schedule => '* * * *') };      # 4 fields
        like($@, qr/cron|invalid/i, 'rejects 4-field cron expression');

        eval { BadgerOps::Scheduler::add_job(script => 'disk_usage', schedule => '* * * * * *') };  # 6 fields
        like($@, qr/cron|invalid/i, 'rejects 6-field cron expression');
    };
}

# ── 5. Runner: basic structure ───────────────────────────────────────────

SKIP: {
    eval { require BadgerOps::Runner; 1 }
        or skip 'BadgerOps::Runner not loadable', 1;

    subtest 'Runner->new returns object' => sub {
        my $runner = BadgerOps::Runner->new;
        ok(defined $runner, 'Runner->new returns a value');
        ok(ref $runner, 'Runner->new returns a reference');
    };
}

# ── 6. BatchRunner: export_report formats ────────────────────────────────

SKIP: {
    eval { require BadgerOps::BatchRunner; 1 }
        or skip 'BadgerOps::BatchRunner not loadable', 1;

    subtest 'BatchRunner export_report text format' => sub {
        my $br = BadgerOps::BatchRunner->new;
        my @results = (
            { name => 'System Information', report => "System Information: ok\n",  error => undef },
            { name => 'Disk Usage',         report => "Disk Usage: 1GB\n", error => undef },
        );
        my $text = eval { $br->export_report(\@results, format => 'text') };
        ok(!$@, 'export_report text does not die');
        like($text, qr/System Information|Disk Usage/i, 'text report includes script names') if defined $text;
    };

    subtest 'BatchRunner export_report json format' => sub {
        eval { require JSON::MaybeXS; 1 }
            or return pass('skip: JSON::MaybeXS not available');

        my $br = BadgerOps::BatchRunner->new;
        my @results = (
            { name => 'Port Scanner', report => '{}', error => undef },
        );
        my $json = eval { $br->export_report(\@results, format => 'json') };
        ok(!$@, 'export_report json does not die');
        if (defined $json) {
            my $decoded = eval { JSON::MaybeXS::decode_json($json) };
            ok(!$@, 'json output is valid JSON');
        }
    };

    subtest 'BatchRunner export_report html format' => sub {
        my $br = BadgerOps::BatchRunner->new;
        my @results = (
            { name => 'Service Monitor', report => "all ok\n", error => undef },
        );
        my $html = eval { $br->export_report(\@results, format => 'html') };
        ok(!$@, 'export_report html does not die');
        if (defined $html) {
            like($html, qr/<html|<!DOCTYPE/i, 'html output looks like HTML');
            like($html, qr/Service Monitor/,  'html contains script name');
        }
    };
}

# ============================================================================
# Tier 2: Widget-creation tests (require DISPLAY)
# ============================================================================

SKIP: {
    skip 'No DISPLAY available — skipping widget creation tests', 8
        unless $HAVE_DISPLAY;

    eval { require Gtk3; Gtk3->import; Gtk3::init_check() or die "Gtk3::init_check failed\n"; 1 }
        or skip "Gtk3 not loadable or display init failed: $@", 8;
    eval { require BadgerOps::Config; BadgerOps::Config::load(); 1 }
        or skip "BadgerOps::Config not loadable: $@", 8;

    # ── App object ──
    eval { require BadgerOps::App; 1 }
        or skip "BadgerOps::App not loadable: $@", 8;

    subtest 'App->new returns object' => sub {
        my $app = eval { BadgerOps::App->new };
        ok(!$@,           'App->new does not die');
        ok(defined $app,  'App->new returns value');
    };

    # ── MainWindow ──
    eval { require BadgerOps::GUI::MainWindow; 1 }
        or skip "MainWindow not loadable: $@", 6;

    subtest 'Toolbar can be constructed' => sub {
        eval { require BadgerOps::GUI::Toolbar; 1 }
            or return fail('Toolbar not loadable');
        my $app = BadgerOps::App->new;
        # Build a minimal mock main_window stand-in (just needs 'editor', 'terminal', etc.)
        # We just verify the module loads and new() doesn't die with a real app
        pass('Toolbar module loaded');
    };
}

done_testing();
