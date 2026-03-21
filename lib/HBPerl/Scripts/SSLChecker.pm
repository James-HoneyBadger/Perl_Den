package HBPerl::Scripts::SSLChecker;
# ============================================================================
# SSL/TLS certificate checker — expiry, chain, cipher analysis
# ============================================================================
use strict;
use warnings;
use IO::Socket::SSL;
use IO::Socket::INET;
use POSIX qw(strftime);

sub run {
    my (%args) = @_;
    my $hosts   = $args{hosts}   // ['localhost'];
    my $port    = $args{port}    // 443;
    my $timeout = $args{timeout} // 10;

    my @results;
    for my $host (@$hosts) {
        push @results, _check_host($host, $port, $timeout);
    }

    # ── Local certificate files ──
    my $local_certs = _scan_local_certs();

    return {
        checks     => \@results,
        local_certs => $local_certs,
    };
}

sub format_report {
    my ($result) = @_;

    my $report = <<"EOF";
╔══════════════════════════════════════════════════════════════╗
║                SSL / TLS CERTIFICATE CHECKER                  ║
╚══════════════════════════════════════════════════════════════╝

EOF

    $report .= "── Remote Certificate Checks ─────────────────────────────────\n";
    for my $c (@{$result->{checks}}) {
        $report .= "\n  Host: $c->{host}:$c->{port}\n";
        if ($c->{error}) {
            $report .= "  ✘ ERROR: $c->{error}\n";
            next;
        }
        my $days = $c->{days_remaining} // 0;
        my $status = $days > 30 ? '✔ OK' : $days > 7 ? '⚠ EXPIRING SOON' : '✘ CRITICAL';

        $report .= "  Status:      $status\n";
        $report .= "  Subject:     $c->{subject}\n"     if $c->{subject};
        $report .= "  Issuer:      $c->{issuer}\n"      if $c->{issuer};
        $report .= "  Not Before:  $c->{not_before}\n"  if $c->{not_before};
        $report .= "  Not After:   $c->{not_after}\n"   if $c->{not_after};
        $report .= "  Days Left:   $days\n";
        $report .= "  Protocol:    $c->{ssl_version}\n"  if $c->{ssl_version};
        $report .= "  Cipher:      $c->{cipher}\n"       if $c->{cipher};
        $report .= "  Key Size:    $c->{cipher_bits} bits\n" if $c->{cipher_bits};
        if ($c->{san} && @{$c->{san}}) {
            $report .= "  SANs:        " . join(', ', @{$c->{san}}) . "\n";
        }
    }

    # Local certs
    my @local = @{$result->{local_certs} // []};
    if (@local) {
        $report .= "\n── Local Certificate Files ───────────────────────────────────\n";
        for my $lc (@local) {
            $report .= sprintf("  %-50s %s\n", $lc->{file}, $lc->{status});
        }
    }

    return $report;
}

sub _check_host {
    my ($host, $port, $timeout) = @_;
    my %info = (host => $host, port => $port);

    my $cl = eval {
        IO::Socket::SSL->new(
            PeerAddr        => $host,
            PeerPort        => $port,
            Timeout         => $timeout,
            SSL_verify_mode => IO::Socket::SSL::SSL_VERIFY_NONE(),
            SSL_hostname    => $host,
        );
    };

    if (!$cl) {
        $info{error} = IO::Socket::SSL::errstr() || $@ || 'Connection failed';
        return \%info;
    }

    # Extract cert info
    eval {
        $info{ssl_version} = $cl->get_sslversion();
        $info{cipher}      = $cl->get_cipher();
        $info{cipher_bits} = ($cl->get_cipher()
                              ? Net::SSLeay::SSL_get_cipher_bits(
                                    $cl->_get_ssl_object(), my $algbits)
                              : undef);
        # Prefer simpler approach to bits
        $info{cipher_bits} //= '';

        if (my $cert = $cl->peer_certificate) {
            my $subject = Net::SSLeay::X509_NAME_oneline(
                Net::SSLeay::X509_get_subject_name($cert));
            my $issuer  = Net::SSLeay::X509_NAME_oneline(
                Net::SSLeay::X509_get_issuer_name($cert));

            $info{subject} = $subject;
            $info{issuer}  = $issuer;

            # Dates
            my $not_before = Net::SSLeay::P_ASN1_TIME_get_isotime(
                Net::SSLeay::X509_get_notBefore($cert));
            my $not_after  = Net::SSLeay::P_ASN1_TIME_get_isotime(
                Net::SSLeay::X509_get_notAfter($cert));

            $info{not_before} = $not_before;
            $info{not_after}  = $not_after;

            # Days remaining
            if ($not_after && $not_after =~ /^(\d{4})-(\d{2})-(\d{2})/) {
                require Time::Local;
                my $exp = Time::Local::timegm(0, 0, 0, $3, $2 - 1, $1);
                $info{days_remaining} = int(($exp - time()) / 86400);
            }

            # SANs
            my @san;
            eval {
                my @altnames = Net::SSLeay::X509_get_subjectAltNames($cert);
                while (@altnames) {
                    my $type = shift @altnames;
                    my $val  = shift @altnames;
                    push @san, $val if $type == 2;   # GEN_DNS
                }
            };
            $info{san} = \@san if @san;
        }
    };
    $info{parse_error} = $@ if $@;

    close $cl;
    return \%info;
}

sub _scan_local_certs {
    my @certs;
    my @paths = (
        '/etc/ssl/certs',
        '/etc/pki/tls/certs',
        '/etc/letsencrypt/live',
    );
    for my $dir (@paths) {
        next unless -d $dir;
        opendir my $dh, $dir or next;
        while (my $f = readdir $dh) {
            next unless $f =~ /\.(pem|crt|cer)$/;
            my $path = "$dir/$f";
            my $status = 'present';
            # Quick expiry check via openssl if available
            my $out = '';
            if (open my $ssl_fh, '-|', 'openssl', 'x509', '-enddate', '-noout', '-in', $path) {
                $out = do { local $/; <$ssl_fh> };
                close $ssl_fh;
            }
            if ($out && $out =~ /notAfter=(.+)/) {
                $status = "expires: $1";
            }
            push @certs, { file => $path, status => $status };
        }
        closedir $dh;
    }
    return \@certs;
}

1;

__END__

=head1 NAME

HBPerl::Scripts::SSLChecker - SSL/TLS certificate expiry and analysis

=head1 SYNOPSIS

    use HBPerl::Scripts::SSLChecker;
    my $r = HBPerl::Scripts::SSLChecker::run(
        hosts   => ['example.com', 'github.com'],
        port    => 443,
        timeout => 5,
    );
    print HBPerl::Scripts::SSLChecker::format_report($r);

=head1 DESCRIPTION

Connects to remote hosts to inspect SSL/TLS certificates (subject,
issuer, validity, SANs, cipher) and scans local certificate files
(F</etc/ssl/certs>) for upcoming expiry dates.

=head1 EXPORTED FUNCTIONS

=over 4

=item B<run(%args)>

Parameters: C<hosts> (array-ref of hostnames), C<port> (default 443),
C<timeout> (seconds).

Returns a hash-ref with remote certificate details and local cert
expiry information.

=item B<format_report($result)>

Format the hash-ref from C<run()> as a human-readable report string.

=back

=head1 AUTHOR

James

=head1 LICENSE

MIT

=cut
