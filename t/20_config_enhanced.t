#!/usr/bin/env perl
# ============================================================================
# t/20_config_enhanced.t — Test Config versioning, validation, locking
# ============================================================================
use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../lib";
use File::Temp qw(tempdir);
use File::Path qw(make_path);

use_ok('BadgerOps::Config');

# Redirect config dir to temp location
my $tmpdir = tempdir(CLEANUP => 1);
{
    no warnings 'redefine';
    *BadgerOps::Config::_ensure_dir = sub {
        $BadgerOps::Config::CONFIG_DIR   = "$tmpdir/badgerops_test";
        $BadgerOps::Config::CONFIG_FILE  = "$tmpdir/badgerops_test/config.yml";
        $BadgerOps::Config::SESSION_FILE = "$tmpdir/badgerops_test/session.yml";
        make_path($BadgerOps::Config::CONFIG_DIR)
            unless -d $BadgerOps::Config::CONFIG_DIR;
    };
}

subtest 'Config schema version is set' => sub {
    $BadgerOps::Config::DATA = {};
    my $data = BadgerOps::Config::load();
    ok(exists $data->{_config_version}, '_config_version key exists');
    is($data->{_config_version}, $BadgerOps::Config::CONFIG_SCHEMA_VERSION,
       'schema version matches current');
};

subtest 'New default keys present' => sub {
    $BadgerOps::Config::DATA = {};
    my $data = BadgerOps::Config::load();
    ok(exists $data->{dashboard_interval}, 'dashboard_interval key exists');
    is($data->{dashboard_interval}, 5, 'default dashboard_interval is 5');
    ok(exists $data->{privilege_tool}, 'privilege_tool key exists');
    is($data->{privilege_tool}, 'auto', 'default privilege_tool is auto');
};

subtest 'Validation coerces bad types' => sub {
    $BadgerOps::Config::DATA = {};
    BadgerOps::Config::load();
    # Set invalid values
    BadgerOps::Config::set('tab_width', 'not_a_number');
    BadgerOps::Config::save();

    # Reload and check coercion
    $BadgerOps::Config::DATA = {};
    my $data = BadgerOps::Config::load();
    is($data->{tab_width}, 4, 'invalid tab_width reverts to default');
};

subtest 'Recent files validation' => sub {
    $BadgerOps::Config::DATA = {};
    BadgerOps::Config::load();

    # Add a file that exists and one that doesn't
    my $real_file = "$tmpdir/existing_file.pl";
    open my $fh, '>', $real_file or die;
    print $fh "1;\n";
    close $fh;

    BadgerOps::Config::add_recent_file($real_file);
    BadgerOps::Config::save();

    # Manually inject a non-existent file into the list
    push @{$BadgerOps::Config::DATA->{recent_files}}, '/nonexistent/file.pl';
    BadgerOps::Config::save();

    # Reload — stale files should be filtered
    $BadgerOps::Config::DATA = {};
    my $data = BadgerOps::Config::load();
    my @files = @{$data->{recent_files}};
    ok(!grep({ $_ eq '/nonexistent/file.pl' } @files), 'stale file filtered');
    ok(grep({ $_ eq $real_file } @files), 'existing file preserved');
};

subtest 'recent_files() accessor filters stale' => sub {
    $BadgerOps::Config::DATA = {};
    BadgerOps::Config::load();

    my $real_file = "$tmpdir/accessor_test.pl";
    open my $fh, '>', $real_file or die;
    print $fh "1;\n";
    close $fh;

    BadgerOps::Config::add_recent_file($real_file);
    my $list = BadgerOps::Config::recent_files();
    ok(ref $list eq 'ARRAY', 'recent_files returns arrayref');
    ok(grep({ $_ eq $real_file } @$list), 'real file in list');
};

subtest 'Save and reload with locking' => sub {
    $BadgerOps::Config::DATA = {};
    BadgerOps::Config::load();
    BadgerOps::Config::set('theme', 'vscode-light-plus');
    BadgerOps::Config::save();

    $BadgerOps::Config::DATA = {};
    my $data = BadgerOps::Config::load();
    is($data->{theme}, 'vscode-light-plus', 'theme persisted through locked save');
};

subtest 'Session auto-saves timestamp' => sub {
    $BadgerOps::Config::SESSION = {};
    BadgerOps::Config::load_session();
    BadgerOps::Config::save_session();

    $BadgerOps::Config::SESSION = {};
    my $sess = BadgerOps::Config::load_session();
    ok(exists $sess->{_saved_at}, '_saved_at timestamp exists');
    ok($sess->{_saved_at} > 0, 'timestamp is positive');
};

subtest 'Session cleans stale open_files' => sub {
    $BadgerOps::Config::SESSION = {};
    BadgerOps::Config::load_session();
    BadgerOps::Config::session_set('open_files', ['/nonexistent/a.pl', '/nonexistent/b.pl']);
    BadgerOps::Config::save_session();

    $BadgerOps::Config::SESSION = {};
    my $sess = BadgerOps::Config::load_session();
    is_deeply($sess->{open_files}, [], 'stale session files cleaned');
};

subtest 'privilege_tool detection' => sub {
    $BadgerOps::Config::DATA = {};
    BadgerOps::Config::load();
    my $tool = BadgerOps::Config::privilege_tool();
    ok(defined $tool, 'privilege_tool returns a value');
    like($tool, qr/^(?:pkexec|sudo|doas)$/, 'returns valid tool name');
};

done_testing();
