#!/usr/bin/env perl
# ============================================================================
# t/14_script_registry.t — Test PerlDen::ScriptRegistry
# ============================================================================
use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../lib";

use_ok('PerlDen::ScriptRegistry', qw(script_index script_categories find_script));

subtest 'script_index returns all 20 scripts' => sub {
    my @scripts = script_index();
    is(scalar @scripts, 20, '20 scripts registered');

    for my $s (@scripts) {
        ok(ref $s eq 'ARRAY', 'entry is an arrayref');
        is(scalar @$s, 5, 'entry has 5 fields');
        my ($name, $file, $module, $desc, $cat) = @$s;
        ok(length($name)   > 0, "name is non-empty: $name");
        like($file, qr/\.pl$/, "filename ends with .pl: $file");
        like($module, qr/^PerlDen::Scripts::/, "module starts with PerlDen::Scripts: $module");
        ok(length($desc)   > 0, "description is non-empty");
        ok(length($cat)    > 0, "category is non-empty");
    }
};

subtest 'script_categories returns grouped data' => sub {
    my @cats = script_categories();
    ok(scalar @cats >= 5, 'at least 5 categories');

    my $total_items = 0;
    for my $cat (@cats) {
        ok(ref $cat eq 'HASH', 'category is a hashref');
        ok($cat->{name},  "category has a name: $cat->{name}");
        ok($cat->{icon},  "category has an icon");
        ok($cat->{emoji}, "category has an emoji");
        ok(ref $cat->{items} eq 'ARRAY', 'items is an arrayref');
        ok(scalar @{$cat->{items}} > 0, "category '$cat->{name}' has items");
        $total_items += scalar @{$cat->{items}};
    }
    is($total_items, 20, 'total items across categories equals 20');
};

subtest 'find_script exact match' => sub {
    my @found = find_script('disk_usage');
    is($found[0], 'Disk Usage Analyzer', 'found by stem');
    is($found[1], 'disk_usage.pl',       'correct filename');

    @found = find_script('disk_usage.pl');
    is($found[0], 'Disk Usage Analyzer', 'found with .pl extension');
};

subtest 'find_script partial match' => sub {
    my @found = find_script('ssl');
    is($found[1], 'ssl_checker.pl', 'partial match finds ssl_checker');
};

subtest 'find_script case insensitive' => sub {
    my @found = find_script('DISK_USAGE');
    is($found[1], 'disk_usage.pl', 'case insensitive match');
};

subtest 'find_script no match' => sub {
    my @found = find_script('nonexistent_script');
    is(scalar @found, 0, 'no match returns empty list');

    @found = find_script(undef);
    is(scalar @found, 0, 'undef returns empty list');
};

subtest 'script files exist on disk' => sub {
    my $script_dir = "$FindBin::Bin/../scripts";
    for my $s (script_index()) {
        my $file = "$script_dir/$s->[1]";
        ok(-f $file, "script file exists: $s->[1]");
    }
};

done_testing();
