#!/usr/bin/env perl
# ============================================================================
# t/27_mocked_system.t — System-command-dependent scripts tested with mocks
#
# Exercises format_report() with hand-crafted data, and uses Test::MockModule
# to stub out private helpers that shell out to docker, systemctl, etc.
# These tests run reliably in any CI environment with no external tooling.
# ============================================================================
use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../lib";

my $HAVE_MOCK = eval { require Test::MockModule; 1 };

# ── 1. ServiceMonitor — format_report with hand-crafted data ──────────────

use_ok('PerlDen::Scripts::ServiceMonitor');

subtest 'ServiceMonitor format_report with mock data' => sub {
    my $result = {
        services => [
            { unit => 'sshd.service',    load_state => 'loaded', active => 'active',
              sub_state => 'running',  description => 'OpenSSH Daemon',  enabled => 'enabled'  },
            { unit => 'crond.service',   load_state => 'loaded', active => 'active',
              sub_state => 'running',  description => 'Cron Daemon',     enabled => 'enabled'  },
            { unit => 'broken.service',  load_state => 'loaded', active => 'failed',
              sub_state => 'failed',   description => 'Broken Service',  enabled => 'disabled' },
        ],
        failed => [
            { unit => 'broken.service',  load_state => 'loaded', active => 'failed',
              sub_state => 'failed',   description => 'Broken Service',  enabled => 'disabled' },
        ],
        counts => { active => 2, failed => 1 },
        total  => 3,
    };

    my $report = PerlDen::Scripts::ServiceMonitor::format_report($result);
    ok(length($report) > 50, 'report has content');
    like($report, qr/sshd\.service/,   'report lists sshd');
    like($report, qr/broken\.service/, 'report lists broken service');
    like($report, qr/failed/i,         'report mentions failed state');
};

subtest 'ServiceMonitor format_report with no failed services' => sub {
    my $result = {
        services => [
            { unit => 'nginx.service', load_state => 'loaded', active => 'active',
              sub_state => 'running', description => 'NGINX', enabled => 'enabled' },
        ],
        failed => [],
        counts => { active => 1 },
        total  => 1,
    };
    my $report = PerlDen::Scripts::ServiceMonitor::format_report($result);
    ok(length($report) > 20, 'report generated');
    like($report, qr/nginx/i, 'report mentions nginx');
};

# ── 2. DockerMonitor — mock private helpers ───────────────────────────────

use_ok('PerlDen::Scripts::DockerMonitor');

subtest 'DockerMonitor run() with mocked helpers (docker available)' => sub {
    plan(skip_all => 'Test::MockModule not available') unless $HAVE_MOCK;

    my $mock = Test::MockModule->new('PerlDen::Scripts::DockerMonitor');

    $mock->mock(_docker_available  => sub { 1 });
    $mock->mock(_get_containers    => sub {
        return [
            { id => 'abc123def456', name => 'web',  status => 'Up 2 days',
              ports => '80/tcp', image => 'nginx:latest' },
            { id => '789xyz000111', name => 'db',   status => 'Exited (0)',
              ports => '',       image => 'postgres:14'  },
        ];
    });
    $mock->mock(_get_images        => sub {
        return [
            { repo => 'nginx', tag => 'latest', size => '133MB', created => '2 weeks ago' },
            { repo => 'postgres', tag => '14',  size => '374MB', created => '1 month ago' },
        ];
    });
    $mock->mock(_get_volumes       => sub { return ['pgdata', 'webstatic'] });
    $mock->mock(_get_dangling_images => sub { return [] });
    $mock->mock(_get_disk_usage    => sub { return ['TYPE  TOTAL  ACTIVE  SIZE  RECLAIMABLE',
                                                    'Images 2  1  507MB  374MB (73%)'] });

    my $result = PerlDen::Scripts::DockerMonitor::run();
    ok($result->{available}, 'docker available flag set');
    is(scalar @{$result->{containers}}, 2, 'got 2 containers');
    is($result->{containers}[0]{name}, 'web', 'first container is web');
    is(scalar @{$result->{images}}, 2, 'got 2 images');

    my $report = PerlDen::Scripts::DockerMonitor::format_report($result);
    like($report, qr/nginx/,    'report mentions nginx');
    like($report, qr/postgres/, 'report mentions postgres');
    like($report, qr/Exited/,   'report shows exited container');
};

