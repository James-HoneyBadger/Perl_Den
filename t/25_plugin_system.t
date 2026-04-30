#!/usr/bin/perl
# ============================================================================
# t/25_plugin_system.t - Plugin loader tests
# ============================================================================
use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use File::Spec;
use FindBin qw($RealBin);
use lib File::Spec->catdir($RealBin, '..', 'lib');

# ── Helpers ──────────────────────────────────────────────────────────────────

# Write a minimal valid plugin .pm file into a dir
sub write_plugin {
    my ($dir, $basename, %opts) = @_;
    my $name    = $opts{name}        // 'Test Plugin';
    my $desc    = $opts{desc}        // 'A test plugin';
    my $cat     = $opts{category}    // 'Plugins';
    my $has_run = $opts{has_run}     // 1;
    my $has_fmt = $opts{has_fmt}     // 1;
    my $has_meta = $opts{has_meta}   // 1;
    my $extra   = $opts{extra}       // '';

    my $pkg = "BadgerOps::Plugin::$basename";

    my $run_sub  = $has_run  ? "sub run { return { status => 'ok', data => [] } }\n" : '';
    my $fmt_sub  = $has_fmt  ? "sub format_report { return 'Report for $_[1]' }\n"  : '';
    my $meta_sub = $has_meta ? <<"META" : '';
sub metadata {
    return {
        name        => '$name',
        filename    => '${\(lc $basename)}.pl',
        description => '$desc',
        category    => '$cat',
        icon        => 'extension-symbolic',
        emoji       => '🔌',
    };
}
META

    my $content = <<"PM";
package $pkg;
use strict;
use warnings;
our \$VERSION = '0.01';
$meta_sub$run_sub$fmt_sub${extra}1;
PM

    my $path = File::Spec->catfile($dir, "$basename.pm");
    open my $fh, '>', $path or die "Cannot write $path: $!";
    print $fh $content;
    close $fh;
    return $path;
}

# ── Tests ─────────────────────────────────────────────────────────────────────

my $tmpdir = tempdir(CLEANUP => 1);
my $plugins_dir = File::Spec->catdir($tmpdir, 'plugins');
mkdir $plugins_dir or die "mkdir $plugins_dir: $!";

# Point ScriptRegistry to our temp plugin dir
local $ENV{BADGEROPS_HOME} = $tmpdir;

require BadgerOps::ScriptRegistry;
BadgerOps::ScriptRegistry->import(qw(script_index plugins_dir find_script find_closest invalidate_cache));

# ── 1. plugins_dir() returns the correct path ─────────────────────────────────
{
    my $dir = BadgerOps::ScriptRegistry::plugins_dir();
    like $dir, qr/\Q$tmpdir\E/, 'plugins_dir() honours BADGEROPS_HOME';
}

# ── 2. No plugins — script_index still works ─────────────────────────────────
{
    BadgerOps::ScriptRegistry::invalidate_cache();
    my @all = script_index();
    ok scalar @all >= 20, 'script_index() returns at least 20 built-in scripts with empty plugins dir';
}

# ── 3. Valid plugin is discovered and appears in index ────────────────────────
{
    write_plugin($plugins_dir, 'GoodPlugin');
    BadgerOps::ScriptRegistry::invalidate_cache();

    my @all   = script_index();
    my @plug  = grep { $_->[2] =~ /GoodPlugin/ } @all;
    is scalar @plug, 1, 'GoodPlugin appears once in script_index()';

    my $p = $plug[0];
    is $p->[0], 'Test Plugin',   'plugin display name is from metadata()';
    is $p->[4], 'Plugins',       'plugin category is Plugins';
}

# ── 4. Plugin with comment-header metadata (no metadata() sub) ────────────────
{
    my $path = File::Spec->catfile($plugins_dir, 'HeaderPlugin.pm');
    open my $fh, '>', $path or die $!;
    print $fh <<'PM';
package BadgerOps::Plugin::HeaderPlugin;
# Name: Header Plugin
# Description: Loaded via comment headers
# Category: Security
use strict;
use warnings;
sub run { return { status => 'ok', data => [] } }
sub format_report { return '' }
1;
PM
    close $fh;

    BadgerOps::ScriptRegistry::invalidate_cache();
    my @all  = script_index();
    my @hp   = grep { $_->[0] eq 'Header Plugin' } @all;
    ok scalar @hp >= 1, 'plugin with comment-header metadata is discovered';
    is $hp[0][4], 'Security', 'comment-header category is parsed correctly';
}

# ── 5. Plugin without run() is rejected ───────────────────────────────────────
{
    write_plugin($plugins_dir, 'NoRunPlugin', has_run => 0);
    BadgerOps::ScriptRegistry::invalidate_cache();

    my @all  = script_index();
    my @bad  = grep { $_->[2] =~ /NoRunPlugin/ } @all;
    is scalar @bad, 0, 'plugin without run() is skipped';
}

# ── 6. Plugin with invalid package name (security) ────────────────────────────
{
    my $bad_path = File::Spec->catfile($plugins_dir, 'bad plugin!.pm');
    SKIP: {
        skip 'filesystem does not support ! in filenames', 1
            unless eval { open my $fh, '>', $bad_path; close $fh; 1 };
        open my $fh, '>', $bad_path or die $!;
        print $fh "1;\n";
        close $fh;

        BadgerOps::ScriptRegistry::invalidate_cache();
        my @all = script_index();
        my @bp  = grep { defined $_->[1] && $_->[1] =~ /bad plugin/ } @all;
        is scalar @bp, 0, 'plugin with invalid filename is rejected';
        unlink $bad_path;
    }
}

# ── 7. Disabled plugin does not appear ────────────────────────────────────────
SKIP: {
    skip 'BadgerOps::Config not available', 2
        unless eval { require BadgerOps::Config; 1 };

    # Write a minimal config YAML that disables GoodPlugin
    my $cfg_dir  = File::Spec->catdir($tmpdir, 'badgerops');
    mkdir $cfg_dir unless -d $cfg_dir;
    my $cfg_file = File::Spec->catfile($cfg_dir, 'config.yml');
    open my $fh, '>', $cfg_file or die $!;
    print $fh "schema_version: 4\ndisabled_plugins:\n  - GoodPlugin\n";
    close $fh;

    BadgerOps::ScriptRegistry::invalidate_cache();
    my @all  = script_index();
    my @plug = grep { $_->[2] =~ /GoodPlugin/ } @all;
    is scalar @plug, 0, 'disabled plugin is excluded from index';

    # Re-enable by removing config
    unlink $cfg_file;
    BadgerOps::ScriptRegistry::invalidate_cache();
    @all  = script_index();
    @plug = grep { $_->[2] =~ /GoodPlugin/ } @all;
    is scalar @plug, 1, 'plugin reappears after removing disable config';
}

# ── 8. find_closest() returns suggestion for typo ────────────────────────────
{
    # Built-in 'system_info' should match a close typo
    my $suggestion = find_closest('sytem_info');   # typo: missing 's'
    ok defined $suggestion, 'find_closest() returns a suggestion for near-miss';
    like $suggestion, qr/system/i, 'suggestion mentions "system"';
}

# ── 9. find_closest() returns undef for garbage input ────────────────────────
{
    my $suggestion = find_closest('xyzzy_completely_unknown_zork');
    ok !defined $suggestion, 'find_closest() returns undef for garbage input';
}

done_testing();
