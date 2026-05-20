package PerlDen::GUI::Dashboard;
# ============================================================================
# PerlDen::GUI::Dashboard - Real-time system overview dashboard
# ============================================================================
use strict;
use warnings;
use utf8;
use Glib ('TRUE', 'FALSE');
use Gtk3;
use POSIX qw(strftime);
use PerlDen::Config;

sub new {
    my ($class, %args) = @_;
    my $self = bless {
        main_window => $args{main_window},
        cards       => {},
        markup_widgets => [],  # widgets whose markup needs theme refresh
    }, $class;
    $self->_build_ui;
    $self->_refresh;

    # Auto-refresh at configurable interval (pause when not visible)
    my $interval_secs = PerlDen::Config::get('dashboard_refresh_seconds') // 5;
    $interval_secs = 5 if $interval_secs < 1;
    my $timer_id = Glib::Timeout->add($interval_secs * 1000, sub {
        unless ($self->{widget} && $self->{widget}->get_mapped) {
            $self->{timer_id} = undef;
            return FALSE;
        }
        # Skip refresh if dashboard tab is not currently visible
        my $notebook = $self->{widget}->get_parent;
        if ($notebook && $notebook->isa('Gtk3::Notebook')) {
            my $current_page = $notebook->get_current_page;
            return TRUE unless $current_page == 0;  # Dashboard is page 0
        }
        $self->_refresh;
        return TRUE;
    });
    $self->{timer_id} = $timer_id;

    # Clean up timer on widget destruction
    $self->{widget}->signal_connect('destroy' => sub {
        Glib::Source->remove($self->{timer_id}) if $self->{timer_id};
        $self->{timer_id} = undef;
    });

    return $self;
}

