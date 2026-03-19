#!/usr/bin/env perl
# ============================================================================
# t/01_config.t — Test HBPerl::Config (functional API)
# ============================================================================
use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../lib";
use File::Temp qw(tempdir);

use_ok('HBPerl::Config');

# Redirect config dir to a temp location so tests don't touch real config
my $tmpdir = tempdir(CLEANUP => 1);
{
    no warnings 'redefine';
    *HBPerl::Config::_ensure_dir = sub {
        $HBPerl::Config::CONFIG_DIR  = "$tmpdir/hb_perl_test";
        $HBPerl::Config::CONFIG_FILE = "$tmpdir/hb_perl_test/config.yml";
        $HBPerl::Config::SESSION_FILE = "$tmpdir/hb_perl_test/session.yml";
        File::Path::make_path($HBPerl::Config::CONFIG_DIR)
            unless -d $HBPerl::Config::CONFIG_DIR;
    };
}

subtest 'Default config values' => sub {
    my $data = HBPerl::Config::load();
    ok(ref $data eq 'HASH', 'load returns hashref');
    is($data->{theme}, 'vscode-dark-plus', 'default theme is vscode-dark-plus');
    is($data->{tab_width}, 4, 'default tab width is 4');
    ok($data->{show_line_numbers}, 'line numbers on by default');
    is($data->{editor_scheme}, 'oblivion', 'default scheme is oblivion');
};

subtest 'Set and get values' => sub {
    HBPerl::Config::set('theme', 'light');
    is(HBPerl::Config::get('theme'), 'light', 'theme updated');

    HBPerl::Config::set('custom_key', 'value');
    is(HBPerl::Config::get('custom_key'), 'value', 'custom key stored');
};

subtest 'Save and reload' => sub {
    HBPerl::Config::set('theme', 'solarized');
    HBPerl::Config::save();

    # Reset internal state and reload from disk
    $HBPerl::Config::DATA = {};
    my $data = HBPerl::Config::load();
    is($data->{theme}, 'solarized', 'theme persisted across save/reload');
};

subtest 'Session persistence' => sub {
    my $sess = HBPerl::Config::load_session();
    ok(ref $sess eq 'HASH', 'session is a hashref');
    is($sess->{window_width}, 1400, 'default window width');
    is($sess->{window_height}, 900, 'default window height');

    HBPerl::Config::session_set('active_tab', 3);
    HBPerl::Config::save_session();

    $HBPerl::Config::SESSION = {};
    my $s2 = HBPerl::Config::load_session();
    is($s2->{active_tab}, 3, 'session active_tab persisted');
};

done_testing();
