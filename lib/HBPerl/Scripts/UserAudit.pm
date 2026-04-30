package HBPerl::Scripts::UserAudit;
# ============================================================================
# Audit user accounts — security checks, password status, shells
# ============================================================================
use strict;
use warnings;

sub run {
    my (%args) = @_;

    my @users;
    my @warnings;

    # Parse /etc/passwd
    if (open my $fh, '<', '/etc/passwd') {
        while (<$fh>) {
            chomp;
            my ($name, $pass, $uid, $gid, $gecos, $home, $shell) = split /:/;
            next unless defined $name;
            push @users, {
                name  => $name,
                uid   => $uid + 0,
                gid   => $gid + 0,
                gecos => $gecos // '',
                home  => $home // '',
                shell => $shell // '',
                is_system => ($uid < 1000 && $uid != 0),
                is_root   => ($uid == 0),
            };
        }
        close $fh;
    }

    # Check for duplicate UIDs
    my %uid_map;
    for my $u (@users) {
        push @{$uid_map{$u->{uid}}}, $u->{name};
    }
    for my $uid (sort { $a <=> $b } keys %uid_map) {
        if (@{$uid_map{$uid}} > 1) {
            push @warnings, "Duplicate UID $uid: " . join(', ', @{$uid_map{$uid}});
        }
    }

    # Check for UID 0 accounts (should only be root)
    my @uid0 = grep { $_->{uid} == 0 && $_->{name} ne 'root' } @users;
    if (@uid0) {
        push @warnings, "Non-root accounts with UID 0: " .
            join(', ', map { $_->{name} } @uid0);
    }

    # Check for users with login shells that might be unused
    my @login_users = grep {
        $_->{shell} && $_->{shell} !~ m{/(nologin|false|sync|shutdown|halt)$}
    } @users;

    # Users without home directory
    my @no_home = grep {
        $_->{home} && !-d $_->{home} && !$_->{is_system}
    } @login_users;
    if (@no_home) {
        push @warnings, "Users with missing home directories: " .
            join(', ', map { "$_->{name} ($_->{home})" } @no_home);
    }

    # Check password status (requires root for shadow, graceful fallback)
    my @no_password;
    my @locked;
    my @password_status;

    if (open my $fh, '<', '/etc/shadow') {
        while (<$fh>) {
            chomp;
            my ($name, $hash, @rest) = split /:/;
            next unless defined $name;

            my $status = 'set';
            if (!$hash || $hash eq '') {
                $status = 'empty';
                push @no_password, $name;
                push @warnings, "Account '$name' has NO PASSWORD!";
            } elsif ($hash eq '!' || $hash eq '*' || $hash =~ /^!/) {
                $status = 'locked';
                push @locked, $name;
            }

            push @password_status, { name => $name, status => $status };
        }
        close $fh;
    } else {
        push @warnings, "Cannot read /etc/shadow (need root) — password checks skipped";
        # Try passwd -S for current user at least
        for my $u (@login_users) {
            next unless $u->{name} =~ /^[a-zA-Z0-9._-]+$/;
            my $out = '';
            if (open my $pfh, '-|', 'passwd', '-S', $u->{name}) {
                $out = do { local $/; <$pfh> } // '';
                close $pfh;
            }
            if ($out =~ /^(\S+)\s+(\S+)/) {
                my $status = $2 eq 'P' ? 'set' :
                             $2 eq 'L' ? 'locked' :
                             $2 eq 'NP' ? 'empty' : 'unknown';
                push @password_status, { name => $1, status => $status };
            }
        }
    }

    # Check sudo access
    my @sudoers;
    if (open my $fh, '<', '/etc/group') {
        while (<$fh>) {
            chomp;
            my ($group, undef, undef, $members) = split /:/;
            if ($group && ($group eq 'sudo' || $group eq 'wheel')) {
                @sudoers = split /,/, ($members // '');
            }
        }
        close $fh;
    }

    # Last logins
    my @last_logins;
    my @last_output;
    if (open my $fh, '-|', 'last', '-n', '20', '--time-format', 'iso') {
        @last_output = <$fh>;
        close $fh;
    }
    for my $line (@last_output) {
        if ($line =~ /^(\S+)\s+(\S+)\s+(\S+)\s+(\S+)/) {
            push @last_logins, {
                user     => $1,
                terminal => $2,
                from     => $3,
                time     => $4,
            };
        }
    }

    return {
        users           => \@users,
        login_users     => \@login_users,
        warnings        => \@warnings,
        no_password     => \@no_password,
        locked          => \@locked,
        password_status => \@password_status,
        sudoers         => \@sudoers,
        last_logins     => \@last_logins,
        uid0_accounts   => \@uid0,
    };
}

sub format_report {
    my ($result) = @_;

    my $report = <<"EOF";
╔══════════════════════════════════════════════════════════════╗
║                    USER ACCOUNT AUDIT                        ║
╚══════════════════════════════════════════════════════════════╝

Total accounts: @{[scalar @{$result->{users}}]}
Login-capable:  @{[scalar @{$result->{login_users}}]}
Sudo/Wheel:     @{[join ', ', @{$result->{sudoers}}]}

EOF

    if (@{$result->{warnings}}) {
        $report .= "⚠  SECURITY WARNINGS:\n";
        for my $w (@{$result->{warnings}}) {
            $report .= "   ⚠ $w\n";
        }
        $report .= "\n";
    } else {
        $report .= "✓ No security warnings\n\n";
    }

    $report .= "── Login-Capable Users ────────────────────────────────────────\n";
    $report .= sprintf("  %-15s %5s %5s  %-20s %s\n", 'USER', 'UID', 'GID', 'HOME', 'SHELL');
    $report .= "  " . "-" x 70 . "\n";
    for my $u (sort { $a->{uid} <=> $b->{uid} } @{$result->{login_users}}) {
        $report .= sprintf("  %-15s %5d %5d  %-20s %s\n",
            $u->{name}, $u->{uid}, $u->{gid}, $u->{home}, $u->{shell});
    }

    if (@{$result->{password_status}}) {
        $report .= "\n── Password Status ───────────────────────────────────────────\n";
        for my $p (@{$result->{password_status}}) {
            my $marker = $p->{status} eq 'empty'  ? '✗' :
                         $p->{status} eq 'locked' ? '🔒' : '✓';
            $report .= "  $marker $p->{name}: $p->{status}\n";
        }
    }

    if (@{$result->{last_logins}}) {
        $report .= "\n── Recent Logins ─────────────────────────────────────────────\n";
        for my $l (@{$result->{last_logins}}) {
            $report .= "  $l->{user}\t$l->{terminal}\t$l->{from}\t$l->{time}\n";
        }
    }

    return $report;
}

sub metadata {
    return {
        name        => 'User Audit',
        filename    => 'user_audit.pl',
        description => 'Audit user accounts and security',
        category    => 'User Management',
        icon        => 'system-users-symbolic',
        emoji       => '👤',
    };
}

1;

__END__

=head1 NAME

HBPerl::Scripts::UserAudit - User account security auditing

=head1 SYNOPSIS

    use HBPerl::Scripts::UserAudit;
    my $r = HBPerl::Scripts::UserAudit::run();
    print HBPerl::Scripts::UserAudit::format_report($r);

=head1 DESCRIPTION

Audits user accounts for security issues: duplicate UIDs, UID-0
non-root accounts, empty passwords, missing home directories, and
recent login activity.  Reads from F</etc/passwd>, F</etc/shadow>,
and the C<lastlog> database.

=head1 EXPORTED FUNCTIONS

=over 4

=item B<run(%args)>

No parameters required.  Returns a hash-ref with account findings,
warnings, and login history.

=item B<format_report($result)>

Format the hash-ref from C<run()> as a human-readable report string.

=back

=head1 RETURNS

C<run()> returns a hashref with:

=over 4

=item C<users>

Arrayref of all user hashrefs C<{ name, uid, gid, home, shell, gecos }>.

=item C<login_users>

Subset of users with interactive login shells.

=item C<warnings>

Arrayref of human-readable warning strings (duplicate UIDs, etc.).

=item C<no_password> / C<locked>

Arrayrefs of usernames with empty or locked passwords.

=item C<sudoers>

Arrayref of usernames with sudo/wheel group membership.

=item C<last_logins>

Arrayref of recent login strings from C<last>.

=item C<uid0_accounts>

Arrayref of non-root usernames with UID 0.

=back

=head1 AUTHOR

James Temple <james@amiga-fan.net>

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2026 Honey Badger Universe

MIT License

=cut
