package HBPerl::Config;
# ============================================================================
# HBPerl::Config - Session and preference persistence
# ============================================================================
use strict;
use warnings;
use utf8;
use File::HomeDir;
use File::Path qw(make_path);
use File::Temp;
use Fcntl qw(:flock);
use YAML::XS qw(LoadFile DumpFile);
use Carp qw(carp);

our $VERSION = '2.00';

# Config schema version — bump when adding/removing/renaming keys
our $CONFIG_SCHEMA_VERSION = 4;

our $CONFIG_DIR;
our $CONFIG_FILE;
our $SESSION_FILE;
our $DATA = {};
our $SESSION = {};

sub _ensure_dir {
    # HBPERL_HOME overrides the default ~/.config/hb_perl base
    my $base;
    if ($ENV{HBPERL_HOME} && -d $ENV{HBPERL_HOME}) {
        $base = $ENV{HBPERL_HOME};
    } else {
        $base = File::HomeDir->my_home . '/.config/hb_perl';
    }
    $CONFIG_DIR   //= $base;
    $CONFIG_FILE  //= "$CONFIG_DIR/config.yml";
    $SESSION_FILE //= "$CONFIG_DIR/session.yml";
    make_path($CONFIG_DIR, { mode => 0700 }) unless -d $CONFIG_DIR;
}

# ── Preferences ──

# Allowed config keys with types for validation
my %CONFIG_SCHEMA = (
    _config_version          => 'int',
    theme                    => 'string',
    font                     => 'string',
    tab_width                => 'int',
    show_line_numbers        => 'bool',
    highlight_line           => 'bool',
    auto_indent              => 'bool',
    word_wrap                => 'bool',
    editor_scheme            => 'string',
    terminal_scrollback      => 'int',
    recent_files             => 'array',
    dashboard_interval       => 'int',
    dashboard_refresh_seconds => 'int',
    privilege_tool           => 'string',
    font_scale               => 'int',
    notifications            => 'string',
    disabled_plugins         => 'array',
);