subtest 'DockerMonitor run() with mocked helpers (docker unavailable)' => sub {
    plan(skip_all => 'Test::MockModule not available') unless $HAVE_MOCK;

    my $mock = Test::MockModule->new('PerlDen::Scripts::DockerMonitor');
    $mock->mock(_docker_available => sub { 0 });

    my $result = PerlDen::Scripts::DockerMonitor::run();
    ok(!$result->{available}, 'available is false');
    ok(!exists $result->{containers}, 'no containers key when unavailable');

    my $report = PerlDen::Scripts::DockerMonitor::format_report($result);
    like($report, qr/not installed|not running/i, 'report explains docker unavailability');
};

subtest 'DockerMonitor format_report with dangling images' => sub {
    my $result = {
        available => 1,
        containers => [],
        images     => [],
        volumes    => [],
        dangling   => ['sha256:deadbeef1234 45MB', 'sha256:cafebabe5678 12MB'],
        disk_usage => [],
    };
    my $report = PerlDen::Scripts::DockerMonitor::format_report($result);
    like($report, qr/Dangling|dangling|prune/i, 'report mentions dangling images');
};

# ── 3. PortScanner — format_report with hand-crafted data ────────────────

use_ok('PerlDen::Scripts::PortScanner');

subtest 'PortScanner format_report with mock data' => sub {
    my $result = {
        listening   => [
            { proto => 'tcp', state => 'LISTEN', local => '0.0.0.0:22',  peer => '*', process => 'sshd' },
            { proto => 'tcp', state => 'LISTEN', local => '0.0.0.0:80',  peer => '*', process => 'nginx' },
            { proto => 'tcp', state => 'LISTEN', local => '0.0.0.0:443', peer => '*', process => 'nginx' },
        ],
        established => [
            { proto => 'tcp', local => '10.0.0.1:22', peer => '10.0.0.2:54321', process => 'sshd' },
        ],
        service_map => { 22 => 'SSH', 80 => 'HTTP', 443 => 'HTTPS' },
        scan        => undef,
    };

    my $report = PerlDen::Scripts::PortScanner::format_report($result);
    ok(length($report) > 50, 'report has content');
    like($report, qr/:22.*SSH|SSH.*22/s, 'report shows SSH on port 22');
    like($report, qr/:80.*HTTP|HTTP.*80/s, 'report shows HTTP on port 80');
};

# ── 4. NetworkDiag — format_report with hand-crafted data ────────────────

use_ok('PerlDen::Scripts::NetworkDiag');

subtest 'NetworkDiag format_report with mock data' => sub {
    my $result = {
        interfaces => [
            { name => 'eth0', flags => 'UP BROADCAST RUNNING', mtu => 1500,
              inet => '192.168.1.10', netmask => '255.255.255.0', inet6 => undef },
            { name => 'lo',   flags => 'UP LOOPBACK RUNNING',   mtu => 65536,
              inet => '127.0.0.1',   netmask => '255.0.0.0',     inet6 => undef },
        ],
        routes     => [
            { dest => '0.0.0.0', gateway => '192.168.1.1', iface => 'eth0', metric => 100 },
        ],
        gateway    => '192.168.1.1',
        dns_servers => ['8.8.8.8', '8.8.4.4'],
        dns        => { lookup => 'localhost', address => '127.0.0.1', success => 1 },
        ping       => { host => '127.0.0.1', success => 1, avg_ms => 0.2 },
    };

    my $report = PerlDen::Scripts::NetworkDiag::format_report($result);
    ok(length($report) > 50, 'report has content');
    like($report, qr/eth0|192\.168/, 'report shows interface info');
    like($report, qr/8\.8\.8\.8/,   'report shows DNS servers');
};

# ── 5. BandwidthMonitor — format_report with hand-crafted data ───────────

use_ok('PerlDen::Scripts::BandwidthMonitor');

