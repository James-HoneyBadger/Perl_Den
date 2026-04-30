#!/usr/bin/env perl
# ============================================================================
# t/01_config.t — Test BadgerOps::Config (functional API)
# ============================================================================
use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../lib";
use File::Temp qw(tempdir);

use_ok('BadgerOps::Config');

# Redirect config dir to a temp location so tests don't touch real config
my $tmpdir = tempdir(CLEANUP => 1);
{
    no warnings 'redefine';
    *BadgerOps::Config::_ensure_dir = sub {
        $BadgerOps::Config::CONFIG_DIR  = "$tmpdir/badgerops_test";
        $BadgerOps::Config::CONFIG_FILE = "$tmpdir/badgerops_test/config.yml";
        $BadgerOps::Config::SESSION_FILE = "$tmpdir/badgerops_test/session.yml";
        File::Path::make_path($BadgerOps::Config::CONFIG_DIR)
            unless -d $BadgerOps::Config::CONFIG_DIR;
    };
}

subtest 'Default config values' => sub {
    my $data = BadgerOps::Config::load();
    ok(ref $data eq 'HASH', 'load returns hashref');
    is($data->{theme}, 'vscode-dark-plus', 'default theme is vscode-dark-plus');
    is($data->{tab_width}, 4, 'default tab width is 4');
    ok($data->{show_line_numbers}, 'line numbers on by default');
    is($data->{editor_scheme}, 'oblivion', 'default scheme is oblivion');
};

subtest 'Set and get values' => sub {
    BadgerOps::Config::set('theme', 'light');
    is(BadgerOps::Config::get('theme'), 'light', 'theme updated');

    BadgerOps::Config::set('custom_key', 'value');
    is(BadgerOps::Config::get('custom_key'), 'value', 'custom key stored');
};

subtest 'Save and reload' => sub {
    BadgerOps::Config::set('theme', 'solarized');
    BadgerOps::Config::save();

    # Reset internal state and reload from disk
    $BadgerOps::Config::DATA = {};
    my $data = BadgerOps::Config::load();
    is($data->{theme}, 'solarized', 'theme persisted across save/reload');
};

subtest 'Session persistence' => sub {
    my $sess = BadgerOps::Config::load_session();
    ok(ref $sess eq 'HASH', 'session is a hashref');
    is($sess->{window_width}, 1400, 'default window width');
    is($sess->{window_height}, 900, 'default window height');

    BadgerOps::Config::session_set('active_tab', 3);
    BadgerOps::Config::save_session();

    $BadgerOps::Config::SESSION = {};
    my $s2 = BadgerOps::Config::load_session();
    is($s2->{active_tab}, 3, 'session active_tab persisted');
};

done_testing();
