#!/usr/bin/env perl
# ============================================================================
# Template: Web/API Client Script
# Description: HTTP client with JSON parsing and error handling
# ============================================================================
use strict;
use warnings;
use HTTP::Tiny;
use JSON::MaybeXS qw(decode_json encode_json);
use Getopt::Long;

my $url     = '';
my $method  = 'GET';
my $data;
my $header;
my $verbose = 0;

GetOptions(
    'url=s'     => \$url,
    'method=s'  => \$method,
    'data=s'    => \$data,
    'header=s'  => \$header,
    'verbose|v' => \$verbose,
) or die "Usage: $0 --url URL [--method GET|POST] [--data JSON] [--header 'Key: Value']\n";

die "URL required (--url)\n" unless $url;

# ── Build Request ──────────────────────────────────────────
my $http = HTTP::Tiny->new(
    agent   => 'Perl Den-Client/1.0',
    timeout => 30,
);

my %options;
if ($data) {
    $options{content} = $data;
    $options{headers}{'Content-Type'} = 'application/json';
}
if ($header && $header =~ /^(.+?):\s*(.+)$/) {
    $options{headers}{$1} = $2;
}

# ── Execute Request ────────────────────────────────────────
print STDERR "$method $url\n" if $verbose;
my $response = $http->request($method, $url, \%options);

# ── Process Response ───────────────────────────────────────
if ($verbose) {
    print STDERR "Status: $response->{status} $response->{reason}\n";
    for my $h (sort keys %{$response->{headers}}) {
        print STDERR "  $h: $response->{headers}{$h}\n";
    }
    print STDERR "\n";
}

if ($response->{success}) {
    my $body = $response->{content};

    # Try to pretty-print JSON
    eval {
        my $parsed = decode_json($body);
        print encode_json($parsed);  # or use Data::Dumper for debug
        print "\n";
    };
    if ($@) {
        print $body;  # Not JSON, print raw
    }
} else {
    die sprintf("HTTP %s: %s\n%s\n",
        $response->{status}, $response->{reason},
        $response->{content} // '');
}
