package PerlDen::Scripts::ConfigDiff;
# ============================================================================
# Config diff — baseline snapshots and diff of system configuration files
# ============================================================================
use strict;
use warnings;
use File::Spec;
use File::Copy;
use File::Find;
use File::Basename;
use Digest::SHA;
use POSIX qw(strftime);
# Text::Diff is loaded lazily in _diff_against_baseline — optional CPAN dep

my @DEFAULT_TRACKED = qw(
    /etc/fstab
    /etc/hosts
    /etc/hostname
    /etc/resolv.conf
    /etc/nsswitch.conf
    /etc/passwd
    /etc/group
    /etc/shadow
    /etc/sudoers
    /etc/ssh/sshd_config
    /etc/sysctl.conf
    /etc/environment
    /etc/locale.conf
    /etc/pacman.conf
    /etc/makepkg.conf
);

sub run {
    my (%args) = @_;
    my $action   = $args{action}   // 'status';   # baseline | diff | status
    my $base_dir = $args{base_dir} // "$ENV{HOME}/.config/perlden/baselines";
    my $files    = $args{files}    // \@DEFAULT_TRACKED;

    my %result = (action => $action, base_dir => $base_dir);

    if ($action eq 'baseline') {
        $result{baseline} = _create_baseline($files, $base_dir);
    }
    elsif ($action eq 'diff') {
        $result{diffs} = _diff_against_baseline($files, $base_dir);
    }
    elsif ($action eq 'status') {
        $result{status} = _check_status($files, $base_dir);
    }

    return \%result;
}