sub _build_ui {
    my ($self) = @_;

    my $scroll = Gtk3::ScrolledWindow->new(undef, undef);
    $scroll->set_policy('automatic', 'automatic');

    my $vbox = Gtk3::Box->new('vertical', 8);
    $vbox->set_margin_start(16);
    $vbox->set_margin_end(16);
    $vbox->set_margin_top(12);
    $vbox->set_margin_bottom(12);

    # Title
    my $tc = PerlDen::Config::theme_colors();
    my $title = Gtk3::Label->new;
    $title->set_markup(qq{<span size="x-large" weight="bold" foreground="$tc->{accent}">⊞ System Dashboard</span>});
    $title->set_halign('start');
    $vbox->pack_start($title, FALSE, FALSE, 0);
    $self->{title_label} = $title;

    my $subtitle = Gtk3::Label->new;
    $subtitle->set_halign('start');
    $self->{subtitle} = $subtitle;
    $vbox->pack_start($subtitle, FALSE, FALSE, 0);

    # ── Row 1: Hostname, Kernel, Uptime, Load ──
    my $row1 = Gtk3::Box->new('horizontal', 8);
    $self->{cards}{hostname} = $self->_make_card('Hostname',   '...', $row1);
    $self->{cards}{kernel}   = $self->_make_card('Kernel',     '...', $row1);
    $self->{cards}{uptime}   = $self->_make_card('Uptime',     '...', $row1);
    $self->{cards}{load}     = $self->_make_card('Load Avg',   '...', $row1);
    $vbox->pack_start($row1, FALSE, FALSE, 0);

    # ── Row 2: CPU, Memory, Swap ──
    my $row2 = Gtk3::Box->new('horizontal', 8);
    $self->{cards}{cpu}    = $self->_make_card('CPU Usage',   '...', $row2);
    $self->{cards}{memory} = $self->_make_card('Memory',      '...', $row2);
    $self->{cards}{swap}   = $self->_make_card('Swap',        '...', $row2);
    $vbox->pack_start($row2, FALSE, FALSE, 0);

    # ── Row 3: Disk Usage ──
    my $row3_label = Gtk3::Label->new;
    $row3_label->set_markup(qq{<span weight="bold" foreground="$tc->{accent}">Disk Usage</span>});
    $row3_label->set_halign('start');
    $row3_label->set_margin_top(8);
    $vbox->pack_start($row3_label, FALSE, FALSE, 0);
    $self->{disk_label} = $row3_label;

    my $disk_box = Gtk3::Box->new('vertical', 4);
    $self->{disk_box} = $disk_box;
    $vbox->pack_start($disk_box, FALSE, FALSE, 0);

    # ── Row 4: Top Processes ──
    my $proc_label = Gtk3::Label->new;
    $proc_label->set_markup(qq{<span weight="bold" foreground="$tc->{accent}">Top Processes (by CPU)</span>});
    $proc_label->set_halign('start');
    $proc_label->set_margin_top(8);
    $vbox->pack_start($proc_label, FALSE, FALSE, 0);
    $self->{proc_label} = $proc_label;

    # Process list as a TreeView
    my $proc_store = Gtk3::ListStore->new(
        'Glib::String', 'Glib::String', 'Glib::String', 'Glib::String', 'Glib::String'
    );
    $self->{proc_store} = $proc_store;

    my $proc_tree = Gtk3::TreeView->new($proc_store);
    $proc_tree->set_headers_visible(TRUE);
    eval { $proc_tree->get_accessible->set_name('Top processes by CPU usage') };
    my @headers = ('PID', 'User', 'CPU%', 'MEM%', 'Command');
    for my $i (0 .. $#headers) {
        my $renderer = Gtk3::CellRendererText->new;
        my $col = Gtk3::TreeViewColumn->new_with_attributes($headers[$i], $renderer, text => $i);
        $col->set_resizable(TRUE);
        $col->set_min_width(60);
        $proc_tree->append_column($col);
    }

    my $proc_sw = Gtk3::ScrolledWindow->new(undef, undef);
    $proc_sw->set_policy('automatic', 'never');
    $proc_sw->set_min_content_height(200);
    $proc_sw->add($proc_tree);
    $vbox->pack_start($proc_sw, FALSE, FALSE, 0);

    # ── Row 5: Hardware (Temperature + GPU) ──
    my $hw_label = Gtk3::Label->new;
    $hw_label->set_markup(qq{<span weight="bold" foreground="$tc->{accent}">Hardware</span>});
    $hw_label->set_halign('start');
    $hw_label->set_margin_top(8);
    $vbox->pack_start($hw_label, FALSE, FALSE, 0);
    $self->{hw_label} = $hw_label;

    my $hw_row = Gtk3::Box->new('horizontal', 8);
    $self->{cards}{cpu_temp} = $self->_make_card('CPU Temp', 'N/A', $hw_row);
    $self->{cards}{gpu_temp} = $self->_make_card('GPU Temp', 'N/A', $hw_row);
    $self->{cards}{gpu_util} = $self->_make_card('GPU Util', 'N/A', $hw_row);
    $vbox->pack_start($hw_row, FALSE, FALSE, 0);

    $scroll->add($vbox);
    $self->{widget} = $scroll;
}

sub _make_card {
    my ($self, $label_text, $value_text, $parent_box) = @_;

    my $frame = Gtk3::Frame->new;
    $frame->get_style_context->add_class('dashboard-card');

    my $box = Gtk3::Box->new('vertical', 4);
    $box->set_margin_start(12);
    $box->set_margin_end(12);
    $box->set_margin_top(8);
    $box->set_margin_bottom(8);

    my $tc = PerlDen::Config::theme_colors();
    my $label = Gtk3::Label->new;
    $label->set_markup(qq{<span size='small' foreground='$tc->{subtext}'>$label_text</span>});
    $label->set_halign('start');
    $label->get_style_context->add_class('dashboard-label');
    push @{$self->{markup_widgets}}, { widget => $label, template => qq{<span size='small' foreground='%s'>$label_text</span>}, key => 'subtext' };

    my $value = Gtk3::Label->new($value_text);
    $value->set_halign('start');
    $value->get_style_context->add_class('dashboard-value');

    # ATK accessible name for screen readers
    eval { $frame->get_accessible->set_name("Dashboard card: $label_text") };

    $box->pack_start($label, FALSE, FALSE, 0);
    $box->pack_start($value, FALSE, FALSE, 0);
    $frame->add($box);

    $parent_box->pack_start($frame, TRUE, TRUE, 0);

    return $value;
}

