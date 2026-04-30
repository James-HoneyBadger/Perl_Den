package HBPerl::Scripts::DiskUsage;
# ============================================================================
# Analyze disk usage by directory — find space hogs
# ============================================================================
use strict;
use warnings;
use File::Find;
use File::Basename qw(basename);
use Cwd qw(abs_path);
use HBPerl::Util qw(format_bytes);

sub run {
    my (%args) = @_;
    my $target     = $args{target} // $ENV{HOME} // '/tmp';
    my $max_depth  = $args{max_depth} // 2;
    my $top_n      = $args{top_n} // 20;
    my $min_size   = $args{min_size} // 1048576;  # 1MB default

    $target = abs_path($target) // $target;

    my %dir_sizes;
    my @large_files;

    eval {
        find({
            wanted => sub {
                return unless -f $_ && !-l $_;
                my $size = -s $_ // 0;
                my $file = $File::Find::name;

                # Accumulate directory sizes up to and including target
                my $dir = $File::Find::dir;
                while ($dir && length($dir) >= length($target)) {
                    $dir_sizes{$dir} += $size;
                    last if $dir eq $target;
                    $dir =~ s|/[^/]+$|| or last;
                }

                # Track large files
                if ($size >= $min_size) {
                    push @large_files, { path => $file, size => $size };
                }
            },
            no_chdir   => 1,
            follow     => 0,
        }, $target);
    };

    # Filter directories by depth
    my $base_depth = () = $target =~ /\//g;
    my @dirs;
    for my $dir (sort keys %dir_sizes) {
        my $depth = (() = $dir =~ /\//g) - $base_depth;
        next if $depth > $max_depth || $depth < 0;
        push @dirs, { path => $dir, size => $dir_sizes{$dir}, depth => $depth };
    }

    # Sort directories by size descending
    @dirs = sort { $b->{size} <=> $a->{size} } @dirs;
    splice @dirs, $top_n if @dirs > $top_n;

    # Sort large files by size descending
    @large_files = sort { $b->{size} <=> $a->{size} } @large_files;
    splice @large_files, $top_n if @large_files > $top_n;

    return {
        target       => $target,
        total_size   => $dir_sizes{$target} // 0,
        directories  => \@dirs,
        large_files  => \@large_files,
    };
}

sub format_report {
    my ($result) = @_;

    my $report = <<"EOF";
╔══════════════════════════════════════════════════════════════╗
║                    DISK USAGE ANALYSIS                       ║
╚══════════════════════════════════════════════════════════════╝

Target: $result->{target}
Total:  @{[_fmt_size($result->{total_size})]}

── Top Directories by Size ───────────────────────────────────
EOF

    my $max_size = $result->{directories}[0]{size} || 1;
    for my $d (@{$result->{directories}}) {
        my $bar_len = int(40 * $d->{size} / $max_size);
        $bar_len = 1 if $bar_len < 1 && $d->{size} > 0;
        my $bar = '█' x $bar_len;
        my $indent = '  ' x $d->{depth};
        $report .= sprintf("  %8s  %s%s %s\n",
            _fmt_size($d->{size}), $indent, $bar, $d->{path});
    }

    $report .= "\n── Largest Files ─────────────────────────────────────────────\n";
    for my $f (@{$result->{large_files}}) {
        $report .= sprintf("  %8s  %s\n", _fmt_size($f->{size}), $f->{path});
    }

    return $report;
}

# _fmt_size is provided by HBPerl::Util::format_bytes
sub _fmt_size { goto &format_bytes }

sub metadata {
    return {
        name        => 'Disk Usage Analyzer',
        filename    => 'disk_usage.pl',
        description => 'Analyze disk usage by directory',
        category    => 'System Info',
        icon        => 'computer-symbolic',
        emoji       => '🖥',
    };
}

1;

__END__

=head1 NAME

HBPerl::Scripts::DiskUsage - Recursive directory size analysis

=head1 SYNOPSIS

    use HBPerl::Scripts::DiskUsage;
    my $result = HBPerl::Scripts::DiskUsage::run(
        target    => '/home',
        max_depth => 2,
        top_n     => 20,
        min_size  => 1_048_576,   # 1 MB
    );
    print HBPerl::Scripts::DiskUsage::format_report($result);

=head1 DESCRIPTION

Recursively walks a directory tree accumulating sizes per directory,
identifying the largest files, and summarising space consumption.

=head1 EXPORTED FUNCTIONS

=over 4

=item B<run(%args)>

Parameters: C<target> (directory path), C<max_depth>, C<top_n> (number
of largest entries to show), C<min_size> (bytes, skip files smaller).

Returns a hash-ref with directory sizes and top files.

=item B<format_report($result)>

Format the hash-ref from C<run()> as a human-readable report string.

=back

=head1 RETURNS

C<run()> returns a hashref with:

=over 4

=item C<target>

The directory analysed (default C</>).

=item C<total_size>

Total size of C<target> in bytes.

=item C<directories>

Arrayref of C<{ path, size }> hashrefs sorted by size descending.

=item C<large_files>

Arrayref of C<{ path, size }> hashrefs for the largest individual files.

=back

=head1 AUTHOR

James Temple <james@amiga-fan.net>

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2026 Honey Badger Universe

MIT License

=cut
