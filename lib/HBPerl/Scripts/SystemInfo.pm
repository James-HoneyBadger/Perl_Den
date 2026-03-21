package HBPerl::Scripts::SystemInfo;
# ============================================================================
# Collect comprehensive system information from /proc, uname, etc.
# ============================================================================
use strict;
use warnings;
use POSIX qw(strftime uname);

sub run {
    my (%args) = @_;
    my %info;

    # ── OS / Kernel ──
    my @uname = uname();
    $info{hostname}    = $uname[1] // 'unknown';
    $info{kernel}      = $uname[2] // 'unknown';
    $info{arch}        = $uname[4] // 'unknown';
    $info{os}          = _read_os_release();

    # ── Uptime ──
    if (open my $fh, '<', '/proc/uptime') {
        my $line = <$fh>;
        close $fh;
        if ($line =~ /^([\d.]+)/) {
            my $secs = int($1);
            my $days  = int($secs / 86400);
            my $hours = int(($secs % 86400) / 3600);
            my $mins  = int(($secs % 3600) / 60);
            $info{uptime_seconds} = $secs;
            $info{uptime_human}   = "${days}d ${hours}h ${mins}m";
        }
    }

    # ── Load Average ──
    if (open my $fh, '<', '/proc/loadavg') {
        my $line = <$fh>;
        close $fh;
        if ($line =~ /^([\d.]+)\s+([\d.]+)\s+([\d.]+)\s+(\d+)\/(\d+)/) {
            $info{load_1}  = $1 + 0;
            $info{load_5}  = $2 + 0;
            $info{load_15} = $3 + 0;
            $info{running_procs} = $4 + 0;
            $info{total_procs}   = $5 + 0;
        }
    }

    # ── CPU Info ──
    if (open my $fh, '<', '/proc/cpuinfo') {
        my (@cpus, %current);
        while (<$fh>) {
            chomp;
            if (/^$/) {
                push @cpus, {%current} if %current;
                %current = ();
            } elsif (/^(.+?)\s*:\s*(.+)/) {
                $current{$1} = $2;
            }
        }
        push @cpus, {%current} if %current;
        close $fh;

        $info{cpu_model}   = $cpus[0]{'model name'} // $cpus[0]{'Processor'} // 'Unknown';
        $info{cpu_cores}   = scalar @cpus;
        $info{cpu_mhz}     = $cpus[0]{'cpu MHz'} // '';
        $info{cpu_bogomips} = $cpus[0]{'BogoMIPS'} // $cpus[0]{'bogomips'} // '';
    }

    # ── Memory ──
    if (open my $fh, '<', '/proc/meminfo') {
        my %mem;
        while (<$fh>) {
            $mem{$1} = $2 if /^(\w+):\s+(\d+)/;
        }
        close $fh;

        $info{mem_total_kb}     = $mem{MemTotal} // 0;
        $info{mem_available_kb} = $mem{MemAvailable} // $mem{MemFree} // 0;
        $info{mem_used_kb}      = $info{mem_total_kb} - $info{mem_available_kb};
        $info{swap_total_kb}    = $mem{SwapTotal} // 0;
        $info{swap_free_kb}     = $mem{SwapFree} // 0;
        $info{swap_used_kb}     = $info{swap_total_kb} - $info{swap_free_kb};
    }

    # ── Disk partitions ──
    $info{disks} = _get_disk_info();

    # ── Network interfaces ──
    $info{interfaces} = _get_network_interfaces();

    # ── Current user ──
    $info{user}     = $ENV{USER} // getpwuid($<) // 'unknown';
    $info{uid}      = $<;
    $info{euid}     = $>;
    $info{home}     = $ENV{HOME} // '';
    $info{shell}    = $ENV{SHELL} // '';
    $info{timestamp} = strftime('%Y-%m-%d %H:%M:%S', localtime);

    return \%info;
}

