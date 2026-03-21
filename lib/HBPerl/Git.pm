package HBPerl::Git;
# ============================================================================
# HBPerl::Git - Lightweight git integration for status bar and file browser
# ============================================================================
use strict;
use warnings;
use File::Basename qw(dirname);
use Carp qw(carp);

# TTL-based cache for git results (avoids repeated subprocess spawns)
my %_cache;        # key => { value => ..., expires => time() + TTL }
my $_cache_ttl = 2; # seconds

sub _cache_get {
    my ($key) = @_;
    my $entry = $_cache{$key};
    return undef unless $entry && time() < $entry->{expires};
    return $entry->{value};
}

sub _cache_set {
    my ($key, $value) = @_;
    $_cache{$key} = { value => $value, expires => time() + $_cache_ttl };
    return $value;
}

sub cache_clear { %_cache = () }

# Check if the given directory is inside a git working tree
sub is_git_repo {
    my ($dir) = @_;
    $dir //= '.';
    my $key = "is_git:$dir";
    my $cached = _cache_get($key);
    return $cached if defined $cached;
    my $out = _run_git($dir, 'rev-parse', '--is-inside-work-tree');
    my $result = defined $out && $out =~ /^true/ ? 1 : 0;
    return _cache_set($key, $result);
}

# Return the current branch name, or undef if not in a repo
sub current_branch {
    my ($dir) = @_;
    $dir //= '.';
    my $key = "branch:$dir";
    my $cached = _cache_get($key);
    return $cached if defined $cached;
    my $branch = _run_git($dir, 'rev-parse', '--abbrev-ref', 'HEAD');
    return _cache_set($key, undef) unless defined $branch;
    chomp $branch;
    return _cache_set($key, $branch eq '' ? undef : $branch);
}

# Return a hash of file statuses from git status --porcelain
# Keys are file paths (relative to repo root), values are status codes
#   M = modified, A = added, D = deleted, ? = untracked, R = renamed
sub status {
    my ($dir) = @_;
    $dir //= '.';
    my $key = "status:$dir";
    my $cached = _cache_get($key);
    return $cached if defined $cached;
    my $raw = _run_git($dir, 'status', '--porcelain', '-uall');
    return _cache_set($key, {}) unless defined $raw;

    my %files;
    for my $line (split /\n/, $raw) {
        next unless $line =~ /^(.{2})\s+(.+)$/;
        my ($code, $path) = ($1, $2);
        # Simplify status codes
        if ($code =~ /\?/) {
            $files{$path} = '?';
        } elsif ($code =~ /A/) {
            $files{$path} = 'A';
        } elsif ($code =~ /D/) {
            $files{$path} = 'D';
        } elsif ($code =~ /R/) {
            $files{$path} = 'R';
        } elsif ($code =~ /[MC]/) {
            $files{$path} = 'M';
        }
    }
    return _cache_set($key, \%files);
}

# Return a one-line summary: "main | 3M 1? 2A"
sub status_summary {
    my ($dir) = @_;
    $dir //= '.';
    my $branch = current_branch($dir);
    return undef unless defined $branch;

    my $st = status($dir);
    my %counts;
    $counts{$_}++ for values %$st;

    my @parts;
    push @parts, "$counts{M}M" if $counts{M};
    push @parts, "$counts{A}A" if $counts{A};
    push @parts, "$counts{D}D" if $counts{D};
    push @parts, "$counts{R}R" if $counts{R};
    push @parts, "$counts{'?'}?" if $counts{'?'};

    my $changes = @parts ? join(' ', @parts) : 'clean';
    return "$branch | $changes";
}

# Internal: run a git command and return stdout, or undef on error
sub _run_git {
    my ($dir, @args) = @_;
    # Validate directory exists — list-form open below is already safe
    # from shell injection so we only need to verify the path is real.
    return undef unless defined $dir && -d $dir;

    my @cmd = ('git', '-C', $dir, @args);
    my $output = eval {
        open my $fh, '-|', @cmd or return undef;
        local $/;
        my $out = <$fh>;
        close $fh;
        return ($? == 0) ? $out : undef;
    };
    return $output;
}

1;

__END__

=head1 NAME

HBPerl::Git - Lightweight git status integration

=head1 SYNOPSIS

    use HBPerl::Git;

    if (HBPerl::Git::is_git_repo('/path/to/project')) {
        my $branch = HBPerl::Git::current_branch('/path/to/project');
        my $summary = HBPerl::Git::status_summary('/path/to/project');
        # "main | 3M 1?"
    }

=head1 FUNCTIONS

=over 4

=item B<is_git_repo($dir)>

Returns true if $dir is inside a git working tree.

=item B<current_branch($dir)>

Returns the current branch name, or undef.

=item B<status($dir)>

Returns a hashref of {filepath => status_code} from C<git status --porcelain>.

=item B<status_summary($dir)>

Returns a one-line summary string like C<"main | 3M 1?">.

=back

=head1 AUTHOR

James

=head1 LICENSE

MIT

=cut