sub _refresh {
    my ($self) = @_;

    # Hostname (from /proc or POSIX)
    my $hostname = 'unknown';
    if (open my $fh, '<', '/proc/sys/kernel/hostname') {
        chomp($hostname = <$fh> // 'unknown');
        close $fh;
    }
    $self->{cards}{hostname}->set_text($hostname);

    # Kernel (from /proc/version)
    my $kernel = 'unknown';
    if (open my $fh, '<', '/proc/version') {
        my $line = <$fh>;
        close $fh;
        $kernel = $1 if $line && $line =~ /Linux version\s+(\S+)/;
    }
    $self->{cards}{kernel}->set_text($kernel);

    # Uptime
    if (open my $fh, '<', '/proc/uptime') {
        my $line = <$fh>;
        close $fh;
        if ($line =~ /^(\d+(?:\.\d+)?)/) {
            my $secs = int($1);
            my $days  = int($secs / 86400);
            my $hours = int(($secs % 86400) / 3600);
            my $mins  = int(($secs % 3600) / 60);
            $self->{cards}{uptime}->set_text("${days}d ${hours}h ${mins}m");
        }
    }

    # Load average
    if (open my $fh, '<', '/proc/loadavg') {
        my $line = <$fh>;
        close $fh;
        if ($line =~ /^([\d.]+)\s+([\d.]+)\s+([\d.]+)/) {
            $self->{cards}{load}->set_text("$1  $2  $3");
        }
    }

    # CPU usage (from /proc/stat, simplified as idle%)
    eval {
        if (open my $fh, '<', '/proc/stat') {
            my $line = <$fh>;
            close $fh;
            if ($line =~ /^cpu\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)/) {
                my $total = $1+$2+$3+$4+$5+$6+$7;
                my $idle = $4;
                if ($self->{prev_total}) {
                    my $dt = $total - $self->{prev_total};
                    my $di = $idle - $self->{prev_idle};
                    my $usage = $dt > 0 ? sprintf("%.1f%%", 100 * (1 - $di/$dt)) : "0.0%";
                    $self->{cards}{cpu}->set_text($usage);
                }
                $self->{prev_total} = $total;
                $self->{prev_idle}  = $idle;
            }
        }
    };

    # Memory
    eval {
        if (open my $fh, '<', '/proc/meminfo') {
            my %mem;
            while (<$fh>) {
                $mem{$1} = $2 if /^(\w+):\s+(\d+)/;
            }
            close $fh;

            my $total = $mem{MemTotal} // 0;
            my $avail = $mem{MemAvailable} // $mem{MemFree} // 0;
            my $used  = $total - $avail;
            if ($total > 0) {
                my $pct = sprintf("%.1f%%", 100 * $used / $total);
                my $used_gb  = sprintf("%.1f", $used / 1048576);
                my $total_gb = sprintf("%.1f", $total / 1048576);
                $self->{cards}{memory}->set_text("$used_gb / ${total_gb} GB ($pct)");
            }

            my $swap_total = $mem{SwapTotal} // 0;
            my $swap_free  = $mem{SwapFree} // 0;
            my $swap_used  = $swap_total - $swap_free;
            if ($swap_total > 0) {
                my $pct = sprintf("%.1f%%", 100 * $swap_used / $swap_total);
                my $used_mb  = sprintf("%.0f", $swap_used / 1024);
                my $total_mb = sprintf("%.0f", $swap_total / 1024);
                $self->{cards}{swap}->set_text("${used_mb} / ${total_mb} MB ($pct)");
            } else {
                $self->{cards}{swap}->set_text("No swap");
            }
        }
    };

    # Disk usage (list-form open to avoid shell)
    eval {
        my @lines;
        if (open my $fh, '-|', 'df', '-h',
                '--output=target,size,used,avail,pcent',
                '-x', 'tmpfs', '-x', 'devtmpfs', '-x', 'squashfs') {
            @lines = <$fh>;
            close $fh;
        }
        # Clear previous
        my @children = $self->{disk_box}->get_children;
        $_->destroy for @children;

        shift @lines;  # header
        for my $line (@lines) {
            $line =~ s/^\s+//;
            my ($mount, $size, $used, $avail, $pct) = split /\s+/, $line;
            next unless $mount && $pct;
            $pct =~ s/[^0-9.]//g;
            next unless $pct =~ /^\d/;
            my $row = Gtk3::Box->new('horizontal', 8);
            $row->set_margin_start(4);

            my $mount_label = Gtk3::Label->new($mount);
            $mount_label->set_width_chars(20);
            $mount_label->set_halign('start');
            $row->pack_start($mount_label, FALSE, FALSE, 0);

            # Progress bar
            my $bar = Gtk3::ProgressBar->new;
            $bar->set_fraction(($pct // 0) / 100);
            $bar->set_text("$used / $size ($pct%)");
            $bar->set_show_text(TRUE);
            $row->pack_start($bar, TRUE, TRUE, 0);

            $self->{disk_box}->pack_start($row, FALSE, FALSE, 0);
        }
        $self->{disk_box}->show_all;
    };

    # Top processes (list-form open to avoid shell)
    eval {
        my @lines;
        if (open my $fh, '-|', 'ps', 'aux', '--sort=-%cpu') {
            for (1..11) {
                my $line = <$fh>;
                last unless defined $line;
                push @lines, $line;
            }
            close $fh;
        }
        $self->{proc_store}->clear;
        shift @lines;  # header
        for my $line (@lines) {
            my @fields = split /\s+/, $line, 11;
            next unless @fields >= 11;
            my ($user, $pid, $cpu, $mem) = @fields[0, 1, 2, 3];
            my $cmd = $fields[10] // '';
            $cmd = substr($cmd, 0, 60) . '...' if length($cmd) > 60;
            my $iter = $self->{proc_store}->append;
            $self->{proc_store}->set($iter,
                0, $pid, 1, $user, 2, "$cpu%", 3, "$mem%", 4, $cmd,
            );
        }
    };

    # Update subtitle timestamp
    my $now = strftime('%Y-%m-%d %H:%M:%S', localtime);
    my $tc = PerlDen::Config::theme_colors();
    $self->{subtitle}->set_markup(qq{<span size='small' foreground='$tc->{dim}'>Last updated: $now</span>});

    # Hardware metrics (gracefully skipped if sensors unavailable)
    $self->_refresh_hardware;
}

# ── Hardware sensor helpers ───────────────────────────────────────────────────

sub _refresh_hardware {
    my ($self) = @_;

    # CPU temperature
    my $cpu_temp = _read_cpu_temp();
    $self->{cards}{cpu_temp}->set_text(
        defined $cpu_temp ? sprintf('%.0f %sC', $cpu_temp, "\x{b0}") : 'N/A'
    );

    # GPU: try NVIDIA first, then AMD
    my ($gpu_temp, $gpu_util) = _read_nvidia_gpu();
    ($gpu_temp, $gpu_util) = _read_amd_gpu() unless defined $gpu_temp;

    $self->{cards}{gpu_temp}->set_text(
        defined $gpu_temp ? sprintf('%.0f %sC', $gpu_temp, "\x{b0}") : 'N/A'
    );
    $self->{cards}{gpu_util}->set_text(
        defined $gpu_util ? sprintf('%.0f%%', $gpu_util) : 'N/A'
    );
}

# Read highest CPU temperature from /sys/class/thermal (millidegrees -> Celsius)
sub _read_cpu_temp {
    my $base = '/sys/class/thermal';
    return undef unless -d $base;

    opendir(my $dh, $base) or return undef;
    my @zones = grep { /^thermal_zone/ } readdir $dh;
    closedir $dh;

    my @temps;
    for my $zone (@zones) {
        my $temp_file = "$base/$zone/temp";
        my $type_file = "$base/$zone/type";
        next unless -r $temp_file;

        # Filter to known CPU-relevant zone types
        if (-r $type_file) {
            open my $tf, '<', $type_file or next;
            my $type = do { local $/; <$tf> };
            close $tf;
            chomp($type //= '');
            next unless $type =~ /^(?:x86_pkg_temp|acpitz|cpu)/i;
        }

        open my $fh, '<', $temp_file or next;
        my $raw = do { local $/; <$fh> };
        close $fh;
        next unless defined $raw && $raw =~ /^(\d+)/;
        push @temps, $1 / 1000;
    }

    return undef unless @temps;
    return (sort { $b <=> $a } @temps)[0];  # highest reading
}

# Returns (temp_C, util_pct) from nvidia-smi, or () if unavailable
sub _read_nvidia_gpu {
    my $out = eval {
        open my $fh, '-|', 'nvidia-smi',
            '--query-gpu=temperature.gpu,utilization.gpu',
            '--format=csv,noheader,nounits' or return undef;
        my $l = <$fh>;
        close $fh;
        return undef if $?;
        $l;
    };
    return () unless defined $out;
    chomp $out;
    $out =~ s/\s//g;
    my ($t, $u) = split /,/, $out;
    return () unless defined $t && $t =~ /^\d/;
    return ($t + 0, defined $u && $u =~ /^\d/ ? $u + 0 : undef);
}

# Returns (temp_C, undef) from rocm-smi (AMD GPUs), or () if unavailable
sub _read_amd_gpu {
    my $out = eval {
        open my $fh, '-|', 'rocm-smi', '--showtemp' or return undef;
        local $/;
        my $o = <$fh>;
        close $fh;
        return undef if $?;
        $o;
    };
    return () unless defined $out;
    my ($temp) = $out =~ /Temperature.*?:\s*([\d.]+)/i;
    return () unless defined $temp;
    return ($temp + 0, undef);
}

sub apply_settings {
    my ($self) = @_;
    my $tc = PerlDen::Config::theme_colors();

    # Refresh section headers
    $self->{title_label}->set_markup(
        qq{<span size="x-large" weight="bold" foreground="$tc->{accent}">⊞ System Dashboard</span>}
    ) if $self->{title_label};
    $self->{disk_label}->set_markup(
        qq{<span weight="bold" foreground="$tc->{accent}">Disk Usage</span>}
    ) if $self->{disk_label};
    $self->{proc_label}->set_markup(
        qq{<span weight="bold" foreground="$tc->{accent}">Top Processes (by CPU)</span>}
    ) if $self->{proc_label};
    $self->{hw_label}->set_markup(
        qq{<span weight="bold" foreground="$tc->{accent}">Hardware</span>}
    ) if $self->{hw_label};

    # Refresh card labels
    for my $m (@{$self->{markup_widgets} // []}) {
        my $color = $tc->{$m->{key}} // $tc->{subtext};
        $m->{widget}->set_markup(sprintf($m->{template}, $color));
    }
}

sub widget { return $_[0]->{widget} }

1;

__END__

=head1 NAME

PerlDen::GUI::Dashboard - Real-time system overview dashboard

=head1 DESCRIPTION

A scrollable panel displaying live system metrics: hostname, kernel,
uptime, load average, CPU usage, memory, swap, disk usage (with progress
bars), and the top processes by CPU.  Metrics refresh automatically every
5 seconds from F</proc> and standard Linux commands.

=head1 METHODS

=over 4

=item B<new(main_window =E<gt> $mw)>

Build the dashboard UI and start the auto-refresh timer.

=item B<apply_settings()>

Refresh colours and markup to match the current theme.

=item B<widget()>

Return the top-level GTK widget.

=back

=head1 AUTHOR

James Temple <james@amiga-fan.net>

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2026 Honey Badger Universe

MIT License

=cut
