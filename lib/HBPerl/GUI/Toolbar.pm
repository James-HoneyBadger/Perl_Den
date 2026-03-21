package HBPerl::GUI::Toolbar;
# ============================================================================
# HBPerl::GUI::Toolbar - Menu bar and quick-access toolbar
# ============================================================================
use strict;
use warnings;
use utf8;
use Glib ('TRUE', 'FALSE');
use Gtk3;
use HBPerl::ScriptRegistry qw(script_index);
use HBPerl::Util qw(shell_quote);

sub new {
    my ($class, %args) = @_;
    my $self = bless {
        main_window => $args{main_window},
    }, $class;
    $self->_build_menubar;
    $self->_build_quick_toolbar;
    return $self;
}

sub _build_menubar {
    my ($self) = @_;
    my $mw = $self->{main_window};

    my $menubar = Gtk3::MenuBar->new;

    # ── File Menu ──
    my $file_menu = Gtk3::Menu->new;
    $self->_add_menu_item($file_menu, 'New File',        'Ctrl+N',  sub { $mw->editor->new_file });
    $self->_add_menu_item($file_menu, 'Open File...',    'Ctrl+O',  sub { $mw->editor->open_file_dialog });
    $self->_add_separator($file_menu);
    $self->_add_menu_item($file_menu, 'Save',            'Ctrl+S',  sub { $mw->editor->save_current_file });
    $self->_add_menu_item($file_menu, 'Save As...',      'Ctrl+Shift+S', sub { $mw->editor->save_file_as });
    $self->_add_separator($file_menu);
    $self->_add_menu_item($file_menu, 'Close Tab',       'Ctrl+W',  sub { $mw->editor->close_current_tab });
    $self->_add_separator($file_menu);

    # Recent Files submenu
    my $recent_menu = Gtk3::Menu->new;
    my $recent_item = Gtk3::MenuItem->new_with_label('Recent Files');
    $recent_item->set_submenu($recent_menu);
    $self->{recent_menu} = $recent_menu;
    $self->_populate_recent_menu;
    $file_menu->append($recent_item);

    $self->_add_separator($file_menu);
    $self->_add_menu_item($file_menu, 'Quit',            'Ctrl+Q',  sub { $mw->app->quit });
    $menubar->append($self->_make_menu_heading('File', $file_menu));

    # ── Edit Menu ──
    my $edit_menu = Gtk3::Menu->new;
    $self->_add_menu_item($edit_menu, 'Undo',            'Ctrl+Z',     sub { $mw->editor->undo });
    $self->_add_menu_item($edit_menu, 'Redo',            'Ctrl+Shift+Z', sub { $mw->editor->redo });
    $self->_add_separator($edit_menu);
    $self->_add_menu_item($edit_menu, 'Find...',         'Ctrl+F',     sub { $mw->editor->show_find_bar });
    $self->_add_menu_item($edit_menu, 'Find & Replace...', 'Ctrl+Shift+H', sub { $mw->editor->show_find_replace_bar });
    $self->_add_menu_item($edit_menu, 'Go to Line...',     'Ctrl+G',  sub { $mw->editor->goto_line_dialog });
    $self->_add_separator($edit_menu);
    $self->_add_menu_item($edit_menu, 'Preferences...',  '',           sub { HBPerl::GUI::Dialogs::show_preferences($mw) });
    $menubar->append($self->_make_menu_heading('Edit', $edit_menu));

    # ── Tools Menu ──
    my $tools_menu = Gtk3::Menu->new;
    $self->_add_menu_item($tools_menu, 'Syntax Check',         'F9',    sub { $mw->editor->syntax_check });
    $self->_add_menu_item($tools_menu, 'Format Code (Tidy)',   'Ctrl+Shift+F', sub { $mw->editor->format_code });
    $self->_add_menu_item($tools_menu, 'Lint (Perl::Critic)',  '',      sub { $mw->editor->lint_code });
    $self->_add_separator($tools_menu);
    $self->_add_menu_item($tools_menu, 'POD Preview',          '',      sub { $mw->editor->pod_preview });
    $self->_add_separator($tools_menu);
    $self->_add_menu_item($tools_menu, 'New Script from Template...', '', sub { HBPerl::GUI::Dialogs::show_new_from_template($mw) });
    $menubar->append($self->_make_menu_heading('Tools', $tools_menu));

    # ── Run Menu ──
    my $run_menu = Gtk3::Menu->new;
    $self->_add_menu_item($run_menu, 'Run Script',      'F5',  sub { $mw->run_current_script });
    $self->_add_menu_item($run_menu, 'Run as Root',     '',    sub {
        my $file = $mw->editor->get_current_file;
        if ($file && -f $file) {
            $mw->editor->save_current_file;
            my $priv_tool = HBPerl::Config::privilege_tool();
            $mw->terminal->run_command("$priv_tool perl " . shell_quote($file));
        }
    });
    $self->_add_separator($run_menu);
    $self->_add_menu_item($run_menu, 'Stop Script',     '',    sub { $mw->terminal->stop_running });
    $menubar->append($self->_make_menu_heading('Run', $run_menu));

    # ── Scripts Menu (populated from registry) ──
    my $scripts_menu = Gtk3::Menu->new;
    for my $entry (script_index()) {
        my ($label, $script, $module, $desc, $category) = @$entry;
        $self->_add_menu_item($scripts_menu, $label, '', sub {
            my $script_path = $mw->app->share_dir . "/../scripts/$script";
            if (-f $script_path) {
                $mw->open_file_in_editor($script_path);
            } else {
                $mw->set_status("Script not found: $script");
            }
        });
    }
    $menubar->append($self->_make_menu_heading('Scripts', $scripts_menu));

    # ── Tutorials Menu ──
    my $tut_menu = Gtk3::Menu->new;
    $self->_add_menu_item($tut_menu, 'Browse Tutorials...', '', sub {
        HBPerl::GUI::Dialogs::show_tutorial_browser($mw);
    });
    $menubar->append($self->_make_menu_heading('Tutorials', $tut_menu));

    # ── Help Menu ──
    my $help_menu = Gtk3::Menu->new;
    $self->_add_menu_item($help_menu, 'About HB Perl IDE', '', sub { HBPerl::GUI::Dialogs::show_about($mw) });
    $self->_add_menu_item($help_menu, 'Keyboard Shortcuts', '', sub { HBPerl::GUI::Dialogs::show_shortcuts($mw) });
    $menubar->append($self->_make_menu_heading('Help', $help_menu));

    $self->{menubar} = $menubar;
}

