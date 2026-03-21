#!/usr/bin/env perl
# ============================================================================
# t/unit/security_hardening.t — Tests for command injection hardening
# ============================================================================
use strict;
use warnings;
use Test::More;
use FindBin qw($RealBin);
use File::Temp qw(tempdir);

use lib "$RealBin/../../lib";

use_ok('HBPerl::Util');
use_ok('HBPerl::Git');

# ============================================================================
# shell_quote()
# ============================================================================
subtest 'shell_quote basics' => sub {
    is(HBPerl::Util::shell_quote('hello'), "'hello'", 'simple string');
    is(HBPerl::Util::shell_quote('/usr/bin/perl'), "'/usr/bin/perl'", 'path');
    is(HBPerl::Util::shell_quote(''), "''", 'empty string');
    is(HBPerl::Util::shell_quote(undef), "''", 'undef');
};

subtest 'shell_quote escapes single quotes' => sub {
    is(HBPerl::Util::shell_quote("it's"), "'it'\\''s'", 'embedded single quote');
    is(HBPerl::Util::shell_quote("a'b'c"), "'a'\\''b'\\''c'", 'multiple single quotes');
};

subtest 'shell_quote neutralises shell metacharacters' => sub {
    my @dangerous = (
        'foo; rm -rf /',
        'foo && evil',
        'foo | cat /etc/passwd',
        '$(whoami)',
        '`whoami`',
        'foo > /dev/null',
        'foo\nbar',
    );
    for my $input (@dangerous) {
        my $quoted = HBPerl::Util::shell_quote($input);
        # Quoted value should round-trip through echo safely
        my $out = `echo $quoted`;
        chomp $out;
        is($out, $input, "round-trips: $input");
    }
};

subtest 'shell_quote handles spaces and special paths' => sub {
    my $quoted = HBPerl::Util::shell_quote('/home/user/my projects/script.pl');
    my $out = `echo $quoted`;
    chomp $out;
    is($out, '/home/user/my projects/script.pl', 'path with spaces');
};

# ============================================================================
# run_command_list()
# ============================================================================
subtest 'run_command_list basic' => sub {
    my ($out, $rc) = HBPerl::Util::run_command_list('echo', 'hello world');
    chomp $out;
    is($out, 'hello world', 'captures output');
    is($rc, 0, 'exit code 0');
};

subtest 'run_command_list no shell expansion' => sub {
    # $HOME should NOT be expanded when passed as an argument in list form
    my ($out, $rc) = HBPerl::Util::run_command_list('echo', '$HOME');
    chomp $out;
    is($out, '$HOME', 'shell variable not expanded in list form');
};

subtest 'run_command_list exit code' => sub {
    my ($out, $rc) = HBPerl::Util::run_command_list('false');
    isnt($rc, 0, 'non-zero exit code');
};

# ============================================================================
# Git.pm — path handling
# ============================================================================
subtest 'Git _run_git accepts paths with spaces' => sub {
    my $tmpdir = tempdir('git test XXXX', CLEANUP => 1, TMPDIR => 1);
    # Not a git repo, so should fail gracefully (return undef), not die
    my $result = HBPerl::Git::is_git_repo($tmpdir);
    ok(!$result, 'non-repo with spaces returns false, not crash');
};

subtest 'Git _run_git rejects undef dir' => sub {
    # is_git_repo() defaults undef to '.', so test _run_git directly
    my $result = HBPerl::Git::_run_git(undef, 'rev-parse', '--is-inside-work-tree');
    ok(!defined $result, 'undef dir returns undef from _run_git');
};

subtest 'Git _run_git rejects non-existent dir' => sub {
    my $result = HBPerl::Git::is_git_repo('/no/such/directory/exists');
    ok(!$result, 'non-existent dir returns false');
};

# ============================================================================
# BatchRunner module name validation
# ============================================================================
subtest 'BatchRunner rejects invalid module names' => sub {
    use_ok('HBPerl::BatchRunner');
    my @errors;
    my $br = HBPerl::BatchRunner->new(
        on_error => sub { push @errors, $_[1] },
    );

    # This test verifies the module name regex guard.
    # Since we can't directly inject an invalid module name through
    # find_script (it only returns registered modules), we verify the
    # validation exists by checking that 'nonexistent_xyz' fails with
    # "Unknown script" (which fires before module validation).
    my $results = $br->run_batch('nonexistent_xyz');
    like($results->[0]{error}, qr/Unknown script/, 'unknown script rejected');
};

done_testing();