subtest 'BandwidthMonitor format_report with mock data' => sub {
    my $result = {
        interval   => 1,
        interfaces => [
            { name     => 'eth0',
              rx_bytes  => 104857600, tx_bytes  => 52428800,
              rx_rate   => 1048576,   tx_rate   => 524288,
              rx_errors => 0,         tx_errors => 0,
              rx_dropped => 0,        tx_dropped => 0,
            },
        ],
    };

    my $report = PerlDen::Scripts::BandwidthMonitor::format_report($result);
    ok(length($report) > 30, 'report has content');
    like($report, qr/eth0/,            'report shows eth0');
    like($report, qr/Bandwidth|BANDWIDTH|RX|TX/i, 'report has bandwidth headers');
};

# ── 6. FirewallAuditor — format_report with hand-crafted data ────────────

use_ok('PerlDen::Scripts::FirewallAuditor');

subtest 'FirewallAuditor format_report with mock data' => sub {
    my $result = {
        firewall_type  => 'iptables',
        iptables       => {
            INPUT  => { policy => 'DROP',   rules => ['-A INPUT -p tcp --dport 22 -j ACCEPT',
                                                      '-A INPUT -p tcp --dport 80 -j ACCEPT'] },
            OUTPUT => { policy => 'ACCEPT', rules => [] },
        },
        nftables       => [],
        unmatched_ports => [],
    };

    my $report = PerlDen::Scripts::FirewallAuditor::format_report($result);
    ok(length($report) > 30, 'report has content');
    like($report, qr/iptables|INPUT/i, 'report mentions firewall rules');
    like($report, qr/22/,              'report shows port 22 rule');
};

# ── 7. SystemdAnalyzer — format_report with hand-crafted data ────────────

use_ok('PerlDen::Scripts::SystemdAnalyzer');

subtest 'SystemdAnalyzer format_report with mock data' => sub {
    my $result = {
        available    => 1,
        boot_time    => ['Startup finished in 3.1s (kernel) + 9.2s (userspace) = 12.345s',
                         'graphical.target reached after 9.1s in userspace.'],
        unit_count   => { loaded => 187, active => 162, failed => 0 },
        blame        => [
            { time => '3.200s', unit => 'NetworkManager-wait-online.service' },
            { time => '1.500s', unit => 'systemd-udev-settle.service' },
            { time => '0.800s', unit => 'plymouth-quit-wait.service' },
        ],
        failed_units => [],
        timers       => [
            { timer => 'fstrim.timer', next => 'Sun 2026-05-03 00:00',
              activates => 'fstrim.service' },
        ],
    };

    my $report = PerlDen::Scripts::SystemdAnalyzer::format_report($result);
    ok(length($report) > 50, 'report has content');
    like($report, qr/12\.345s/,   'report shows boot time');
    like($report, qr/NetworkManager/, 'report shows blame entries');
};

subtest 'SystemdAnalyzer format_report when systemd unavailable' => sub {
    my $result = { available => 0 };
    my $report = PerlDen::Scripts::SystemdAnalyzer::format_report($result);
    like($report, qr/not available|systemd/i, 'report explains systemd unavailability');
};

# ── 8. PackageAuditor — format_report with hand-crafted data ─────────────

use_ok('PerlDen::Scripts::PackageAuditor');

subtest 'PackageAuditor format_report with mock data' => sub {
    my $result = {
        pkg_manager => 'pacman',
        installed   => 842,
        updates     => [
            { name => 'linux',       old => '6.8.1', new => '6.8.2' },
            { name => 'glibc',       old => '2.39',  new => '2.40'  },
        ],
        orphaned    => ['python-six', 'perl-local-lib'],
        recent      => [
            { date => '2026-04-29', name => 'firefox', version => '125.0' },
        ],
    };

    my $report = PerlDen::Scripts::PackageAuditor::format_report($result);
    ok(length($report) > 50, 'report has content');
    like($report, qr/pacman|linux|glibc/i, 'report shows package info');
    like($report, qr/orphan|python-six/i,  'report shows orphaned packages');
};

done_testing();
