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

use_ok('PerlDen::Config');

# Redirect config dir to temp location
my $tmpdir = tempdir(CLEANUP => 1);
{
    no warnings 'redefine';
    *PerlDen::Config::_ensure_dir = sub {
        $PerlDen::Config::CONFIG_DIR   = "$tmpdir/perlden_test";
        $PerlDen::Config::CONFIG_FILE  = "$tmpdir/perlden_test/config.yml";
        $PerlDen::Config::SESSION_FILE = "$tmpdir/perlden_test/session.yml";
        make_path($PerlDen::Config::CONFIG_DIR)
            unless -d $PerlDen::Config::CONFIG_DIR;
    };
}

subtest 'Config schema version is set' => sub {
    $PerlDen::Config::DATA = {};
    my $data = PerlDen::Config::load();
    ok(exists $data->{_config_version}, '_config_version key exists');
    is($data->{_config_version}, $PerlDen::Config::CONFIG_SCHEMA_VERSION,
       'schema version matches current');
};

subtest 'New default keys present' => sub {
    $PerlDen::Config::DATA = {};
    my $data = PerlDen::Config::load();
    ok(exists $data->{dashboard_interval}, 'dashboard_interval key exists');
    is($data->{dashboard_interval}, 5, 'default dashboard_interval is 5');
    ok(exists $data->{privilege_tool}, 'privilege_tool key exists');
    is($data->{privilege_tool}, 'auto', 'default privilege_tool is auto');
};

subtest 'Validation coerces bad types' => sub {
    $PerlDen::Config::DATA = {};
    PerlDen::Config::load();
    # Set invalid values
    PerlDen::Config::set('tab_width', 'not_a_number');
    PerlDen::Config::save();

    # Reload and check coercion
    $PerlDen::Config::DATA = {};
    my $data = PerlDen::Config::load();
    is($data->{tab_width}, 4, 'invalid tab_width reverts to default');
};

subtest 'Recent files validation' => sub {
    $PerlDen::Config::DATA = {};
    PerlDen::Config::load();

    # Add a file that exists and one that doesn't
    my $real_file = "$tmpdir/existing_file.pl";
    open my $fh, '>', $real_file or die;
    print $fh "1;\n";
    close $fh;

    PerlDen::Config::add_recent_file($real_file);
    PerlDen::Config::save();

    # Manually inject a non-existent file into the list
    push @{$PerlDen::Config::DATA->{recent_files}}, '/nonexistent/file.pl';
    PerlDen::Config::save();

    # Reload — stale files should be filtered
    $PerlDen::Config::DATA = {};
    my $data = PerlDen::Config::load();
    my @files = @{$data->{recent_files}};
    ok(!grep({ $_ eq '/nonexistent/file.pl' } @files), 'stale file filtered');
    ok(grep({ $_ eq $real_file } @files), 'existing file preserved');
};

subtest 'recent_files() accessor filters stale' => sub {
    $PerlDen::Config::DATA = {};
    PerlDen::Config::load();

    my $real_file = "$tmpdir/accessor_test.pl";
    open my $fh, '>', $real_file or die;
    print $fh "1;\n";
    close $fh;

    PerlDen::Config::add_recent_file($real_file);
    my $list = PerlDen::Config::recent_files();
    ok(ref $list eq 'ARRAY', 'recent_files returns arrayref');
    ok(grep({ $_ eq $real_file } @$list), 'real file in list');
};

subtest 'Save and reload with locking' => sub {
    $PerlDen::Config::DATA = {};
    PerlDen::Config::load();
    PerlDen::Config::set('theme', 'vscode-light-plus');
    PerlDen::Config::save();

    $PerlDen::Config::DATA = {};
    my $data = PerlDen::Config::load();
    is($data->{theme}, 'vscode-light-plus', 'theme persisted through locked save');
};

subtest 'Session auto-saves timestamp' => sub {
    $PerlDen::Config::SESSION = {};
    PerlDen::Config::load_session();
    PerlDen::Config::save_session();

    $PerlDen::Config::SESSION = {};
    my $sess = PerlDen::Config::load_session();
    ok(exists $sess->{_saved_at}, '_saved_at timestamp exists');
    ok($sess->{_saved_at} > 0, 'timestamp is positive');
};

subtest 'Session cleans stale open_files' => sub {
    $PerlDen::Config::SESSION = {};
    PerlDen::Config::load_session();
    PerlDen::Config::session_set('open_files', ['/nonexistent/a.pl', '/nonexistent/b.pl']);
    PerlDen::Config::save_session();

    $PerlDen::Config::SESSION = {};
    my $sess = PerlDen::Config::load_session();
    is_deeply($sess->{open_files}, [], 'stale session files cleaned');
};

subtest 'privilege_tool detection' => sub {
    $PerlDen::Config::DATA = {};
    PerlDen::Config::load();
    my $tool = PerlDen::Config::privilege_tool();
    ok(defined $tool, 'privilege_tool returns a value');
    like($tool, qr/^(?:pkexec|sudo|doas)$/, 'returns valid tool name');
};

done_testing();
