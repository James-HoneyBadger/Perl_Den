package PerlDen::ScriptRegistry;
# ============================================================================
# PerlDen::ScriptRegistry - Dynamic script discovery and plugin loader
# ============================================================================
# Built-in scripts are auto-discovered from lib/PerlDen/Scripts/*.pm — each
# module must export a metadata() function.  Plugins live in
# ~/.config/perlden/plugins/*.pm and must export metadata(), run(), and
# format_report().  User scripts live in ~/.config/perlden/scripts/*.pl
# and use comment-header metadata (# Name:, # Description:, # Category:).
# ============================================================================
use strict;
use warnings;
use File::Basename qw(basename dirname);
use Carp qw(carp);
use Exporter 'import';

our $VERSION = '2.01';
our @EXPORT_OK = qw(
    script_index script_categories find_script find_closest find_top_n
    user_scripts_dir plugins_dir
    invalidate_cache
);

# ── Category display metadata ──────────────────────────────────────────────
my %CATEGORY_META = (
    'System Info'      => { icon => 'computer-symbolic',                emoji => '🖥' },
    'Log Analysis'     => { icon => 'text-x-generic-symbolic',          emoji => '📋' },
    'User Management'  => { icon => 'system-users-symbolic',            emoji => '👤' },
    'Network'          => { icon => 'network-wired-symbolic',           emoji => '🌐' },
    'Security'         => { icon => 'security-high-symbolic',           emoji => '🔒' },
    'Containers'       => { icon => 'application-x-executable-symbolic',emoji => '🐳' },
    'Backup & Config'  => { icon => 'drive-harddisk-symbolic',          emoji => '💾' },
    'Plugins'          => { icon => 'extension-symbolic',               emoji => '🔌' },
    'User Scripts'     => { icon => 'user-home-symbolic',               emoji => '📝' },
);

my @CATEGORY_ORDER = qw(
    System\ Info Log\ Analysis User\ Management Network
    Security Containers Backup\ &\ Config Plugins User\ Scripts
);

# ── Directory helpers ───────────────────────────────────────────────────────

my $_scripts_lib_dir;
sub _scripts_lib_dir {
    # __FILE__ is lib/PerlDen/ScriptRegistry.pm; Scripts/ is a sibling dir
    $_scripts_lib_dir //= dirname(__FILE__) . '/Scripts';
    return $_scripts_lib_dir;
}

