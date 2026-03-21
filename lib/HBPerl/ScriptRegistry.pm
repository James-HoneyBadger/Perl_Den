package HBPerl::ScriptRegistry;
# ============================================================================
# HBPerl::ScriptRegistry - Single source of truth for the script index
# ============================================================================
use strict;
use warnings;
use Exporter 'import';

our $VERSION = '1.00';
our @EXPORT_OK = qw(script_index script_categories find_script user_scripts_dir);

# User scripts directory
my $USER_SCRIPTS_DIR;

sub user_scripts_dir {
    unless ($USER_SCRIPTS_DIR) {
        eval { require File::HomeDir };
        my $home = $ENV{HOME} || (eval { File::HomeDir->my_home } // '');
        $USER_SCRIPTS_DIR = "$home/.config/hb_perl/scripts" if $home;
    }
    return $USER_SCRIPTS_DIR;
}

# Canonical list of all toolkit scripts.
# Each entry: [ display_name, script_filename, module_name, description, category ]
my @SCRIPTS = (
    ['System Information',  'system_info.pl',          'HBPerl::Scripts::SystemInfo',         'Collect CPU, RAM, kernel, uptime info',     'System Info'],
    ['Disk Usage Analyzer', 'disk_usage.pl',           'HBPerl::Scripts::DiskUsage',          'Analyze disk usage by directory',           'System Info'],
    ['Process Manager',     'process_manager.pl',      'HBPerl::Scripts::ProcessManager',     'List and manage running processes',         'System Info'],
    ['Service Monitor',     'service_monitor.pl',      'HBPerl::Scripts::ServiceMonitor',     'Check systemd service status',              'System Info'],
    ['Log Analyzer',        'log_analyzer.pl',         'HBPerl::Scripts::LogAnalyzer',        'Parse and analyze system logs',             'Log Analysis'],
    ['Failed Login Detector','failed_login_detector.pl','HBPerl::Scripts::FailedLoginDetector','Detect brute-force SSH attempts',           'Log Analysis'],
    ['User Audit',          'user_audit.pl',           'HBPerl::Scripts::UserAudit',          'Audit user accounts and security',          'User Management'],
    ['Cron Manager',        'cron_manager.pl',         'HBPerl::Scripts::CronManager',        'View and manage cron jobs',                 'User Management'],
    ['Network Diagnostics', 'network_diag.pl',         'HBPerl::Scripts::NetworkDiag',        'DNS lookups, ping, interface info',         'Network'],
    ['Port Scanner',        'port_scanner.pl',         'HBPerl::Scripts::PortScanner',        'Scan listening ports and services',         'Network'],
    ['SSL Checker',         'ssl_checker.pl',          'HBPerl::Scripts::SSLChecker',         'Check SSL certificate expiry',              'Network'],
    ['File Permissions',    'file_permissions.pl',     'HBPerl::Scripts::FilePermissions',    'Audit SUID/SGID/world-writable files',      'Security'],
    ['Backup Manager',      'backup_manager.pl',       'HBPerl::Scripts::BackupManager',      'Create and manage backups',                 'Backup & Config'],
    ['Config Diff',         'config_diff.pl',          'HBPerl::Scripts::ConfigDiff',         'Compare config files against baselines',    'Backup & Config'],
    ['Duplicate Finder',    'duplicate_finder.pl',     'HBPerl::Scripts::DuplicateFinder',    'Find duplicate files by hash',              'Backup & Config'],
    ['Firewall Auditor',    'firewall_auditor.pl',     'HBPerl::Scripts::FirewallAuditor',    'Audit iptables/nftables firewall rules',    'Security'],
    ['Docker Monitor',      'docker_monitor.pl',       'HBPerl::Scripts::DockerMonitor',      'Container status, images, disk usage',      'Containers'],
    ['Bandwidth Monitor',   'bandwidth_monitor.pl',    'HBPerl::Scripts::BandwidthMonitor',   'Per-interface network traffic rates',       'Network'],
    ['Package Auditor',     'package_auditor.pl',      'HBPerl::Scripts::PackageAuditor',     'Installed packages, updates, orphans',      'System Info'],
    ['Systemd Analyzer',    'systemd_analyzer.pl',     'HBPerl::Scripts::SystemdAnalyzer',    'Boot time analysis, failed units',          'System Info'],
);

# Category metadata: display name => { icon, emoji }
my %CATEGORY_META = (
    'System Info'      => { icon => 'computer-symbolic',          emoji => '🖥' },
    'Log Analysis'     => { icon => 'text-x-generic-symbolic',    emoji => '📋' },
    'User Management'  => { icon => 'system-users-symbolic',      emoji => '👤' },
    'Network'          => { icon => 'network-wired-symbolic',     emoji => '🌐' },
    'Security'         => { icon => 'security-high-symbolic',     emoji => '🔒' },
    'Containers'       => { icon => 'application-x-executable-symbolic', emoji => '🐳' },
    'Backup & Config'  => { icon => 'drive-harddisk-symbolic',    emoji => '💾' },
    'User Scripts'     => { icon => 'user-home-symbolic',          emoji => '👤' },
);

# Return flat list of all scripts (built-in + user) as arrayrefs
sub script_index {
    return (@SCRIPTS, _load_user_scripts());
}

# Return ordered list of categories with their scripts, for GUI tree/menus
# Returns: ( { name, icon, emoji, items => [ [name, filename, desc], ... ] }, ... )
sub script_categories {
    my @order = ('System Info', 'Log Analysis', 'User Management', 'Network', 'Security', 'Containers', 'Backup & Config', 'User Scripts');
    my %by_cat;

    for my $s (@SCRIPTS, _load_user_scripts()) {
        my ($name, $file, $module, $desc, $cat) = @$s;
        push @{$by_cat{$cat}}, [$name, $file, $desc];
    }

    my @result;
    for my $cat (@order) {
        next unless $by_cat{$cat};
        my $meta = $CATEGORY_META{$cat} // {};
        push @result, {
            name  => $cat,
            icon  => $meta->{icon}  // 'folder-symbolic',
            emoji => $meta->{emoji} // '📁',
            items => $by_cat{$cat},
        };
    }
    return @result;
}

# Find a script by shorthand name (fuzzy match on filename stem)
# Returns: (display_name, filename, module, description) or empty list
sub find_script {
    my ($query) = @_;
    return () unless defined $query;
    $query =~ s/\.pl$//;
    $query = lc($query);

    my @all = (@SCRIPTS, _load_user_scripts());

    for my $s (@all) {
        my $stem = lc($s->[1]);
        $stem =~ s/\.pl$//;
        return @$s if $stem eq $query;
    }

    # Partial match
    for my $s (@all) {
        my $stem = lc($s->[1]);
        $stem =~ s/\.pl$//;
        return @$s if $stem =~ /\Q$query\E/;
    }

    return ();
}

# ── User/plugin script discovery ──

our @_user_scripts_cache;
our $_user_scripts_mtime = 0;

sub _load_user_scripts {
    my $dir = user_scripts_dir();
    return () unless $dir && -d $dir;

    # Cache based on directory mtime
    my $mtime = (stat($dir))[9] // 0;
    return @_user_scripts_cache if $mtime == $_user_scripts_mtime && @_user_scripts_cache;
    $_user_scripts_mtime = $mtime;
    @_user_scripts_cache = ();

    opendir(my $dh, $dir) or return ();
    my @files = sort grep { /\.pl$/ } readdir $dh;
    closedir $dh;

    for my $file (@files) {
        my $path = "$dir/$file";
        next unless -f $path;

        # Extract metadata from comment header lines
        my ($name, $desc);
        if (open my $fh, '<', $path) {
            while (my $line = <$fh>) {
                last if $. > 20;  # Only scan first 20 lines
                if ($line =~ /^#\s*Name:\s*(.+)/i) {
                    $name = $1;
                    $name =~ s/\s+$//;
                }
                if ($line =~ /^#\s*Description:\s*(.+)/i) {
                    $desc = $1;
                    $desc =~ s/\s+$//;
                }
            }
            close $fh;
        }

        # Default name from filename
        unless ($name) {
            $name = $file;
            $name =~ s/\.pl$//;
            $name =~ s/_/ /g;
            $name =~ s/\b(\w)/uc($1)/ge;
        }
        $desc //= 'User script';

        push @_user_scripts_cache, [$name, $path, '', $desc, 'User Scripts'];
    }

    return @_user_scripts_cache;
}

1;

__END__

=head1 NAME

HBPerl::ScriptRegistry - Canonical script index for the HB Perl toolkit

=head1 SYNOPSIS

    use HBPerl::ScriptRegistry qw(script_index script_categories find_script);

    # Flat list
    for my $s (script_index()) {
        my ($name, $file, $module, $desc, $category) = @$s;
    }

    # Grouped by category (for GUI menus/trees)
    for my $cat (script_categories()) {
        print "$cat->{emoji}  $cat->{name}\n";
        for my $item (@{$cat->{items}}) {
            print "  $item->[0] ($item->[1])\n";
        }
    }

    # Look up by name
    my ($name, $file, $module, $desc) = find_script('disk_usage');

=head1 DESCRIPTION

Single source of truth for the 20 bundled sysadmin scripts.  The CLI, TUI,
GUI, and test suite all query this module rather than scanning the filesystem.

Each script entry is an arrayref:

    [ display_name, script_filename, module_name, description, category ]

Categories: System Info, Log Analysis, User Management, Network, Security,
Backup & Config.

=head1 EXPORTED FUNCTIONS

=over 4

=item B<script_index()>

Return a flat list of all script entries as arrayrefs.

=item B<script_categories()>

Return an ordered list of category hashrefs, each containing C<name>,
C<icon>, C<emoji>, and C<items> (arrayrefs of C<[name, filename, desc]>).
Used by the GUI sidebar and menus.

=item B<find_script($query)>

Fuzzy-match a script by filename stem.  Returns the full entry
C<($name, $file, $module, $desc, $category)> or an empty list.

=back

=head1 AUTHOR

James

=head1 LICENSE

MIT

=cut