sub load {
    _ensure_dir();
    if (-f $CONFIG_FILE) {
        eval { $DATA = _load_yaml_locked($CONFIG_FILE) // {} };
        carp "Config load error: $@" if $@;
    }

    # Migrate from older schema versions
    _migrate_config();

    # Set defaults
    _apply_defaults();

    # Validate types — coerce bad values to defaults
    _validate_config();

    # Backward compatibility for previous theme names
    my %theme_alias = (
        dark          => 'vscode-dark-plus',
        light         => 'vscode-light-plus',
        'vscode-dark' => 'vscode-dark-plus',
        'vscode-light'=> 'vscode-light-plus',
    );
    if (defined $DATA->{theme} && exists $theme_alias{$DATA->{theme}}) {
        $DATA->{theme} = $theme_alias{$DATA->{theme}};
    }

    # Clean stale entries from recent files
    if (ref $DATA->{recent_files} eq 'ARRAY') {
        @{$DATA->{recent_files}} = grep { defined $_ && -f $_ } @{$DATA->{recent_files}};
    }

    # Stamp current schema version
    $DATA->{_config_version} = $CONFIG_SCHEMA_VERSION;

    return $DATA;
}

sub save {
    _ensure_dir();
    $DATA->{_config_version} = $CONFIG_SCHEMA_VERSION;
    _save_yaml_locked($CONFIG_FILE, $DATA);
}

sub get {
    my ($key) = @_;
    return $DATA->{$key};
}

sub set {
    my ($key, $value) = @_;
    $DATA->{$key} = $value;
}

sub add_recent_file {
    my ($file) = @_;
    return unless defined $file && length($file) && -f $file;
    my $list = $DATA->{recent_files} //= [];
    @$list = grep { defined $_ && $_ ne $file } @$list;
    unshift @$list, $file;
    splice @$list, 20 if @$list > 20;
}

sub recent_files {
    my $list = $DATA->{recent_files} // [];
    return [ grep { defined $_ && -f $_ } @$list ];
}

# ── Session (open tabs, window geometry) ──

sub load_session {
    _ensure_dir();
    if (-f $SESSION_FILE) {
        eval { $SESSION = _load_yaml_locked($SESSION_FILE) // {} };
        carp "Session load error: $@" if $@;
    }
    $SESSION->{window_width}  //= 1400;
    $SESSION->{window_height} //= 900;
    $SESSION->{hpaned_pos}    //= 260;
    $SESSION->{vpaned_pos}    //= 600;
    $SESSION->{open_files}    //= [];
    $SESSION->{active_tab}    //= 0;

    # Clean stale files from session
    if (ref $SESSION->{open_files} eq 'ARRAY') {
        @{$SESSION->{open_files}} = grep { defined $_ && -f $_ } @{$SESSION->{open_files}};
    }

    return $SESSION;
}

sub save_session {
    _ensure_dir();
    $SESSION->{_saved_at} = time();
    _save_yaml_locked($SESSION_FILE, $SESSION);
}

# Check if last session was saved cleanly (for crash recovery)
sub session_was_clean {
    return 1 unless -f $SESSION_FILE;
    my $data = eval { _load_yaml_locked($SESSION_FILE) } // {};
    return defined $data->{_saved_at};
}

sub session_get {
    my ($key) = @_;
    return $SESSION->{$key};
}

sub session_set {
    my ($key, $value) = @_;
    $SESSION->{$key} = $value;
}

sub config_dir { _ensure_dir(); return $CONFIG_DIR }

# Detect available privilege escalation tool
sub privilege_tool {
    my $pref = $DATA->{privilege_tool} // 'auto';
    return $pref unless $pref eq 'auto';
    for my $tool (qw(pkexec sudo doas)) {
        require HBPerl::Util;
        my ($path) = HBPerl::Util::run_command_list('which', $tool);
        chomp($path) if defined $path;
        return $tool if $path && -x $path;
    }
    return 'sudo';  # fallback
}

# ── Internal: locked YAML I/O ──

sub _load_yaml_locked {
    my ($file) = @_;
    open my $fh, '<', $file or die "Cannot open $file: $!";
    flock($fh, LOCK_SH) or carp "Cannot lock $file: $!";
    # Read within the lock scope to avoid double-open
    local $/;
    my $raw = <$fh>;
    close $fh;
    my $data = eval { YAML::XS::Load($raw) };
    die $@ if $@;
    # Validate structure is a plain hashref (defense against YAML object instantiation)
    die "Config file $file: expected hash, got " . ref($data)
        unless ref($data) eq 'HASH';
    return $data;
}

sub _save_yaml_locked {
    my ($file, $data) = @_;
    _ensure_dir();
    eval {
        my $tmp = File::Temp->new(DIR => $CONFIG_DIR, SUFFIX => '.tmp', UNLINK => 0);
        DumpFile($tmp->filename, $data);
        # Acquire exclusive lock on target before rename
        if (open my $lock_fh, '>>', $file) {
            flock($lock_fh, LOCK_EX) or carp "Cannot lock $file: $!";
            rename($tmp->filename, $file)
                or die "rename failed: $!";
            close $lock_fh;
        } else {
            rename($tmp->filename, $file)
                or die "rename failed: $!";
        }
    };
    carp "Save error for $file: $@" if $@;
}

# ── Internal: schema migration ──

sub _migrate_config {
    my $ver = $DATA->{_config_version} // 1;

    # v1 → v2: add dashboard_interval, privilege_tool
    if ($ver < 2) {
        $DATA->{dashboard_interval} //= 5;
        $DATA->{privilege_tool}     //= 'auto';
    }

    # v2 → v3: add font_scale
    if ($ver < 3) {
        $DATA->{font_scale} //= 100;
    }

    # v3 → v4: add notifications, disabled_plugins, dashboard_refresh_seconds
    if ($ver < 4) {
        $DATA->{notifications}             //= 'errors';
        $DATA->{disabled_plugins}          //= [];
        $DATA->{dashboard_refresh_seconds} //= 5;
    }

    $DATA->{_config_version} = $CONFIG_SCHEMA_VERSION;
}

# ── Internal: apply default values for missing keys ──

sub _apply_defaults {
    $DATA->{theme}                    //= 'vscode-dark-plus';
    $DATA->{font}                     //= 'monospace 11';
    $DATA->{tab_width}                //= 4;
    $DATA->{show_line_numbers}        //= 1;
    $DATA->{highlight_line}           //= 1;
    $DATA->{auto_indent}              //= 1;
    $DATA->{word_wrap}                //= 0;
    $DATA->{editor_scheme}            //= 'oblivion';
    $DATA->{terminal_scrollback}      //= 10000;
    $DATA->{recent_files}             //= [];
    $DATA->{dashboard_interval}       //= 5;
    $DATA->{dashboard_refresh_seconds} //= 5;
    $DATA->{privilege_tool}           //= 'auto';
    $DATA->{font_scale}               //= 100;
    $DATA->{notifications}            //= 'errors';
    $DATA->{disabled_plugins}         //= [];
}

# ── Internal: config validation ──

sub _validate_config {
    while (my ($key, $type) = each %CONFIG_SCHEMA) {
        next unless exists $DATA->{$key};
        my $val = $DATA->{$key};
        if ($type eq 'int') {
            unless (defined $val && $val =~ /^\d+$/) {
                delete $DATA->{$key};
            }
        } elsif ($type eq 'bool') {
            $DATA->{$key} = $val ? 1 : 0;
        } elsif ($type eq 'string') {
            unless (defined $val && !ref($val)) {
                delete $DATA->{$key};
            }
        } elsif ($type eq 'array') {
            $DATA->{$key} = [] unless ref $val eq 'ARRAY';
        }
    }

    # Remove unknown keys (but preserve underscore-prefixed internal keys)
    for my $key (keys %$DATA) {
        next if $key =~ /^_/;
        unless (exists $CONFIG_SCHEMA{$key}) {
            carp "Config: ignoring unknown key '$key'";
            delete $DATA->{$key};
        }
    }

    # Re-apply defaults for any values removed during validation
    _apply_defaults();
}

# ── Theme-aware colour palettes ──
# Returns a hash ref of named colours for the current theme so that
# Perl-side markup / TextBuffer tags always match the CSS.

my %PALETTES = (
    'vscode-dark-plus' => {
        accent      => '#3794ff',
        fg          => '#d4d4d4',
        subtext     => '#9da5b4',
        dim         => '#6a737d',
        bg          => '#1e1e1e',
        surface     => '#252526',
        panel_bg    => '#1e1e1e',
        error       => '#f14c4c',
        success     => '#89d185',
        warning     => '#cca700',
        info        => '#3794ff',
        # VTE terminal
        vte_bg_r => 0.118, vte_bg_g => 0.118, vte_bg_b => 0.118,
        vte_fg_r => 0.831, vte_fg_g => 0.831, vte_fg_b => 0.831,
    },
    'vscode-light-plus' => {
        accent      => '#0078d4',
        fg          => '#1e1e1e',
        subtext     => '#616161',
        dim         => '#8a8a8a',
        bg          => '#ffffff',
        surface     => '#f3f3f3',
        panel_bg    => '#f3f3f3',
        error       => '#e51400',
        success     => '#388a34',
        warning     => '#b89500',
        info        => '#0078d4',
        # VTE terminal
        vte_bg_r => 0.953, vte_bg_g => 0.953, vte_bg_b => 0.953,
        vte_fg_r => 0.118, vte_fg_g => 0.118, vte_fg_b => 0.118,
    },
    'high-contrast' => {
        accent      => '#ffff00',
        fg          => '#ffffff',
        subtext     => '#cccccc',
        dim         => '#999999',
        bg          => '#000000',
        surface     => '#0a0a0a',
        panel_bg    => '#000000',
        error       => '#ff3333',
        success     => '#00ff00',
        warning     => '#ffaa00',
        info        => '#6fc3df',
        # VTE terminal
        vte_bg_r => 0.0, vte_bg_g => 0.0, vte_bg_b => 0.0,
        vte_fg_r => 1.0, vte_fg_g => 1.0, vte_fg_b => 1.0,
    },
);

# Legacy aliases
$PALETTES{dark}           = $PALETTES{'vscode-dark-plus'};
$PALETTES{light}          = $PALETTES{'vscode-light-plus'};
$PALETTES{'vscode-dark'}  = $PALETTES{'vscode-dark-plus'};
$PALETTES{'vscode-light'} = $PALETTES{'vscode-light-plus'};

sub theme_colors {
    my $theme = $DATA->{theme} // 'vscode-dark-plus';
    return $PALETTES{$theme} // $PALETTES{dark};
}

1;

__END__

=encoding utf8

=head1 NAME

HBPerl::Config - Configuration and session management for HB Perl IDE

=head1 SYNOPSIS

    use HBPerl::Config;

    HBPerl::Config::load();
    my $theme = HBPerl::Config::get('theme');
    HBPerl::Config::set('font', 'monospace 12');
    HBPerl::Config::save();

=head1 DESCRIPTION

Manages two YAML files under F<~/.config/hb_perl/>:

=over 4

=item F<config.yml> — user preferences (theme, font, tab width, etc.)

=item F<session.yml> — session state (window size, pane positions, open files)

=back

Writes are atomic (temp file + rename) to prevent corruption on crash.

=head1 CONFIG KEYS

    theme              vscode-dark-plus | vscode-light-plus
    font               Pango font description (e.g. 'monospace 11')
    tab_width          integer (default 4)
    show_line_numbers  boolean (default 1)
    highlight_line     boolean (default 1)
    auto_indent        boolean (default 1)
    word_wrap          boolean (default 0)
    editor_scheme      GtkSourceView scheme id (default 'oblivion')
    terminal_scrollback integer (default 10000)
    recent_files       arrayref of file paths (max 20)

=head1 FUNCTIONS

=over 4

=item B<load()>

Load F<config.yml> from disk and apply defaults for missing keys.
Returns the config hashref.

=item B<save()>

Atomically write the current config to F<config.yml>.

=item B<get($key)>

Return the value for a config key.

=item B<set($key, $value)>

Set a config key.

=item B<add_recent_file($path)>

Prepend a file path to the recent-files list (max 20, deduped).

=item B<load_session()>

Load F<session.yml>; returns the session hashref.

=item B<save_session()>

Atomically write session state to F<session.yml>.

=item B<session_get($key)>, B<session_set($key, $value)>

Read/write session keys (window_width, window_height, hpaned_pos,
vpaned_pos, open_files, active_tab).

=item B<config_dir()>

Return the path to F<~/.config/hb_perl/>.

=item B<theme_colors()>

Return a hashref of named colours for the current theme (accent, fg, bg,
error, success, etc.) used by GUI components for Pango markup.

=back

=head1 AUTHOR

James Temple <james@amiga-fan.net>

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2026 Honey Badger Universe

MIT License

=cut
