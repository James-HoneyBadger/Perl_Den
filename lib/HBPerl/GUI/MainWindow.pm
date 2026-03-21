package HBPerl::GUI::MainWindow;
# ============================================================================
# HBPerl::GUI::MainWindow - Main application window layout
# ============================================================================
use strict;
use warnings;
use utf8;
use Glib ('TRUE', 'FALSE');
use Gtk3;
use File::Basename qw(dirname);

use HBPerl::Config;
use HBPerl::Git;
use HBPerl::Util qw(shell_quote);
use HBPerl::GUI::Toolbar;
use HBPerl::GUI::Editor;
use HBPerl::GUI::Terminal;
use HBPerl::GUI::ScriptBrowser;
use HBPerl::GUI::Dashboard;
use HBPerl::GUI::Dialogs;

sub new {
    my ($class, %args) = @_;
    my $self = bless {
        app       => $args{app},
        share_dir => $args{share_dir},
        has_vte   => $args{has_vte},
    }, $class;

    $self->_build_ui;
    return $self;
}

sub _build_ui {
    my ($self) = @_;
    my $session = HBPerl::Config::load_session();

    # ── Main Window ──
    my $window = Gtk3::Window->new('toplevel');
    $window->set_title('HB Perl IDE');
    $window->set_default_size(
        $session->{window_width}  // 1400,
        $session->{window_height} // 900,
    );
    $window->set_position('center');
    $window->signal_connect(delete_event => sub {
        $self->{app}->quit;
        return FALSE;
    });
    $self->{window} = $window;

    # Try to set window icon
    eval {
        my $icon_file = "$self->{share_dir}/icons/hb_perl.png";
        if (-f $icon_file) {
            $window->set_icon_from_file($icon_file);
        }
    };

    # ── Master vertical box ──
    my $vbox = Gtk3::Box->new('vertical', 0);
    $window->add($vbox);

    # ── Menu Bar ──
    my $toolbar = HBPerl::GUI::Toolbar->new(main_window => $self);
    $vbox->pack_start($toolbar->menubar, FALSE, FALSE, 0);
    $self->{toolbar} = $toolbar;

    # ── Quick Toolbar ──
    $vbox->pack_start($toolbar->quick_toolbar, FALSE, FALSE, 0);

    # ── Main Content: HPaned (sidebar | editor+dashboard) ──
    my $hpaned = Gtk3::Paned->new('horizontal');
    $hpaned->set_position($session->{hpaned_pos} // 260);
    $self->{hpaned} = $hpaned;

    # ── Left: Script Browser ──
    my $browser = HBPerl::GUI::ScriptBrowser->new(
        main_window => $self,
        share_dir   => $self->{share_dir},
    );
    $self->{browser} = $browser;
    $hpaned->pack1($browser->widget, FALSE, FALSE);

    # ── Right: VPaned (editor tabs on top, terminal on bottom) ──
    my $vpaned = Gtk3::Paned->new('vertical');
    $vpaned->set_position($session->{vpaned_pos} // 550);
    $self->{vpaned} = $vpaned;

    # ── Editor Notebook (with Dashboard tab) ──
    my $right_notebook = Gtk3::Notebook->new;
    $right_notebook->set_scrollable(TRUE);
    $self->{right_notebook} = $right_notebook;

    # Dashboard tab
    my $dashboard = HBPerl::GUI::Dashboard->new(main_window => $self);
    $self->{dashboard} = $dashboard;
    my $dash_label = Gtk3::Label->new('⊞ Dashboard');
    $right_notebook->append_page($dashboard->widget, $dash_label);

    # Editor component (manages tabs within the same notebook)
    my $editor = HBPerl::GUI::Editor->new(
        main_window => $self,
        notebook    => $right_notebook,
    );
    $self->{editor} = $editor;

    $vpaned->pack1($right_notebook, TRUE, TRUE);

    # ── Bottom: Terminal + Output Panel ──
    my $terminal = HBPerl::GUI::Terminal->new(
        main_window => $self,
        has_vte     => $self->{has_vte},
    );
    $self->{terminal} = $terminal;
    $vpaned->pack2($terminal->widget, FALSE, TRUE);

    $hpaned->pack2($vpaned, TRUE, TRUE);

    $vbox->pack_start($hpaned, TRUE, TRUE, 0);

    # ── Status Bar ──
    my $statusbar = $self->_build_statusbar;
    $vbox->pack_start($statusbar, FALSE, FALSE, 0);

    # ── Keyboard Shortcuts ──
    $window->signal_connect('key-press-event' => sub {
        my ($w, $event) = @_;
        return $self->_handle_keypress($event);
    });

    # ── Restore open files from session ──
    my $open_files = $session->{open_files} // [];
    for my $file (@$open_files) {
        $editor->open_file($file) if -f $file;
    }

    # ── Open files passed via command-line arguments ──
    if ($self->{app}{open_files}) {
        for my $file (@{$self->{app}{open_files}}) {
            $editor->open_file($file) if -f $file;
        }
    }

    if (defined $session->{active_tab} && $session->{active_tab} >= 0) {
        my $page = $session->{active_tab} + 1;  # +1 for dashboard tab
        $right_notebook->set_current_page($page)
            if $page < $right_notebook->get_n_pages;
    }
}

sub _build_statusbar {
    my ($self) = @_;
    my $bar = Gtk3::Box->new('horizontal', 12);
    my $sc = $bar->get_style_context;
    $sc->add_class('statusbar');
    $bar->set_margin_start(8);
    $bar->set_margin_end(8);

    $self->{status_left}  = Gtk3::Label->new('Ready');
    $self->{status_left}->set_halign('start');
    $bar->pack_start($self->{status_left}, TRUE, TRUE, 0);

    $self->{status_pos} = Gtk3::Label->new('Ln 1, Col 1');
    $bar->pack_start($self->{status_pos}, FALSE, FALSE, 0);

    $self->{status_encoding} = Gtk3::Label->new('UTF-8');
    $bar->pack_start($self->{status_encoding}, FALSE, FALSE, 0);

    $self->{status_eol} = Gtk3::Label->new('LF');
    $bar->pack_start($self->{status_eol}, FALSE, FALSE, 0);

    $self->{status_lang} = Gtk3::Label->new('Perl');
    $bar->pack_start($self->{status_lang}, FALSE, FALSE, 0);

    my $perl_ver = sprintf("Perl %vd", $^V);
    my $pl = Gtk3::Label->new($perl_ver);
    $bar->pack_start($pl, FALSE, FALSE, 0);

    # Git branch indicator
    $self->{status_git} = Gtk3::Label->new('');
    $bar->pack_start($self->{status_git}, FALSE, FALSE, 0);
    $self->_update_git_status;

    return $bar;
}

sub _handle_keypress {
    my ($self, $event) = @_;
    my $key  = $event->keyval;
    my $ctrl = $event->state >= 'control-mask';
    my $shift = $event->state >= 'shift-mask';

    if ($ctrl) {
        if ($key == Gtk3::Gdk::KEY_n()) {
            $self->{editor}->new_file;
            return TRUE;
        }
        elsif ($key == Gtk3::Gdk::KEY_o()) {
            $self->{editor}->open_file_dialog;
            return TRUE;
        }
        elsif ($key == Gtk3::Gdk::KEY_s()) {
            if ($shift) {
                $self->{editor}->save_file_as;
            } else {
                $self->{editor}->save_current_file;
            }
            return TRUE;
        }
        elsif ($key == Gtk3::Gdk::KEY_w()) {
            $self->{editor}->close_current_tab;
            return TRUE;
        }
        elsif ($key == Gtk3::Gdk::KEY_f()) {
            $self->{editor}->show_find_bar;
            return TRUE;
        }
        elsif ($key == Gtk3::Gdk::KEY_g()) {
            $self->{editor}->goto_line_dialog;
            return TRUE;
        }
        elsif ($key == Gtk3::Gdk::KEY_h() && $shift) {
            $self->{editor}->show_find_replace_bar;
            return TRUE;
        }
        elsif ($key == Gtk3::Gdk::KEY_F5()) {
            $self->run_current_script;
            return TRUE;
        }
        elsif ($key == Gtk3::Gdk::KEY_q()) {
            $self->{app}->quit;
            return TRUE;
        }
        elsif ($key == Gtk3::Gdk::KEY_grave()) {
            # Ctrl+` toggle terminal
            $self->{terminal}->toggle_visibility;
            return TRUE;
        }
    }
    elsif ($key == Gtk3::Gdk::KEY_F5()) {
        $self->run_current_script;
        return TRUE;
    }

    return FALSE;
}

sub show {
    my ($self) = @_;
    $self->{window}->show_all;
}

sub save_state {
    my ($self) = @_;
    my ($w, $h) = $self->{window}->get_size;
    HBPerl::Config::session_set('window_width',  $w);
    HBPerl::Config::session_set('window_height', $h);
    HBPerl::Config::session_set('hpaned_pos', $self->{hpaned}->get_position);
    HBPerl::Config::session_set('vpaned_pos', $self->{vpaned}->get_position);

    # Save open files
    my @files = $self->{editor}->get_open_files;
    HBPerl::Config::session_set('open_files', \@files);

    my $current = $self->{right_notebook}->get_current_page;
    HBPerl::Config::session_set('active_tab', $current > 0 ? $current - 1 : 0);
}

sub set_status {
    my ($self, $text) = @_;
    $self->{status_left}->set_text($text // 'Ready');
}

sub set_cursor_position {
    my ($self, $line, $col) = @_;
    $self->{status_pos}->set_text("Ln $line, Col $col");
}

sub set_language_mode {
    my ($self, $lang) = @_;
    $self->{status_lang}->set_text($lang // 'Plain Text');
}

sub set_line_ending {
    my ($self, $eol) = @_;
    $self->{status_eol}->set_text($eol // 'LF');
}

sub run_current_script {
    my ($self) = @_;
    my $file = $self->{editor}->get_current_file;
    if ($file && -f $file) {
        $self->{editor}->save_current_file;
        $self->{terminal}->run_command("perl " . shell_quote($file));
        # Auto-focus the output/terminal panel
        $self->{terminal}->show_output_tab;
        $self->set_status("Running: $file");
        $self->_update_git_status;
    } else {
        $self->set_status("No file to run");
    }
}

sub open_file_in_editor {
    my ($self, $file) = @_;
    $self->{editor}->open_file($file);
    $self->_update_git_status;
}

sub append_output {
    my ($self, $text, $tag) = @_;
    $self->{terminal}->append_output($text, $tag);
}

sub apply_settings {
    my ($self) = @_;

    # 1. Re-apply the CSS theme (handles dark <-> light swap)
    $self->{app}->apply_theme;

    # 2. Re-apply editor settings to every open tab
    $self->{editor}->apply_settings;

    # 3. Re-apply terminal / output font and colours
    $self->{terminal}->apply_settings;

    # 4. Re-apply dashboard colours
    $self->{dashboard}->apply_settings if $self->{dashboard};

    $self->set_status('Preferences applied');
}

sub window { return $_[0]->{window} }
sub editor { return $_[0]->{editor} }
sub terminal { return $_[0]->{terminal} }
sub app { return $_[0]->{app} }

sub _update_git_status {
    my ($self) = @_;
    my $file = $self->{editor} ? $self->{editor}->get_current_file : undef;
    my $dir = defined $file ? dirname($file) : '.';

    my $summary = eval { HBPerl::Git::status_summary($dir) };
    if (defined $summary) {
        $self->{status_git}->set_text("\x{e0a0} $summary");  # branch icon
        $self->{status_git}->show;
    } else {
        $self->{status_git}->set_text('');
        $self->{status_git}->hide;
    }
}

1;

__END__

=head1 NAME

HBPerl::GUI::MainWindow - Main application window and layout manager

=head1 DESCRIPTION

Assembles the top-level GTK window: menu bar, quick toolbar, sidebar
(script browser), tabbed editor, terminal/output panel, and status bar.
Handles keyboard shortcuts, session save/restore, and coordinates between
child components.

=head1 METHODS

=over 4

=item B<new(app =E<gt> $app, share_dir =E<gt> $path, has_vte =E<gt> $bool)>

Build the window layout and restore session geometry.

=item B<show()>

Display the window and re-open files from the previous session.

=item B<save_state()>

Persist window size, pane positions, and open files to the session.

=item B<set_status($message)>

Update the status bar text.

=item B<set_cursor_position($line, $col)>

Update the cursor position indicator in the status bar.

=item B<run_current_script()>

Save and execute the active editor tab via the terminal.

=item B<open_file_in_editor($path)>

Open a file in the editor (used by ScriptBrowser and Toolbar).

=item B<append_output($text, $tag)>

Append text to the script output panel with an optional style tag.

=item B<apply_settings()>

Propagate theme/font changes to all child components.

=item B<window()>, B<editor()>, B<terminal()>, B<app()>

Accessors for child components.

=back

=head1 KEYBOARD SHORTCUTS

    Ctrl+N          New file
    Ctrl+O          Open file
    Ctrl+S          Save
    Ctrl+Shift+S    Save as
    Ctrl+W          Close tab
    Ctrl+Q          Quit
    Ctrl+Z          Undo
    Ctrl+Shift+Z    Redo
    Ctrl+F          Find
    Ctrl+Shift+H    Find & Replace
    F5              Run script
    F9              Syntax check

=head1 AUTHOR

James

=head1 LICENSE

MIT

=cut
