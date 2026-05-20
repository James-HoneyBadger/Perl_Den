#!/usr/bin/env perl
# docker_monitor.pl — Docker container and image monitoring
use strict;
use warnings;
use FindBin qw($RealBin);
use lib "$RealBin/../lib";
use PerlDen::Scripts::DockerMonitor;

my $result = PerlDen::Scripts::DockerMonitor::run();
print PerlDen::Scripts::DockerMonitor::format_report($result);