my $_hb_config_base;
sub _hb_config_base {
    unless ($_hb_config_base) {
        if ($ENV{PERLDEN_HOME} && -d $ENV{PERLDEN_HOME}) {
            $_hb_config_base = $ENV{PERLDEN_HOME};
        } else {
            eval { require File::HomeDir };
            my $home = $ENV{HOME} || (eval { File::HomeDir->my_home } // '');
            $_hb_config_base = "$home/.config/perlden";
        }
    }
    return $_hb_config_base;
}

sub user_scripts_dir { return _hb_config_base() . '/scripts' }
sub plugins_dir      { return _hb_config_base() . '/plugins' }

# Cache variables for all three discovery layers
my @_builtin_cache;
my $_builtin_loaded   = 0;
my @_plugin_cache;
my $_plugin_dir_mtime = 0;
my @_user_scripts_cache;
my $_user_scripts_mtime = 0;
my $_plugin_cache_key = '';
my $_user_scripts_cache_key = '';

# Force a full re-discovery on next access (e.g. after installing a plugin)
sub invalidate_cache {
    @_builtin_cache     = ();
    $_builtin_loaded    = 0;
    @_plugin_cache      = ();
    $_plugin_dir_mtime  = 0;
    $_plugin_cache_key  = '';
    @_user_scripts_cache = ();
    $_user_scripts_mtime = 0;
    $_user_scripts_cache_key = '';
}

# ── Built-in script discovery ──────────────────────────────────────────────

sub _load_builtin_scripts {
    return @_builtin_cache if $_builtin_loaded;

    my $scripts_dir = _scripts_lib_dir();
    unless (-d $scripts_dir) {
        carp "ScriptRegistry: Scripts directory not found: $scripts_dir" if $ENV{PERLDEN_DEBUG};
        $_builtin_loaded = 1;
        return ();
    }

    opendir(my $dh, $scripts_dir) or do {
        carp "ScriptRegistry: cannot opendir $scripts_dir: $!";
        $_builtin_loaded = 1;
        return ();
    };
    my @pm_files = sort grep { /\.pm$/ } readdir $dh;
    closedir $dh;

    for my $file (@pm_files) {
        my $modname = $file;
        $modname =~ s/\.pm$//;
        my $module = "PerlDen::Scripts::$modname";

        # Security: module name must be a valid Perl identifier path
        unless ($module =~ /\A[A-Za-z_][A-Za-z0-9_]*(?:::[A-Za-z_][A-Za-z0-9_]*)*\z/) {
            warn "ScriptRegistry: skipping suspicious module name: $module\n";
            next;
        }

        (my $module_path = "$module.pm") =~ s{::}{/}g;
        my $loaded = eval { require $module_path; 1 };
        unless ($loaded) {
            carp "ScriptRegistry: failed to load $module: $@" if $ENV{PERLDEN_DEBUG};
            next;
        }

        my $meta_fn = $module->can('metadata');
        unless ($meta_fn) {
            carp "ScriptRegistry: $module has no metadata() — skipping" if $ENV{PERLDEN_DEBUG};
            next;
        }

        my $meta = eval { $meta_fn->() };
        if ($@ || !ref($meta)) {
            carp "ScriptRegistry: metadata() failed for $module: $@" if $ENV{PERLDEN_DEBUG};
            next;
        }

        # Derive a sensible script filename from module name if not in metadata
        my $filename = $meta->{filename};
        unless ($filename) {
            ($filename = lc($modname)) =~ s/([A-Z])/'_' . lc($1)/ge;
            $filename =~ s/^_//;
            $filename .= '.pl';
        }

        push @_builtin_cache, [
            $meta->{name}        // $modname,
            $filename,
            $module,
            $meta->{description} // '',
            $meta->{category}    // 'Uncategorized',
        ];
    }

    $_builtin_loaded = 1;
    return @_builtin_cache;
}

# ── Plugin discovery ────────────────────────────────────────────────────────


sub _disabled_plugins {
    # Avoid circular dependency — only load Config if already in %INC
    my @disabled;

    if (exists $INC{'PerlDen/Config.pm'} && eval { require PerlDen::Config; 1 }) {
        my $disabled = PerlDen::Config::get('disabled_plugins') // [];
        @disabled = ref($disabled) eq 'ARRAY' ? @$disabled : ();
    }

    # Backward compatibility: older layouts stored config under
    # $PERLDEN_HOME/perlden/config.yml instead of $PERLDEN_HOME/config.yml.
    if (!@disabled && $ENV{PERLDEN_HOME}) {
        my $legacy_cfg = $ENV{PERLDEN_HOME} . '/perlden/config.yml';
        if (-f $legacy_cfg) {
            @disabled = _parse_disabled_plugins_legacy_yaml($legacy_cfg);
        }
    }

    return @disabled;
}

sub _parse_disabled_plugins_legacy_yaml {
    my ($path) = @_;
    my @out;
    return @out unless $path && -f $path;

    open my $fh, '<', $path or return @out;
    my $in_list = 0;
    while (my $line = <$fh>) {
        if ($line =~ /^\s*disabled_plugins\s*:\s*$/) {
            $in_list = 1;
            next;
        }
        if ($in_list) {
            if ($line =~ /^\s*-\s*(.+?)\s*$/) {
                push @out, _trim($1);
                next;
            }
            last if $line =~ /^\S/;
        }
    }
    close $fh;
    return @out;
}

sub _load_plugins {
    my $dir = plugins_dir();
    return () unless $dir && -d $dir;

    my $mtime = (stat($dir))[9] // 0;
    opendir(my $dh, $dir) or return ();
    my @pm_files = sort grep { /\.pm$/ } readdir $dh;
    closedir $dh;

    my %disabled = map { $_ => 1 } _disabled_plugins();
    my $disabled_sig = join('|', sort keys %disabled);
    my $file_sig = join('|', map {
        my $path = "$dir/$_";
        my $fm = (stat($path))[9] // 0;
        "$_:$fm";
    } @pm_files);
    my $cache_key = join('||', $dir, $mtime, $disabled_sig, $file_sig);

    return @_plugin_cache
        if $cache_key eq $_plugin_cache_key && @_plugin_cache;

    $_plugin_dir_mtime = $mtime;
    $_plugin_cache_key = $cache_key;
    @_plugin_cache = ();

    for my $file (@pm_files) {
        my $modname = $file;
        $modname =~ s/\.pm$//;
        my $module = "PerlDen::Plugin::$modname";

        # Security: only valid Perl identifier paths
        unless ($module =~ /\A[A-Za-z_][A-Za-z0-9_]*(?:::[A-Za-z_][A-Za-z0-9_]*)*\z/) {
            warn "ScriptRegistry: skipping suspicious plugin name: $module\n";
            next;
        }

        # Load the plugin file by absolute path using an @INC hook.
        # Plugins live as flat files ($dir/GoodPlugin.pm) but are declared
        # as PerlDen::Plugin::GoodPlugin, so the relative require path
        # ("PerlDen/Plugin/GoodPlugin.pm") won't match a flat directory.
        my $plugin_path = "$dir/$file";
        (my $rel = "$module.pm") =~ s{::}{/}g;
        my $loaded = eval {
            unless ($INC{$rel}) {
                local @INC = (sub {
                    my (undef, $req) = @_;
                    return undef unless $req eq $rel;
                    open my $fh, '<', $plugin_path
                        or die "Cannot open $plugin_path: $!\n";
                    $INC{$req} = $plugin_path;
                    return $fh;
                }, @INC);
                require $rel;
            }
            1;
        };
        unless ($loaded) {
            carp "ScriptRegistry: failed to load plugin $module: $@" if $ENV{PERLDEN_DEBUG};
            next;
        }

        # Validate plugin API — both run() and format_report() are required
        my $valid = 1;
        for my $fn (qw(run format_report)) {
            unless ($module->can($fn)) {
                carp "ScriptRegistry: plugin $module missing $fn() — skipping";
                $valid = 0;
                last;
            }
        }
        next unless $valid;

        # Get metadata — try metadata() first, fall back to comment headers
        my $meta = {};
        if (my $mfn = $module->can('metadata')) {
            $meta = eval { $mfn->() } // {};
        }
        unless ($meta->{name}) {
            $meta = _parse_plugin_headers("$dir/$file");
        }

           my $plugin_name = $meta->{name} // $modname;
           next if $disabled{$plugin_name}
               || $disabled{$module}
               || $disabled{$modname};

        push @_plugin_cache, [
            $plugin_name,
            $meta->{filename} // lc($modname) . '.pl',
            $module,
            $meta->{description} // 'Plugin',
            $meta->{category}    // 'Plugins',
        ];
    }

    return @_plugin_cache;
}

sub _parse_plugin_headers {
    my ($path) = @_;
    my %meta;
    return \%meta unless open(my $fh, '<', $path);
    while (my $line = <$fh>) {
        last if $. > 30;
        $meta{name}        = _trim($1) if $line =~ /^#\s*Name:\s*(.+)/i;
        $meta{description} = _trim($1) if $line =~ /^#\s*Description:\s*(.+)/i;
        $meta{category}    = _trim($1) if $line =~ /^#\s*Category:\s*(.+)/i;
        $meta{version}     = _trim($1) if $line =~ /^#\s*Version:\s*(.+)/i;
        $meta{author}      = _trim($1) if $line =~ /^#\s*Author:\s*(.+)/i;
    }
    close $fh;
    return \%meta;
}

sub _trim { my $s = shift // ''; $s =~ s/^\s+|\s+$//g; $s }

# ── User script discovery (unchanged API, enhanced metadata) ────────────────


sub _load_user_scripts {
    my $dir = user_scripts_dir();
    return () unless $dir && -d $dir;

    my $mtime = (stat($dir))[9] // 0;
    opendir(my $dh, $dir) or return ();
    my @files = sort grep { /\.pl$/ } readdir $dh;
    closedir $dh;

    my $file_sig = join('|', map {
        my $path = "$dir/$_";
        my $fm = (stat($path))[9] // 0;
        "$_:$fm";
    } @files);
    my $cache_key = join('||', $dir, $mtime, $file_sig);

    return @_user_scripts_cache
        if $cache_key eq $_user_scripts_cache_key && @_user_scripts_cache;

    $_user_scripts_mtime = $mtime;
    $_user_scripts_cache_key = $cache_key;
    @_user_scripts_cache = ();

    for my $file (@files) {
        my $path = "$dir/$file";
        next unless -f $path;

        my ($name, $desc, $cat);
        if (open my $fh, '<', $path) {
            while (my $line = <$fh>) {
                last if $. > 30;
                $name = _trim($1) if $line =~ /^#\s*Name:\s*(.+)/i;
                $desc = _trim($1) if $line =~ /^#\s*Description:\s*(.+)/i;
                $cat  = _trim($1) if $line =~ /^#\s*Category:\s*(.+)/i;
            }
            close $fh;
        }

        unless ($name) {
            $name = $file;
            $name =~ s/\.pl$//;
            $name =~ s/_/ /g;
            $name =~ s/\b(\w)/uc($1)/ge;
        }
        $desc //= 'User script';
        $cat  //= 'User Scripts';

        push @_user_scripts_cache, [$name, $path, '', $desc, $cat];
    }

    return @_user_scripts_cache;
}

# ── Public API ──────────────────────────────────────────────────────────────

# Return flat list of all scripts (built-in + plugins + user) as arrayrefs
sub script_index {
    return (_load_builtin_scripts(), _load_plugins(), _load_user_scripts());
}

# Return ordered list of categories with their scripts, for GUI tree/menus
sub script_categories {
    my %by_cat;

    for my $s (script_index()) {
        my ($name, $file, $module, $desc, $cat) = @$s;
        push @{$by_cat{$cat}}, [$name, $file, $desc];
    }

    # Build result in canonical order; append any unknown categories at end
    my %seen_order;
    my @result;
    for my $cat_key (@CATEGORY_ORDER) {
        (my $cat = $cat_key) =~ s/\\ / /g;
        next unless $by_cat{$cat};
        $seen_order{$cat} = 1;
        my $meta = $CATEGORY_META{$cat} // {};
        push @result, {
            name  => $cat,
            icon  => $meta->{icon}  // 'folder-symbolic',
            emoji => $meta->{emoji} // '📁',
            items => $by_cat{$cat},
        };
    }
    for my $cat (sort keys %by_cat) {
        next if $seen_order{$cat};
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

# Find a script by name/filename — exact first, then partial
# Returns: ($name, $filename, $module, $desc, $category) or ()
sub find_script {
    my ($query) = @_;
    return () unless defined $query;
    (my $q = lc($query)) =~ s/\.pl$//;

    my @all = script_index();

    # 1. Exact match on filename stem
    for my $s (@all) {
        (my $stem = lc(basename($s->[1]))) =~ s/\.pl$//;
        return @$s if $stem eq $q;
    }

    # 2. Exact match on display name
    for my $s (@all) {
        return @$s if lc($s->[0]) eq $q;
    }

    # 3. Partial match on filename stem or display name
    for my $s (@all) {
        (my $stem = lc(basename($s->[1]))) =~ s/\.pl$//;
        return @$s if $stem =~ /\Q$q\E/ || lc($s->[0]) =~ /\Q$q\E/;
    }

    return ();
}

# Return the closest-matching script name for "did you mean?" suggestions.
# Returns the display name of the best match, or undef if nothing is close.
sub find_closest {
    my ($query) = @_;
    return undef unless defined $query && length $query;
    (my $q = lc($query)) =~ s/\.pl$//;

    my @all = script_index();
    my $best_name  = undef;
    my $best_score = 0;

    for my $s (@all) {
        (my $stem = lc(basename($s->[1]))) =~ s/\.pl$//;
        my $score = _similarity($q, $stem);
        if ($score > $best_score) {
            $best_score = $score;
            $best_name  = $s->[0];
        }
    }

    return $best_score >= 0.4 ? $best_name : undef;
}

# Return up to N closest-matching script display names (for multi-suggestion
# "did you mean?" output). Only returns names with similarity >= 0.4.
sub find_top_n {
    my ($query, $n) = @_;
    $n //= 3;
    return () unless defined $query && length $query;
    (my $q = lc($query)) =~ s/\.pl$//;

    my @scored;
    for my $s (script_index()) {
        (my $stem = lc(basename($s->[1]))) =~ s/\.pl$//;
        my $score = _similarity($q, $stem);
        push @scored, [$score, $s->[0]] if $score >= 0.4;
    }
    @scored = sort { $b->[0] <=> $a->[0] } @scored;
    my $limit = $n < @scored ? $n : scalar @scored;
    return map { $_->[1] } @scored[0 .. $limit - 1];
}
sub _similarity {
    my ($a, $b) = @_;
    return 1 if $a eq $b;
    return 0 if length($a) < 2 || length($b) < 2;

    my %ta = _trigrams($a);
    my %tb = _trigrams($b);

    my $shared = 0;
    $shared += ($ta{$_} < $tb{$_} ? $ta{$_} : $tb{$_}) for grep { exists $tb{$_} } keys %ta;

    my $total = 0;
    $total += $_ for values %ta;
    $total += $_ for values %tb;
    return $total > 0 ? (2 * $shared) / $total : 0;
}

sub _trigrams {
    my ($s) = @_;
    my %t;
    $s = "  $s  ";
    $t{substr($s, $_, 3)}++ for 0 .. length($s) - 3;
    return %t;
}

1;

__END__

=head1 NAME

PerlDen::ScriptRegistry - Dynamic script discovery and plugin loader

=head1 SYNOPSIS

    use PerlDen::ScriptRegistry qw(script_index script_categories find_script find_closest);

    # Flat list of all scripts (built-in + plugins + user)
    for my $s (script_index()) {
        my ($name, $file, $module, $desc, $category) = @$s;
    }

    # Grouped by category (for GUI menus/trees)
    for my $cat (script_categories()) {
        print "$cat->{emoji}  $cat->{name}\n";
        for my $item (@{$cat->{items}}) {
            print "  $item->[0]\n";
        }
    }

    # Look up by name
    my ($name, $file, $module, $desc) = find_script('disk_usage');

    # Fuzzy suggestion for "did you mean?"
    my $suggestion = find_closest('disk_usge');   # returns 'Disk Usage Analyzer'

=head1 DESCRIPTION

Dynamic source of truth for all toolkit scripts.  Built-in scripts are
auto-discovered from C<lib/PerlDen/Scripts/*.pm> (each must export
C<metadata()>).  Plugins come from C<~/.config/perlden/plugins/*.pm>
and must export C<metadata()>, C<run()>, and C<format_report()>.  User
scripts come from C<~/.config/perlden/scripts/*.pl> and use comment
headers (C<# Name:>, C<# Description:>, C<# Category:>).

The C<PERLDEN_HOME> environment variable overrides the C<~/.config/perlden>
base directory.

=head1 BUILT-IN SCRIPT API (metadata())

Every C<PerlDen::Scripts::*> module must export:

    sub metadata {
        return {
            name        => 'My Script',        # display name
            filename    => 'my_script.pl',     # companion script filename
            description => 'What it does',
            category    => 'System Info',      # must match a known category
            icon        => 'computer-symbolic',
            emoji       => '🖥',
            run_timeout => 30,                 # optional; enables alarm() guard
        };
    }

=head1 PLUGIN API

Plugins in C<~/.config/perlden/plugins/*.pm> must export:

    sub metadata    { ... }   # same structure as built-in metadata()
    sub run         { my (%args) = @_; return \%result }
    sub format_report { my ($result) = @_; return $string }

Optionally:

    sub configure   { ... }   # opens a settings UI or prints config help

=head1 EXPORTED FUNCTIONS

=over 4

=item B<script_index()>

Return a flat list of all script entries (built-in + plugins + user) as
arrayrefs: C<[$name, $filename, $module, $desc, $category]>.

=item B<script_categories()>

Return an ordered list of category hashrefs: C<{name, icon, emoji, items}>.

=item B<find_script($query)>

Exact then partial match on filename stem or display name.  Returns
C<($name, $filename, $module, $desc, $category)> or an empty list.

=item B<find_closest($query)>

Trigram similarity match.  Returns the display name of the closest script
(score E<ge> 0.4), or C<undef>.  Used for CLI "did you mean?" suggestions.

=item B<user_scripts_dir()>

Path to the user scripts directory (C<~/.config/perlden/scripts>).

=item B<plugins_dir()>

Path to the plugins directory (C<~/.config/perlden/plugins>).

=item B<invalidate_cache()>

Force re-discovery on next access (e.g. after installing a plugin).

=back

=head1 AUTHOR

James Temple <james@amiga-fan.net>

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2026 Honey Badger Universe

MIT License

=cut