sub _build_quick_toolbar {
    my ($self) = @_;
    my $mw = $self->{main_window};

    my $tb = Gtk3::Toolbar->new;
    $tb->set_style('icons');
    $tb->set_icon_size('small-toolbar');

    my @items = (
        ['document-new-symbolic',     'New File (Ctrl+N)',      sub { $mw->editor->new_file }],
        ['document-open-symbolic',    'Open File (Ctrl+O)',     sub { $mw->editor->open_file_dialog }],
        ['document-save-symbolic',    'Save (Ctrl+S)',          sub { $mw->editor->save_current_file }],
        [undef],  # separator
        ['edit-undo-symbolic',        'Undo (Ctrl+Z)',          sub { $mw->editor->undo }],
        ['edit-redo-symbolic',        'Redo (Ctrl+Shift+Z)',    sub { $mw->editor->redo }],
        [undef],  # separator
        ['edit-find-symbolic',        'Find (Ctrl+F)',          sub { $mw->editor->show_find_bar }],
        [undef],  # separator
        ['media-playback-start-symbolic', 'Run Script (F5)',    sub { $mw->run_current_script }],
        ['media-playback-stop-symbolic',  'Stop Script',        sub { $mw->terminal->stop_running }],
        [undef],  # separator
        ['applications-system-symbolic',  'Syntax Check (F9)',  sub { $mw->editor->syntax_check }],
        ['format-text-bold-symbolic',     'Format Code',        sub { $mw->editor->format_code }],
    );

    for my $item (@items) {
        if (!defined $item->[0]) {
            $tb->insert(Gtk3::SeparatorToolItem->new, -1);
            next;
        }
        my ($icon, $tooltip, $cb) = @$item;
        my $btn = Gtk3::ToolButton->new(undef, '');
        $btn->set_icon_name($icon);
        $btn->set_tooltip_text($tooltip);
        $btn->signal_connect(clicked => sub { $cb->() });
        $tb->insert($btn, -1);
    }

    $self->{quick_toolbar} = $tb;
}

