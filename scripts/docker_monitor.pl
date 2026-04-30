#!/usr/bin/env perl
# docker_monitor.pl — Docker container and image monitoring
use strict;
use warnings;
use FindBin qw($RealBin);
use lib "$RealBin/../lib";
use BadgerOps::Scripts::DockerMonitor;

my $result = BadgerOps::Scripts::DockerMonitor::run();
print BadgerOps::Scripts::DockerMonitor::format_report($result);
