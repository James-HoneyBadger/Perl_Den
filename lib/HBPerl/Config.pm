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
use YAML::XS qw(LoadFile DumpFile);
use Carp qw(carp);

our $VERSION = '1.00';

our $CONFIG_DIR;
our $CONFIG_FILE;
our $SESSION_FILE;
our $DATA = {};
our $SESSION = {};

sub _ensure_dir {
    $CONFIG_DIR  //= File::HomeDir->my_home . '/.config/hb_perl';
    $CONFIG_FILE //= "$CONFIG_DIR/config.yml";
    $SESSION_FILE //= "$CONFIG_DIR/session.yml";
    make_path($CONFIG_DIR) unless -d $CONFIG_DIR;
}

# ── Preferences ──

sub load {
    _ensure_dir();
    if (-f $CONFIG_FILE) {
        eval { $DATA = LoadFile($CONFIG_FILE) // {} };
        carp "Config load error: $@" if $@;
    }
    # Set defaults
    $DATA->{theme}           //= 'vscode-dark-plus';
    $DATA->{font}            //= 'monospace 11';
    $DATA->{tab_width}       //= 4;
    $DATA->{show_line_numbers} //= 1;
    $DATA->{highlight_line}  //= 1;
    $DATA->{auto_indent}     //= 1;
    $DATA->{word_wrap}       //= 0;
    $DATA->{editor_scheme}   //= 'oblivion';
    $DATA->{terminal_scrollback} //= 10000;
    $DATA->{recent_files}    //= [];

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

    return $DATA;
}

sub save {
    _ensure_dir();
    eval {
        my $tmp = File::Temp->new(DIR => $CONFIG_DIR, SUFFIX => '.tmp', UNLINK => 0);
        DumpFile($tmp->filename, $DATA);
        rename($tmp->filename, $CONFIG_FILE)
            or die "rename failed: $!";
    };
    carp "Config save error: $@" if $@;
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
    return unless $file && -f $file;
    my $list = $DATA->{recent_files} //= [];
    @$list = grep { $_ ne $file } @$list;
    unshift @$list, $file;
    splice @$list, 20 if @$list > 20;
}

# ── Session (open tabs, window geometry) ──

sub load_session {
    _ensure_dir();
    if (-f $SESSION_FILE) {
        eval { $SESSION = LoadFile($SESSION_FILE) // {} };
        carp "Session load error: $@" if $@;
    }
    $SESSION->{window_width}  //= 1400;
    $SESSION->{window_height} //= 900;
    $SESSION->{hpaned_pos}    //= 260;
    $SESSION->{vpaned_pos}    //= 600;
    $SESSION->{open_files}    //= [];
    $SESSION->{active_tab}    //= 0;
    return $SESSION;
}

sub save_session {
    _ensure_dir();
    eval {
        my $tmp = File::Temp->new(DIR => $CONFIG_DIR, SUFFIX => '.tmp', UNLINK => 0);
        DumpFile($tmp->filename, $SESSION);
        rename($tmp->filename, $SESSION_FILE)
            or die "rename failed: $!";
    };
    carp "Session save error: $@" if $@;
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

James

=head1 LICENSE

MIT

=cut