sub format_report {
    my ($result) = @_;

    my $report = <<"EOF";
╔══════════════════════════════════════════════════════════════╗
║              CONFIGURATION DIFF TRACKER                       ║
╚══════════════════════════════════════════════════════════════╝

  Baseline Dir: $result->{base_dir}

EOF

    my $action = $result->{action};

    if ($action eq 'baseline') {
        my $b = $result->{baseline};
        $report .= "── Baseline Created ──────────────────────────────────────────\n";
        $report .= "  Timestamp:    $b->{timestamp}\n";
        $report .= "  Files saved:  $b->{saved}\n";
        $report .= "  Skipped:      $b->{skipped}\n";
        if (@{$b->{errors} // []}) {
            $report .= "  Errors:\n";
            for my $e (@{$b->{errors}}) {
                $report .= "    ✘ $e\n";
            }
        }
        $report .= "\n  Tracked files:\n";
        for my $f (@{$b->{files}}) {
            $report .= "    ✔ $f\n";
        }
    }
    elsif ($action eq 'diff') {
        my @diffs = @{$result->{diffs} // []};
        my @changed  = grep { $_->{status} eq 'changed' }  @diffs;
        my @same     = grep { $_->{status} eq 'same' }     @diffs;
        my @missing  = grep { $_->{status} eq 'missing' }  @diffs;
        my @no_base  = grep { $_->{status} eq 'no_baseline' } @diffs;

        $report .= "── Diff Summary ──────────────────────────────────────────────\n";
        $report .= sprintf("  Changed: %d  Unchanged: %d  Missing: %d  No Baseline: %d\n\n",
            scalar @changed, scalar @same, scalar @missing, scalar @no_base);

        for my $d (@changed) {
            $report .= "── CHANGED: $d->{file} ──\n";
            $report .= $d->{diff} . "\n";
        }
        for my $d (@missing) {
            $report .= "  ✘ MISSING: $d->{file}\n";
        }
        for my $d (@no_base) {
            $report .= "  ⚠ NO BASELINE: $d->{file}\n";
        }
    }
    elsif ($action eq 'status') {
        my @st = @{$result->{status} // []};
        $report .= "── File Status ───────────────────────────────────────────────\n";
        $report .= sprintf("  %-40s %-12s %-12s %s\n",
            'File', 'Status', 'Size', 'Modified');
        $report .= "  " . ("-" x 78) . "\n";
        for my $s (@st) {
            $report .= sprintf("  %-40s %-12s %-12s %s\n",
                $s->{file}, $s->{status},
                defined $s->{size} ? "$s->{size}B" : '-',
                $s->{mtime} // '-');
        }
    }

    return $report;
}

sub _create_baseline {
    my ($files, $base_dir) = @_;
    _ensure_dir($base_dir);

    my $ts = strftime('%Y%m%d_%H%M%S', localtime());
    my $snap_dir = File::Spec->catdir($base_dir, $ts);
    _ensure_dir($snap_dir);

    my @saved;
    my @errors;
    my $skipped = 0;

    for my $file (@$files) {
        unless (-f $file) {
            $skipped++;
            next;
        }
        unless (-r $file) {
            push @errors, "Cannot read: $file";
            next;
        }
        # Preserve directory structure
        my $dest = File::Spec->catfile($snap_dir, $file);
        my $dir  = dirname($dest);
        _ensure_dir($dir);

        if (copy($file, $dest)) {
            push @saved, $file;
        } else {
            push @errors, "Copy failed: $file — $!";
        }
    }

    # Also save a manifest
    my $manifest = File::Spec->catfile($snap_dir, 'MANIFEST');
    if (open my $fh, '>', $manifest) {
        for my $f (@saved) {
            my $sha = eval { _sha256($f) } // 'error';
            print $fh "$sha  $f\n";
        }
        close $fh;
    }

    # Symlink 'latest' to this snapshot
    my $latest = File::Spec->catfile($base_dir, 'latest');
    unlink $latest if -e $latest;
    symlink $snap_dir, $latest;

    return {
        timestamp => $ts,
        saved     => scalar @saved,
        skipped   => $skipped,
        errors    => \@errors,
        files     => \@saved,
    };
}

sub _diff_against_baseline {
    my ($files, $base_dir) = @_;
    my $latest = File::Spec->catfile($base_dir, 'latest');

    my @results;

    unless (-d $latest) {
        return [{ file => '(baseline)', status => 'no_baseline',
                  diff => 'No baseline found. Run with action => "baseline" first.' }];
    }

    for my $file (@$files) {
        my $base_file = File::Spec->catfile($latest, $file);
        my %entry = (file => $file);

        unless (-f $file) {
            $entry{status} = 'missing';
            push @results, \%entry;
            next;
        }
        unless (-f $base_file) {
            $entry{status} = 'no_baseline';
            push @results, \%entry;
            next;
        }

        # Compare checksums first (fast)
        my $cur_sha  = eval { _sha256($file) }      // '';
        my $base_sha = eval { _sha256($base_file) }  // '';

        if ($cur_sha eq $base_sha) {
            $entry{status} = 'same';
        } else {
            $entry{status} = 'changed';
            if (eval { require Text::Diff; 1 }) {
                $entry{diff} = Text::Diff::diff($base_file, $file, {
                    STYLE      => 'Unified',
                    FILENAME_A => "baseline:$file",
                    FILENAME_B => "current:$file",
                });
            } else {
                $entry{diff} = "(Text::Diff not installed — install it for unified diff output)\n";
            }
        }
        push @results, \%entry;
    }

    return \@results;
}

sub _check_status {
    my ($files, $base_dir) = @_;
    my $latest = File::Spec->catfile($base_dir, 'latest');
    my $has_baseline = -d $latest;

    my @status;
    for my $file (@$files) {
        my %s = (file => $file);
        if (-f $file) {
            my @st = stat($file);
            $s{size}   = $st[7];
            $s{mtime}  = strftime('%Y-%m-%d %H:%M', localtime($st[9]));
            $s{perms}  = sprintf('%04o', $st[2] & 07777);

            if ($has_baseline) {
                my $base_file = File::Spec->catfile($latest, $file);
                if (-f $base_file) {
                    my $cur_sha  = eval { _sha256($file) } // '';
                    my $base_sha = eval { _sha256($base_file) } // '';
                    $s{status} = ($cur_sha eq $base_sha) ? 'unchanged' : 'CHANGED';
                } else {
                    $s{status} = 'no baseline';
                }
            } else {
                $s{status} = 'present';
            }
        } else {
            $s{status} = 'MISSING';
        }
        push @status, \%s;
    }
    return \@status;
}

sub _sha256 {
    my ($file) = @_;
    my $sha = Digest::SHA->new(256);
    $sha->addfile($file, 'b');
    return $sha->hexdigest;
}

sub _ensure_dir {
    my ($dir) = @_;
    return if -d $dir;
    require File::Path;
    File::Path::make_path($dir);
}

sub metadata {
    return {
        name        => 'Config Diff',
        filename    => 'config_diff.pl',
        description => 'Compare config files against baselines',
        category    => 'Backup & Config',
        icon        => 'drive-harddisk-symbolic',
        emoji       => '💾',
    };
}

1;

__END__

=head1 NAME

PerlDen::Scripts::ConfigDiff - Track changes in system configuration files

=head1 SYNOPSIS

    use PerlDen::Scripts::ConfigDiff;

    my $r = PerlDen::Scripts::ConfigDiff::run(
        action   => 'baseline',
        base_dir => '/var/lib/hbperl/baselines',
        files    => ['/etc/passwd', '/etc/ssh/sshd_config'],
    );
    print PerlDen::Scripts::ConfigDiff::format_report($r);

=head1 DESCRIPTION

Takes SHA256-based baseline snapshots of system configuration files and
diffs them against the current state to detect unauthorised or
unexpected changes.

=head1 EXPORTED FUNCTIONS

=over 4

=item B<run(%args)>

Parameters: C<action> (baseline|diff|status), C<base_dir> (snapshot
storage path), C<files> (array-ref of file paths).

Returns a hash-ref with C<success>, C<action>, and diff details.

=item B<format_report($result)>

Format the hash-ref from C<run()> as a human-readable report string.

=back

=head1 RETURNS

C<run()> returns a hashref. Populated keys depend on C<action>:

=over 4

=item C<action>

The action performed: C<baseline>, C<diff>, or C<status>.

=item C<base_dir>

Path to the directory storing baseline snapshots.

=item C<baseline>

(C<action=baseline>) Arrayref of C<{ file, sha256, saved_to }> records.

=item C<diffs>

(C<action=diff>) Arrayref of C<{ file, status, diff }> records.

=item C<status>

(C<action=status>) Arrayref of C<{ file, status, sha256 }> records.

=back

=head1 AUTHOR

James Temple <james@amiga-fan.net>

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2026 Honey Badger Universe

MIT License

=cut
