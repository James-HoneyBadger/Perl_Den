package BadgerOps::Scripts::DuplicateFinder;
# ============================================================================
# Duplicate file finder — SHA256-based duplicate detection
# ============================================================================
use strict;
use warnings;
use File::Find;
use File::Spec;
use Digest::SHA;
use BadgerOps::Util qw(format_bytes);

sub run {
    my (%args) = @_;
    my $dir      = $args{directory} // '.';
    my $min_size = $args{min_size}  // 1;       # bytes, skip empty files
    my $max_depth = $args{max_depth};           # undef = unlimited

    die "Directory not found: $dir\n" unless -d $dir;

    my %by_size;
    my $total_files = 0;
    my $base_depth  = ($dir =~ tr|/||);

    # Pass 1: group files by size (cheap)
    find({
        no_chdir => 1,
        wanted   => sub {
            return unless -f $_ && !-l $_;
            if (defined $max_depth) {
                my $d = ($File::Find::name =~ tr|/||) - $base_depth;
                return if $d > $max_depth;
            }
            my $size = -s $_;
            return if $size < $min_size;
            $total_files++;
            push @{$by_size{$size}}, $File::Find::name;
        }
    }, $dir);

    # Pass 2: SHA256 only files that share a size (expensive, but narrowed)
    my %by_hash;
    my $hashed = 0;
    for my $size (keys %by_size) {
        next if @{$by_size{$size}} < 2;
        for my $file (@{$by_size{$size}}) {
            my $digest = eval { _sha256($file) };
            next unless $digest;
            $hashed++;
            push @{$by_hash{$digest}}, { path => $file, size => $size };
        }
    }

    # Collect duplicates
    my @groups;
    my $wasted = 0;
    for my $hash (sort keys %by_hash) {
        next if @{$by_hash{$hash}} < 2;
        my @files = @{$by_hash{$hash}};
        my $size  = $files[0]{size};
        $wasted  += $size * (@files - 1);
        push @groups, {
            hash  => $hash,
            size  => $size,
            count => scalar @files,
            files => [ map { $_->{path} } @files ],
        };
    }

    @groups = sort { $b->{size} * $b->{count} <=> $a->{size} * $a->{count} } @groups;

    return {
        directory    => $dir,
        total_files  => $total_files,
        files_hashed => $hashed,
        groups       => \@groups,
        wasted_bytes => $wasted,
    };
}

sub format_report {
    my ($result) = @_;

    my $report = <<"EOF";
╔══════════════════════════════════════════════════════════════╗
║                 DUPLICATE FILE FINDER                        ║
╚══════════════════════════════════════════════════════════════╝

  Directory:      $result->{directory}
  Files scanned:  $result->{total_files}
  Files hashed:   $result->{files_hashed}
  Duplicate sets: @{[ scalar @{$result->{groups}} ]}
  Wasted space:   @{[ _fmt_bytes($result->{wasted_bytes}) ]}

EOF

    if (@{$result->{groups}}) {
        $report .= "── Duplicate Groups ──────────────────────────────────────────\n";
        my $n = 0;
        for my $g (@{$result->{groups}}) {
            $n++;
            last if $n > 50;
            $report .= sprintf("\n  Group %d — %s each, %d copies (SHA256: %.16s…)\n",
                $n, _fmt_bytes($g->{size}), $g->{count}, $g->{hash});
            for my $f (@{$g->{files}}) {
                $report .= "    $f\n";
            }
        }
        if (@{$result->{groups}} > 50) {
            $report .= sprintf("\n  ... and %d more groups\n",
                scalar(@{$result->{groups}}) - 50);
        }
    } else {
        $report .= "  No duplicates found.\n";
    }

    return $report;
}

sub _sha256 {
    my ($file) = @_;
    my $sha = Digest::SHA->new(256);
    $sha->addfile($file, 'b');
    return $sha->hexdigest;
}

# _fmt_bytes is provided by BadgerOps::Util::format_bytes
sub _fmt_bytes { goto &format_bytes }

sub metadata {
    return {
        name        => 'Duplicate Finder',
        filename    => 'duplicate_finder.pl',
        description => 'Find duplicate files by hash',
        category    => 'Backup & Config',
        icon        => 'drive-harddisk-symbolic',
        emoji       => '💾',
    };
}

1;

__END__

=head1 NAME

BadgerOps::Scripts::DuplicateFinder - Find duplicate files by content hash

=head1 SYNOPSIS

    use BadgerOps::Scripts::DuplicateFinder;
    my $r = BadgerOps::Scripts::DuplicateFinder::run(
        directory => '/home/james',
        min_size  => 1024,
        max_depth => 5,
    );
    print BadgerOps::Scripts::DuplicateFinder::format_report($r);

=head1 DESCRIPTION

Finds duplicate files using a two-pass approach: first groups files by
size, then compares SHA256 hashes within each group.  Reports wasted
space and duplicate sets.

=head1 EXPORTED FUNCTIONS

=over 4

=item B<run(%args)>

Parameters: C<directory>, C<min_size> (bytes, skip smaller),
C<max_depth> (directory recursion limit).

Returns a hash-ref with duplicate groups and totals.

=item B<format_report($result)>

Format the hash-ref from C<run()> as a human-readable report string.

=back

=head1 RETURNS

C<run()> returns a hashref with:

=over 4

=item C<directory>

The directory that was scanned.

=item C<total_files> / C<files_hashed>

Count of files examined and fully hashed.

=item C<groups>

Arrayref of C<{ hash, size, count, files }> hashrefs.  C<files> is an
arrayref of duplicate path strings.

=item C<wasted_bytes>

Total bytes wasted by duplicates.

=back

=head1 AUTHOR

James Temple <james@amiga-fan.net>

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2026 Honey Badger Universe

MIT License

=cut
