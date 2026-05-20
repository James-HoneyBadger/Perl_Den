#!/usr/bin/env perl
# ============================================================================
# t/21_script_registry_user.t — Test user/plugin script discovery
# ============================================================================
use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../lib";
use File::Temp qw(tempdir);
use File::Path qw(make_path);

use_ok('PerlDen::ScriptRegistry');

# Redirect user scripts directory to a temp location
my $tmpdir = tempdir(CLEANUP => 1);
my $user_dir = "$tmpdir/scripts";
make_path($user_dir);

{
    no warnings 'redefine';
    *PerlDen::ScriptRegistry::user_scripts_dir = sub { $user_dir };
}

# Reset cache
@PerlDen::ScriptRegistry::_user_scripts_cache = ();
$PerlDen::ScriptRegistry::_user_scripts_mtime = 0;

subtest 'built-in scripts always present' => sub {
    my @index = PerlDen::ScriptRegistry::script_index();
    cmp_ok(scalar @index, '>=', 15, 'at least 15 built-in scripts');
};

subtest 'user script with metadata headers' => sub {
    my $script = "$user_dir/my_tool.pl";
    open my $fh, '>', $script or die $!;
    print $fh <<'SCRIPT';
#!/usr/bin/env perl
# Name: My Custom Tool
# Description: Does something useful
use strict;
use warnings;
print "Hello from my tool\n";
SCRIPT
    close $fh;

    # Reset cache to force re-scan
    @PerlDen::ScriptRegistry::_user_scripts_cache = ();
    $PerlDen::ScriptRegistry::_user_scripts_mtime = 0;

    my @index = PerlDen::ScriptRegistry::script_index();
    my @user = grep { $_->[4] eq 'User Scripts' } @index;
    is(scalar @user, 1, 'found 1 user script');
    is($user[0][0], 'My Custom Tool', 'name extracted from header');
    is($user[0][3], 'Does something useful', 'description extracted from header');
};

subtest 'user script without metadata gets defaults' => sub {
    my $script = "$user_dir/bare_script.pl";
    open my $fh, '>', $script or die $!;
    print $fh "#!/usr/bin/env perl\nprint 1;\n";
    close $fh;

    @PerlDen::ScriptRegistry::_user_scripts_cache = ();
    $PerlDen::ScriptRegistry::_user_scripts_mtime = 0;

    my @index = PerlDen::ScriptRegistry::script_index();
    my @user = grep { $_->[4] eq 'User Scripts' } @index;
    is(scalar @user, 2, '2 user scripts now');

    my ($bare) = grep { $_->[1] =~ /bare_script/ } @user;
    ok($bare, 'bare_script found');
    is($bare->[3], 'User script', 'default description applied');
    like($bare->[0], qr/Bare Script/i, 'name derived from filename');
};

subtest 'find_script finds user scripts' => sub {
    @PerlDen::ScriptRegistry::_user_scripts_cache = ();
    $PerlDen::ScriptRegistry::_user_scripts_mtime = 0;

    my @found = PerlDen::ScriptRegistry::find_script('my_tool');
    ok(scalar @found > 0, 'find_script matched user script');
    is($found[0], 'My Custom Tool', 'correct name returned');
};

subtest 'script_categories includes User Scripts' => sub {
    @PerlDen::ScriptRegistry::_user_scripts_cache = ();
    $PerlDen::ScriptRegistry::_user_scripts_mtime = 0;

    my @cats = PerlDen::ScriptRegistry::script_categories();
    my ($user_cat) = grep { $_->{name} eq 'User Scripts' } @cats;
    ok($user_cat, 'User Scripts category exists');
    cmp_ok(scalar @{$user_cat->{items}}, '>=', 2, 'has user script items');
};

subtest 'non-.pl files are ignored' => sub {
    open my $fh, '>', "$user_dir/readme.txt" or die $!;
    print $fh "Not a script\n";
    close $fh;

    @PerlDen::ScriptRegistry::_user_scripts_cache = ();
    $PerlDen::ScriptRegistry::_user_scripts_mtime = 0;

    my @index = PerlDen::ScriptRegistry::script_index();
    my @user = grep { $_->[4] eq 'User Scripts' } @index;
    is(scalar @user, 2, 'still 2 user scripts (txt ignored)');
};

subtest 'empty user dir returns no user scripts' => sub {
    my $empty_dir = tempdir(CLEANUP => 1) . "/empty";
    make_path($empty_dir);

    {
        no warnings 'redefine';
        *PerlDen::ScriptRegistry::user_scripts_dir = sub { $empty_dir };
    }
    @PerlDen::ScriptRegistry::_user_scripts_cache = ();
    $PerlDen::ScriptRegistry::_user_scripts_mtime = 0;

    my @index = PerlDen::ScriptRegistry::script_index();
    my @user = grep { $_->[4] eq 'User Scripts' } @index;
    is(scalar @user, 0, 'no user scripts from empty dir');

    # Restore
    {
        no warnings 'redefine';
        *PerlDen::ScriptRegistry::user_scripts_dir = sub { $user_dir };
    }
};

done_testing();