sub format_report {
    my ($info) = @_;
    $info //= run();

    my $kb2gb = sub { sprintf("%.2f GB", ($_[0] // 0) / 1048576) };
    my $kb2mb = sub { sprintf("%.0f MB", ($_[0] // 0) / 1024) };

    my $report = <<"EOF";
╔══════════════════════════════════════════════════════════════╗
║                    SYSTEM INFORMATION                        ║
║                    $info->{timestamp}                        ║
╚══════════════════════════════════════════════════════════════╝

── Host ──────────────────────────────────────────────────────
  Hostname:     $info->{hostname}
  OS:           $info->{os}
  Kernel:       $info->{kernel}
  Architecture: $info->{arch}
  Uptime:       $info->{uptime_human}
  User:         $info->{user} (UID: $info->{uid})
  Shell:        $info->{shell}

── CPU ───────────────────────────────────────────────────────
  Model:        $info->{cpu_model}
  Cores:        $info->{cpu_cores}
  BogoMIPS:     $info->{cpu_bogomips}

── Load Average ──────────────────────────────────────────────
  1 min:  $info->{load_1}    5 min:  $info->{load_5}    15 min: $info->{load_15}
  Processes:  $info->{running_procs} running / $info->{total_procs} total

── Memory ────────────────────────────────────────────────────
  Total:      @{[$kb2gb->($info->{mem_total_kb})]}
  Used:       @{[$kb2gb->($info->{mem_used_kb})]}
  Available:  @{[$kb2gb->($info->{mem_available_kb})]}
  Swap Total: @{[$kb2mb->($info->{swap_total_kb})]}
  Swap Used:  @{[$kb2mb->($info->{swap_used_kb})]}

── Disk Usage ────────────────────────────────────────────────
EOF

    if ($info->{disks} && @{$info->{disks}}) {
        $report .= sprintf("  %-20s %8s %8s %8s %6s\n",
            'Mount', 'Size', 'Used', 'Avail', 'Use%');
        $report .= "  " . "-" x 60 . "\n";
        for my $d (@{$info->{disks}}) {
            $report .= sprintf("  %-20s %8s %8s %8s %6s\n",
                $d->{mount}, $d->{size}, $d->{used}, $d->{avail}, $d->{pct});
        }
    }

    $report .= "\n── Network Interfaces ────────────────────────────────────────\n";
    if ($info->{interfaces} && @{$info->{interfaces}}) {
        for my $iface (@{$info->{interfaces}}) {
            $report .= "  $iface->{name}: $iface->{ip}" .
                ($iface->{mac} ? "  MAC: $iface->{mac}" : '') .
                "  State: $iface->{state}\n";
        }
    }

    return $report;
}

sub _read_os_release {
    my $file = -f '/etc/os-release' ? '/etc/os-release' : '/usr/lib/os-release';
    if (open my $fh, '<', $file) {
        while (<$fh>) {
            if (/^PRETTY_NAME="?(.+?)"?\s*$/) {
                close $fh;
                return $1;
            }
        }
        close $fh;
    }
    return 'Linux';
}

sub _get_disk_info {
    my @disks;
    my @lines;
    if (open my $fh, '-|', 'df', '-h', '--output=target,size,used,avail,pcent', '-x', 'tmpfs', '-x', 'devtmpfs', '-x', 'squashfs') {
        @lines = <$fh>;
        close $fh;
    }
    shift @lines;  # skip header
    for my $line (@lines) {
        $line =~ s/^\s+//;
        my ($mount, $size, $used, $avail, $pct) = split /\s+/, $line;
        next unless $mount;
        push @disks, {
            mount => $mount, size => $size, used => $used,
            avail => $avail, pct => $pct,
        };
    }
    return \@disks;
}

sub _get_network_interfaces {
    my @interfaces;
    my @lines;
    if (open my $fh, '-|', 'ip', '-o', 'addr', 'show') {
        @lines = <$fh>;
        close $fh;
    }
    for my $line (@lines) {
        if ($line =~ /^\d+:\s+(\S+)\s+inet\s+([\d.]+\/\d+)/) {
            my ($name, $ip) = ($1, $2);
            my $mac = '';
            my $state = 'unknown';
            my @link;
            if (open my $lnk_fh, '-|', 'ip', 'link', 'show', $name) {
                @link = <$lnk_fh>;
                close $lnk_fh;
            }
            for (@link) {
                $state = $1 if /state\s+(\w+)/;
                $mac = $1 if /link\/ether\s+([\da-f:]+)/i;
            }
            push @interfaces, { name => $name, ip => $ip, mac => $mac, state => $state };
        }
    }
    return \@interfaces;
}

1;

__END__

=head1 NAME

HBPerl::Scripts::SystemInfo - Comprehensive Linux system information collector

=head1 SYNOPSIS

    use HBPerl::Scripts::SystemInfo;
    my $info = HBPerl::Scripts::SystemInfo::run();
    print HBPerl::Scripts::SystemInfo::format_report($info);

=head1 DESCRIPTION

Collects comprehensive system information including OS/kernel version,
hostname, uptime, load average, CPU model and cores, memory and swap
usage, disk partitions, and network interfaces.  Data is gathered from
F</proc>, F</etc/os-release>, and standard Linux commands.

=head1 EXPORTED FUNCTIONS

=over 4

=item B<run(%args)>

No parameters required.  Returns a hash-ref with system metrics.

=item B<format_report($info)>

Format the hash-ref from C<run()> as a human-readable report string.
If called with no argument, calls C<run()> internally.

=back

=head1 AUTHOR

James Temple <james@amiga-fan.net>

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2026 Honey Badger Universe

MIT License

=cut
