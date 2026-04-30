package BadgerOps::Scripts::DockerMonitor;
# ============================================================================
# DockerMonitor — container status, resource limits, image sizes
# ============================================================================
use strict;
use warnings;

sub run {
    my (%args) = @_;
    my %result = (
        available  => 0,
        containers => [],
        images     => [],
        volumes    => [],
        dangling   => [],
        disk_usage => {},
    );

    $result{available} = _docker_available();
    return \%result unless $result{available};

    $result{containers} = _get_containers();
    $result{images}     = _get_images();
    $result{volumes}    = _get_volumes();
    $result{dangling}   = _get_dangling_images();
    $result{disk_usage} = _get_disk_usage();

    return \%result;
}

sub format_report {
    my ($result) = @_;

    my $report = <<"EOF";
╔══════════════════════════════════════════════════════════════╗
║                   DOCKER MONITOR REPORT                      ║
╚══════════════════════════════════════════════════════════════╝

EOF

    unless ($result->{available}) {
        $report .= "  ⚠ Docker is not installed or the daemon is not running.\n";
        return $report;
    }

    # Containers
    $report .= "── Containers ────────────────────────────────────────────────\n";
    $report .= sprintf("  %-15s %-20s %-12s %-10s %s\n",
        'ID', 'Name', 'Status', 'Ports', 'Image');
    $report .= "  " . ("-" x 72) . "\n";
    for my $c (@{$result->{containers} // []}) {
        $report .= sprintf("  %-15s %-20s %-12s %-10s %s\n",
            substr($c->{id}, 0, 12),
            substr($c->{name}, 0, 20),
            $c->{status},
            $c->{ports} // '-',
            $c->{image});
    }
    my @running = grep { ($_->{status} // '') =~ /^Up/ } @{$result->{containers} // []};
    $report .= sprintf("\n  Total: %d  Running: %d\n",
        scalar @{$result->{containers} // []}, scalar @running);

    # Images
    $report .= "\n── Images ────────────────────────────────────────────────────\n";
    $report .= sprintf("  %-30s %-15s %s\n", 'Repository:Tag', 'Size', 'Created');
    $report .= "  " . ("-" x 60) . "\n";
    for my $img (@{$result->{images} // []}) {
        $report .= sprintf("  %-30s %-15s %s\n",
            substr("$img->{repo}:$img->{tag}", 0, 30),
            $img->{size}, $img->{created});
    }

    # Dangling images
    my @dangling = @{$result->{dangling} // []};
    if (@dangling) {
        $report .= "\n── Dangling Images (removable) ───────────────────────────────\n";
        $report .= "  $_\n" for @dangling;
        $report .= "\n  Run: docker image prune  to reclaim space.\n";
    }

    # Disk usage
    if ($result->{disk_usage}) {
        $report .= "\n── Docker Disk Usage ─────────────────────────────────────────\n";
        $report .= "  $_\n" for @{$result->{disk_usage} // []};
    }

    return $report;
}

# ── Internal helpers ──

sub _docker_available {
    my $out = '';
    if (open my $fh, '-|', 'docker', 'info') {
        local $/;
        $out = <$fh> // '';
        close $fh;
    }
    return ($? == 0 && $out !~ /Cannot connect/) ? 1 : 0;
}

sub _get_containers {
    my @containers;
    my $out = '';
    if (open my $fh, '-|', 'docker', 'ps', '-a', '--format', '{{.ID}}|{{.Names}}|{{.Status}}|{{.Ports}}|{{.Image}}') {
        local $/;
        $out = <$fh> // '';
        close $fh;
    }
    for my $line (split /\n/, $out) {
        my ($id, $name, $status, $ports, $image) = split /\|/, $line, 5;
        next unless $id;
        push @containers, {
            id     => $id,
            name   => $name // '',
            status => $status // '',
            ports  => $ports // '',
            image  => $image // '',
        };
    }
    return \@containers;
}

sub _get_images {
    my @images;
    my $out = '';
    if (open my $fh, '-|', 'docker', 'images', '--format', '{{.Repository}}|{{.Tag}}|{{.Size}}|{{.CreatedSince}}') {
        local $/;
        $out = <$fh> // '';
        close $fh;
    }
    for my $line (split /\n/, $out) {
        my ($repo, $tag, $size, $created) = split /\|/, $line, 4;
        next unless $repo;
        push @images, {
            repo    => $repo,
            tag     => $tag // 'latest',
            size    => $size // '?',
            created => $created // '?',
        };
    }
    return \@images;
}

sub _get_volumes {
    my @volumes;
    my $out = '';
    if (open my $fh, '-|', 'docker', 'volume', 'ls', '--format', '{{.Name}}') {
        local $/;
        $out = <$fh> // '';
        close $fh;
    }
    @volumes = grep { length } split /\n/, $out;
    return \@volumes;
}

sub _get_dangling_images {
    my @dangling;
    my $out = '';
    if (open my $fh, '-|', 'docker', 'images', '-f', 'dangling=true', '--format', '{{.ID}} {{.Size}}') {
        local $/;
        $out = <$fh> // '';
        close $fh;
    }
    @dangling = grep { length } split /\n/, $out;
    return \@dangling;
}

sub _get_disk_usage {
    my @lines;
    my $out = '';
    if (open my $fh, '-|', 'docker', 'system', 'df') {
        local $/;
        $out = <$fh> // '';
        close $fh;
    }
    @lines = grep { length } split /\n/, $out;
    return \@lines;
}

sub metadata {
    return {
        name        => 'Docker Monitor',
        filename    => 'docker_monitor.pl',
        description => 'Container status, images, disk usage',
        category    => 'Containers',
        icon        => 'application-x-executable-symbolic',
        emoji       => '🐳',
    };
}

1;

__END__

=head1 NAME

BadgerOps::Scripts::DockerMonitor - Docker container and image monitoring

=head1 SYNOPSIS

    use BadgerOps::Scripts::DockerMonitor;
    my $result = BadgerOps::Scripts::DockerMonitor::run();
    print BadgerOps::Scripts::DockerMonitor::format_report($result);

=head1 DESCRIPTION

Reports on Docker containers (running/stopped), images, dangling images,
volumes, and disk usage summary.

=head1 EXPORTED FUNCTIONS

=over 4

=item B<run(%args)>

Invokes the Docker CLI (C<docker ps>, C<docker images>, C<docker system df>)
to collect container and image data.  Returns an empty result with
C<available =E<gt> 0> if Docker is not installed.

=item B<format_report($result)>

Formats the Docker snapshot as a human-readable text report.

=back

=head1 RETURNS

C<run()> returns a hashref with:

=over 4

=item C<available>

Boolean — 1 if Docker is installed and reachable, 0 otherwise.

=item C<containers>

Arrayref of container info strings (C<docker ps -a --format>).

=item C<images>

Arrayref of image info strings.

=item C<volumes>

Arrayref of volume name strings.

=item C<dangling>

Arrayref of dangling image ID/size strings.

=item C<disk_usage>

Arrayref of C<docker system df> output lines.

=back

=head1 AUTHOR

James Temple <james@amiga-fan.net>

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2026 Honey Badger Universe

MIT License

=cut