sub _make_menu_heading {
    my ($self, $label, $submenu) = @_;
    my $item = Gtk3::MenuItem->new_with_label($label);
    $item->set_submenu($submenu);
    return $item;
}

sub _add_menu_item {
    my ($self, $menu, $label, $accel, $callback) = @_;
    my $item;
    if ($accel && length($accel)) {
        # Create a menu item with a right-aligned accelerator hint
        $item = Gtk3::MenuItem->new;
        my $box = Gtk3::Box->new('horizontal', 12);
        my $lbl = Gtk3::Label->new($label);
        $lbl->set_halign('start');
        my $acc = Gtk3::Label->new($accel);
        $acc->set_halign('end');
        $acc->get_style_context->add_class('dim-label');
        $box->pack_start($lbl, TRUE, TRUE, 0);
        $box->pack_end($acc, FALSE, FALSE, 0);
        $item->add($box);
    } else {
        $item = Gtk3::MenuItem->new_with_label($label);
    }
    $item->signal_connect(activate => sub { $callback->() });
    $menu->append($item);
    return $item;
}

sub _add_separator {
    my ($self, $menu) = @_;
    $menu->append(Gtk3::SeparatorMenuItem->new);
}

sub _populate_recent_menu {
    my ($self) = @_;
    my $mw = $self->{main_window};
    my $menu = $self->{recent_menu};
    return unless $menu;

    # Clear existing items
    $_->destroy for $menu->get_children;

    my $files = HBPerl::Config::recent_files();
    if (!@$files) {
        my $empty = Gtk3::MenuItem->new_with_label('(no recent files)');
        $empty->set_sensitive(FALSE);
        $menu->append($empty);
    } else {
        for my $file (@$files[0 .. ($#$files > 9 ? 9 : $#$files)]) {
            my $label = $file;
            # Show just filename with parent dir for readability
            if ($file =~ m{([^/]+/[^/]+)$}) {
                $label = $1;
            }
            my $item = Gtk3::MenuItem->new_with_label($label);
            $item->set_tooltip_text($file);
            my $f = $file;  # capture for closure
            $item->signal_connect(activate => sub {
                $mw->editor->open_file($f);
            });
            $menu->append($item);
        }
    }
    $menu->show_all;
}

sub refresh_recent_menu {
    my ($self) = @_;
    $self->_populate_recent_menu;
}

sub menubar       { return $_[0]->{menubar} }
sub quick_toolbar { return $_[0]->{quick_toolbar} }

1;

__END__

=head1 NAME

HBPerl::GUI::Toolbar - Menu bar and quick-access toolbar

=head1 DESCRIPTION

Builds the application menu bar (File, Edit, Tools, Run, Scripts,
Tutorials, Help) and a compact icon toolbar for common actions.  Menu
items display keyboard shortcut hints as right-aligned labels.  The
Scripts menu is dynamically populated from L<HBPerl::ScriptRegistry>.

=head1 METHODS

=over 4

=item B<new(main_window =E<gt> $mw)>

Build both the menu bar and the icon toolbar.

=item B<menubar()>

Return the GtkMenuBar widget.

=item B<quick_toolbar()>

Return the GtkToolbar widget.

=back

=head1 AUTHOR

James Temple <james@amiga-fan.net>

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2026 Honey Badger Universe

MIT License

=cut
