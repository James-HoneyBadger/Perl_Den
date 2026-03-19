#!/usr/bin/env perl
# ============================================================================
# Template: OOP Module
# Description: A well-structured Perl module using Moo (lightweight OOP)
# ============================================================================
package My::Module;
use strict;
use warnings;

our $VERSION = '0.01';

# ── Constructor ────────────────────────────────────────────
sub new {
    my ($class, %args) = @_;
    my $self = bless {
        name    => $args{name}    // 'default',
        verbose => $args{verbose} // 0,
        _cache  => {},
    }, $class;
    return $self;
}

# ── Accessors ──────────────────────────────────────────────
sub name    { return $_[0]->{name} }
sub verbose { return $_[0]->{verbose} }

# ── Public Methods ─────────────────────────────────────────
sub greet {
    my ($self) = @_;
    return "Hello from " . $self->name . "!";
}

sub process {
    my ($self, $data) = @_;
    die "No data provided\n" unless defined $data;

    $self->_log("Processing data...") if $self->verbose;

    # TODO: Add your processing logic
    my $result = uc($data);

    $self->_log("Done processing") if $self->verbose;
    return $result;
}

# ── Private Methods ────────────────────────────────────────
sub _log {
    my ($self, $msg) = @_;
    print STDERR "[" . $self->name . "] $msg\n";
}

1;

__END__

=head1 NAME

My::Module - Brief description of this module

=head1 SYNOPSIS

    use My::Module;
    my $obj = My::Module->new(name => 'example', verbose => 1);
    print $obj->greet();
    my $result = $obj->process("some data");

=head1 METHODS

=head2 new(%args)

Constructor. Accepts: name, verbose.

=head2 greet()

Returns a greeting string.

=head2 process($data)

Processes the given data and returns the result.

=head1 AUTHOR

Your Name

=cut
