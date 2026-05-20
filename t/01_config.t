#!/usr/bin/env perl
# ============================================================================
# t/01_config.t — Test PerlDen::Config (functional API)
# ============================================================================
use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../lib";
use File::Temp qw(tempdir);

use_ok('PerlDen::Config');

# Redirect config dir to a temp location so tests don't touch real config
my $tmpdir = tempdir(CLEANUP => 1);
{
    no warnings 'redefine';
    *PerlDen::Config::_ensure_dir = sub {
        $PerlDen::Config::CONFIG_DIR  = "$tmpdir/perlden_test";
        $PerlDen::Config::CONFIG_FILE = "$tmpdir/perlden_test/config.yml";
        $PerlDen::Config::SESSION_FILE = "$tmpdir/perlden_test/session.yml";
        File::Path::make_path($PerlDen::Config::CONFIG_DIR)
            unless -d $PerlDen::Config::CONFIG_DIR;
    };
}

subtest 'Default config values' => sub {
    my $data = PerlDen::Config::load();
    ok(ref $data eq 'HASH', 'load returns hashref');
    is($data->{theme}, 'vscode-dark-plus', 'default theme is vscode-dark-plus');
    is($data->{tab_width}, 4, 'default tab width is 4');
    ok($data->{show_line_numbers}, 'line numbers on by default');
    is($data->{editor_scheme}, 'oblivion', 'default scheme is oblivion');
};

subtest 'Set and get values' => sub {
    PerlDen::Config::set('theme', 'light');
    is(PerlDen::Config::get('theme'), 'light', 'theme updated');

    PerlDen::Config::set('custom_key', 'value');
    is(PerlDen::Config::get('custom_key'), 'value', 'custom key stored');
};

subtest 'Save and reload' => sub {
    PerlDen::Config::set('theme', 'solarized');
    PerlDen::Config::save();

    # Reset internal state and reload from disk
    $PerlDen::Config::DATA = {};
    my $data = PerlDen::Config::load();
    is($data->{theme}, 'solarized', 'theme persisted across save/reload');
};

subtest 'Session persistence' => sub {
    my $sess = PerlDen::Config::load_session();
    ok(ref $sess eq 'HASH', 'session is a hashref');
    is($sess->{window_width}, 1400, 'default window width');
    is($sess->{window_height}, 900, 'default window height');

    PerlDen::Config::session_set('active_tab', 3);
    PerlDen::Config::save_session();

    $PerlDen::Config::SESSION = {};
    my $s2 = PerlDen::Config::load_session();
    is($s2->{active_tab}, 3, 'session active_tab persisted');
};

done_testing();
