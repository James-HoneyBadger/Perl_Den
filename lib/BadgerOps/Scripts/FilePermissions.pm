package BadgerOps::Scripts::FilePermissions;
# ============================================================================
# Audit file permissions — SUID, SGID, world-writable, orphaned files
# ============================================================================
use strict;
use warnings;
use File::Find;
use File::stat;
use Fcntl qw(:mode);

sub run {
    my (%args) = @_;
    my $target    = $args{target} // '/';
    my $max_files = $args{max_files} // 500;

    my @suid_files;
    my @sgid_files;
    my @world_writable;
    my @world_readable_sensitive;
    my @no_owner;
    my $count = 0;

    # Sensitive paths to check readability
    my %sensitive = map { $_ => 1 } qw(
        /etc/shadow /etc/gshadow /etc/sudoers
    );

    eval {
        local $SIG{__WARN__} = sub {
            # Silently skip permission-denied warnings from File::Find
            warn $_[0] unless $_[0] =~ /Permission denied|Can't opendir/;
        };
        find({
            wanted => sub {
                return if $count >= $max_files * 10;  # scan limit
                return unless -f $_ || -d $_;
                return if -l $_;

                my $st = File::stat::stat($_);
                return unless $st;

                my $mode = $st->mode;
                my $path = $File::Find::name;

                # SUID files
                if ($mode & S_ISUID && -f $_) {
                    push @suid_files, {
                        path  => $path,
                        mode  => sprintf("%04o", $mode & 07777),
                        owner => scalar(getpwuid($st->uid)) // $st->uid,
                        group => scalar(getgrgid($st->gid)) // $st->gid,
                        size  => $st->size,
                    };
                    $count++;
                }

                # SGID files
                if ($mode & S_ISGID && -f $_) {
                    push @sgid_files, {
                        path  => $path,
                        mode  => sprintf("%04o", $mode & 07777),
                        owner => scalar(getpwuid($st->uid)) // $st->uid,
                        group => scalar(getgrgid($st->gid)) // $st->gid,
                    };
                    $count++;
                }

                # World-writable (non-sticky)
                if (($mode & S_IWOTH) && !($mode & S_ISVTX)) {
                    push @world_writable, {
                        path  => $path,
                        mode  => sprintf("%04o", $mode & 07777),
                        type  => -d $_ ? 'dir' : 'file',
                    };
                    $count++;
                }

                # Orphaned files (no user or group)
                if (!getpwuid($st->uid) || !getgrgid($st->gid)) {
                    push @no_owner, {
                        path => $path,
                        uid  => $st->uid,
                        gid  => $st->gid,
                    };
                    $count++;
                }
            },
            no_chdir => 1,
            follow   => 0,
        }, $target);
    };

    # Check sensitive files specifically
    for my $f (sort keys %sensitive) {
        next unless -e $f;
        my $st = File::stat::stat($f);
        next unless $st;
        my $mode = $st->mode;
        if ($mode & S_IROTH) {
            push @world_readable_sensitive, {
                path => $f,
                mode => sprintf("%04o", $mode & 07777),
            };
        }
    }

    return {
        target              => $target,
        suid_files          => \@suid_files,
        sgid_files          => \@sgid_files,
        world_writable      => \@world_writable,
        world_readable_sens => \@world_readable_sensitive,
        no_owner            => \@no_owner,
    };
}

sub format_report {
    my ($result) = @_;

    my $report = <<"EOF";
╔══════════════════════════════════════════════════════════════╗
║                FILE PERMISSIONS AUDIT                        ║
╚══════════════════════════════════════════════════════════════╝

Scan target: $result->{target}

EOF

    # Sensitive files
    if (@{$result->{world_readable_sens}}) {
        $report .= "⚠  WORLD-READABLE SENSITIVE FILES:\n";
        for my $f (@{$result->{world_readable_sens}}) {
            $report .= "   $f->{path}  (mode: $f->{mode})\n";
        }
        $report .= "\n";
    }

    # SUID
    $report .= "── SUID Files (" . scalar(@{$result->{suid_files}}) . ") ──\n";
    if (@{$result->{suid_files}}) {
        $report .= sprintf("  %-6s %-10s %-10s %s\n", 'MODE', 'OWNER', 'GROUP', 'PATH');
        for my $f (@{$result->{suid_files}}) {
            $report .= sprintf("  %-6s %-10s %-10s %s\n",
                $f->{mode}, $f->{owner}, $f->{group}, $f->{path});
        }
    } else {
        $report .= "  None found\n";
    }

    # SGID
    $report .= "\n── SGID Files (" . scalar(@{$result->{sgid_files}}) . ") ──\n";
    if (@{$result->{sgid_files}}) {
        for my $f (@{$result->{sgid_files}}) {
            $report .= sprintf("  %-6s %-10s %-10s %s\n",
                $f->{mode}, $f->{owner}, $f->{group}, $f->{path});
        }
    } else {
        $report .= "  None found\n";
    }

    # World-writable
    $report .= "\n── World-Writable (no sticky bit) (" . scalar(@{$result->{world_writable}}) . ") ──\n";
    if (@{$result->{world_writable}}) {
        for my $f (@{$result->{world_writable}}) {
            $report .= sprintf("  [%s] %-6s %s\n", $f->{type}, $f->{mode}, $f->{path});
        }
    } else {
        $report .= "  None found (good!)\n";
    }

    # Orphaned
    $report .= "\n── Orphaned Files (no valid owner) (" . scalar(@{$result->{no_owner}}) . ") ──\n";
    if (@{$result->{no_owner}}) {
        for my $f (@{$result->{no_owner}}) {
            $report .= sprintf("  uid=%-6d gid=%-6d %s\n", $f->{uid}, $f->{gid}, $f->{path});
        }
    } else {
        $report .= "  None found\n";
    }

    return $report;
}

sub metadata {
    return {
        name        => 'File Permissions',
        filename    => 'file_permissions.pl',
        description => 'Audit SUID/SGID/world-writable files',
        category    => 'Security',
        icon        => 'security-high-symbolic',
        emoji       => '🔒',
    };
}

1;

__END__

=head1 NAME

BadgerOps::Scripts::FilePermissions - File permission security auditing

=head1 SYNOPSIS

    use BadgerOps::Scripts::FilePermissions;
    my $r = BadgerOps::Scripts::FilePermissions::run(
        target    => '/usr/local/bin',
        max_files => 10_000,
    );
    print BadgerOps::Scripts::FilePermissions::format_report($r);

=head1 DESCRIPTION

Audits a filesystem subtree for permission-related security issues:
SUID/SGID executables, world-writable files and directories (missing
sticky bit), world-readable sensitive files, and orphaned files with
no valid owner or group.

=head1 EXPORTED FUNCTIONS

=over 4

=item B<run(%args)>

Parameters: C<target> (directory to scan), C<max_files> (limit to
prevent runaway scans).

Returns a hash-ref with categorised findings and counts.

=item B<format_report($result)>

Format the hash-ref from C<run()> as a human-readable report string.

=back

=head1 RETURNS

C<run()> returns a hashref with:

=over 4

=item C<target>

The directory scanned.

=item C<suid_files> / C<sgid_files>

Arrayrefs of path strings for SUID and SGID files.

=item C<world_writable>

Arrayref of world-writable file/directory paths.

=item C<world_readable_sens>

Arrayref of world-readable sensitive file paths (private keys, shadow files).

=item C<no_owner>

Arrayref of paths with no valid owner UID/GID.

=back

=head1 AUTHOR

James Temple <james@amiga-fan.net>

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2026 Honey Badger Universe

MIT License

=cut
