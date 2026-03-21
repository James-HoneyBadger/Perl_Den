#!/usr/bin/env perl
# docker_monitor.pl — Docker container and image monitoring
use strict;
use warnings;
use FindBin qw($RealBin);
use lib "$RealBin/../lib";
use HBPerl::Scripts::DockerMonitor;

my $result = HBPerl::Scripts::DockerMonitor::run();
print HBPerl::Scripts::DockerMonitor::format_report($result);
