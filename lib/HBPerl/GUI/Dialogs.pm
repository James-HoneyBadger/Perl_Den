package HBPerl::GUI::Dialogs;
# ============================================================================
# HBPerl::GUI::Dialogs - About, Preferences, Templates, Tutorials dialogs
# ============================================================================
use strict;
use warnings;
use utf8;
use Glib ('TRUE', 'FALSE');
use Gtk3;
use HBPerl::Config;
use File::Basename qw(basename);

sub show_about {
    my ($mw) = @_;
    my $dialog = Gtk3::AboutDialog->new;
    $dialog->set_transient_for($mw->window);
    $dialog->set_modal(TRUE);
    $dialog->set_program_name('HB Perl IDE');
    $dialog->set_version($HBPerl::App::VERSION // '1.00');
    $dialog->set_comments("Linux Sysadmin Toolkit & Perl Development Environment\n\nA professional IDE for writing, running, and managing\nPerl scripts for Linux system administration.");
    $dialog->set_copyright("© 2026 James");
    $dialog->set_license_type('mit-x11');
    $dialog->set_website('https://github.com/james/HB_Perl');
    $dialog->set_website_label('GitHub Repository');
    $dialog->set_authors(['James']);
    $dialog->run;
    $dialog->destroy;
}

sub show_shortcuts {
    my ($mw) = @_;
    my $dialog = Gtk3::Dialog->new_with_buttons(
        'Keyboard Shortcuts',
        $mw->window,
        'modal',
        'gtk-close' => 'close',
    );
    $dialog->set_default_size(450, 500);

    my $content = $dialog->get_content_area;
    my $sw = Gtk3::ScrolledWindow->new(undef, undef);
    $sw->set_policy('never', 'automatic');

    my $grid = Gtk3::Grid->new;
    $grid->set_row_spacing(6);
    $grid->set_column_spacing(20);
    $grid->set_margin_start(20);
    $grid->set_margin_end(20);
    $grid->set_margin_top(12);

    my @shortcuts = (
        ['File', ''],
        ['  New File',        'Ctrl+N'],
        ['  Open File',       'Ctrl+O'],
        ['  Save',            'Ctrl+S'],
        ['  Save As',         'Ctrl+Shift+S'],
        ['  Close Tab',       'Ctrl+W'],
        ['  Quit',            'Ctrl+Q'],
        ['', ''],
        ['Edit', ''],
        ['  Undo',            'Ctrl+Z'],
        ['  Redo',            'Ctrl+Shift+Z'],
        ['  Find',            'Ctrl+F'],
        ['  Find & Replace',  'Ctrl+Shift+H'],
        ['', ''],
        ['Run', ''],
        ['  Run Script',      'F5'],
        ['  Syntax Check',    'F9'],
        ['', ''],
        ['View', ''],
        ['  Toggle Terminal',  'Ctrl+`'],
    );

    my $row = 0;
    for my $s (@shortcuts) {
        my ($action, $key) = @$s;
        next if $action eq '' && $key eq '';

        if ($key eq '') {
            # Section header
            my $label = Gtk3::Label->new;
            $label->set_markup("<b>$action</b>");
            $label->set_halign('start');
            $grid->attach($label, 0, $row, 2, 1);
        } else {
            my $act_label = Gtk3::Label->new($action);
            $act_label->set_halign('start');
            my $key_label = Gtk3::Label->new;
            $key_label->set_markup("<tt>$key</tt>");
            $key_label->set_halign('end');
            $grid->attach($act_label, 0, $row, 1, 1);
            $grid->attach($key_label, 1, $row, 1, 1);
        }
        $row++;
    }

    $sw->add($grid);
    $content->pack_start($sw, TRUE, TRUE, 0);
    $dialog->show_all;
    $dialog->run;
    $dialog->destroy;
}

sub show_preferences {
    my ($mw) = @_;
    my $dialog = Gtk3::Dialog->new_with_buttons(
        'Preferences',
        $mw->window,
        'modal',
        'gtk-cancel' => 'cancel',
        'gtk-ok'     => 'ok',
    );
    $dialog->set_default_size(500, 400);

    my $content = $dialog->get_content_area;
    $content->set_margin_start(20);
    $content->set_margin_end(20);
    $content->set_margin_top(12);

    my $grid = Gtk3::Grid->new;
    $grid->set_row_spacing(10);
    $grid->set_column_spacing(12);

    my $row = 0;

    # Font
    my $font_label = Gtk3::Label->new('Editor Font:');
    $font_label->set_halign('end');
    my $font_btn = Gtk3::FontButton->new_with_font(HBPerl::Config::get('font') // 'monospace 11');
    $grid->attach($font_label, 0, $row, 1, 1);
    $grid->attach($font_btn,   1, $row, 1, 1);
    $row++;

    # Tab width
    my $tab_label = Gtk3::Label->new('Tab Width:');
    $tab_label->set_halign('end');
    my $tab_spin = Gtk3::SpinButton->new_with_range(2, 8, 1);
    $tab_spin->set_value(HBPerl::Config::get('tab_width') // 4);
    $grid->attach($tab_label, 0, $row, 1, 1);
    $grid->attach($tab_spin,  1, $row, 1, 1);
    $row++;

    # Theme
    my $theme_label = Gtk3::Label->new('Theme:');
    $theme_label->set_halign('end');
    my $theme_combo = Gtk3::ComboBoxText->new;
    my @themes = (
        ['VS Code Dark+',  'vscode-dark-plus'],
        ['VS Code Light+', 'vscode-light-plus'],
    );
    $theme_combo->append_text($_->[0]) for @themes;
    my $current_theme = HBPerl::Config::get('theme') // 'vscode-dark-plus';
    my $theme_idx = 0;
    for my $i (0 .. $#themes) {
        $theme_idx = $i if $themes[$i][1] eq $current_theme;
    }
    $theme_combo->set_active($theme_idx);
    $grid->attach($theme_label, 0, $row, 1, 1);
    $grid->attach($theme_combo, 1, $row, 1, 1);
    $row++;

    # Editor color scheme
    my $scheme_label = Gtk3::Label->new('Color Scheme:');
    $scheme_label->set_halign('end');
    my $scheme_combo = Gtk3::ComboBoxText->new;
    my $ssm = Gtk3::SourceView::StyleSchemeManager->get_default;
    my @schemes = $ssm->get_scheme_ids;
    my $current_scheme = HBPerl::Config::get('editor_scheme') // 'oblivion';
    my $active_idx = 0;
    for my $i (0 .. $#schemes) {
        $scheme_combo->append_text($schemes[$i]);
        $active_idx = $i if $schemes[$i] eq $current_scheme;
    }
    $scheme_combo->set_active($active_idx);
    $grid->attach($scheme_label, 0, $row, 1, 1);
    $grid->attach($scheme_combo, 1, $row, 1, 1);
    $row++;

    # Auto-switch editor scheme when theme changes
    my %default_schemes = (
        'vscode-dark-plus'  => 'oblivion',
        'vscode-light-plus' => 'classic',
    );
    $theme_combo->signal_connect('changed' => sub {
        my $sel_idx = $theme_combo->get_active;
        my $new_theme = ($sel_idx >= 0 && $sel_idx <= $#themes)
            ? $themes[$sel_idx][1]
            : 'vscode-dark-plus';
        my $suggested = $default_schemes{$new_theme} // 'classic';
        # Find and select the suggested scheme in the combo
        for my $i (0 .. $#schemes) {
            if ($schemes[$i] eq $suggested) {
                $scheme_combo->set_active($i);
                last;
            }
        }
    });

    # Show line numbers
    my $ln_check = Gtk3::CheckButton->new_with_label('Show line numbers');
    $ln_check->set_active(HBPerl::Config::get('show_line_numbers') ? TRUE : FALSE);
    $grid->attach($ln_check, 0, $row, 2, 1);
    $row++;

    # Highlight current line
    my $hl_check = Gtk3::CheckButton->new_with_label('Highlight current line');
    $hl_check->set_active(HBPerl::Config::get('highlight_line') ? TRUE : FALSE);
    $grid->attach($hl_check, 0, $row, 2, 1);
    $row++;

    # Word wrap
    my $wrap_check = Gtk3::CheckButton->new_with_label('Word wrap');
    $wrap_check->set_active(HBPerl::Config::get('word_wrap') ? TRUE : FALSE);
    $grid->attach($wrap_check, 0, $row, 2, 1);
    $row++;

    $content->pack_start($grid, FALSE, FALSE, 0);
    $dialog->show_all;

    if ($dialog->run eq 'ok') {
        HBPerl::Config::set('font',              $font_btn->get_font_name);
        HBPerl::Config::set('tab_width',         $tab_spin->get_value_as_int);
        my $sel_idx = $theme_combo->get_active;
        my $theme_id = ($sel_idx >= 0 && $sel_idx <= $#themes)
            ? $themes[$sel_idx][1]
            : 'vscode-dark-plus';
        HBPerl::Config::set('theme',             $theme_id);
        HBPerl::Config::set('editor_scheme',     $scheme_combo->get_active_text);
        HBPerl::Config::set('show_line_numbers', $ln_check->get_active ? 1 : 0);
        HBPerl::Config::set('highlight_line',    $hl_check->get_active ? 1 : 0);
        HBPerl::Config::set('word_wrap',         $wrap_check->get_active ? 1 : 0);
        HBPerl::Config::save();

        # Apply all settings immediately across the entire interface
        $mw->apply_settings;
    }

    $dialog->destroy;
}

sub show_new_from_template {
    my ($mw) = @_;
    my $templates_dir = $mw->app->share_dir . '/templates';

    my @templates;
    if (-d $templates_dir) {
        opendir(my $dh, $templates_dir);
        @templates = sort grep { /\.pl$/ } readdir $dh;
        closedir $dh;
    }

    if (!@templates) {
        my $info = Gtk3::MessageDialog->new(
            $mw->window, 'modal', 'info', 'ok',
            "No templates found in $templates_dir"
        );
        $info->run;
        $info->destroy;
        return;
    }

    my $dialog = Gtk3::Dialog->new_with_buttons(
        'New Script from Template',
        $mw->window,
        'modal',
        'gtk-cancel' => 'cancel',
        'gtk-ok'     => 'ok',
    );
    $dialog->set_default_size(400, 300);

    my $content = $dialog->get_content_area;

    my $label = Gtk3::Label->new('Select a template:');
    $label->set_halign('start');
    $label->set_margin_start(12);
    $label->set_margin_top(8);
    $content->pack_start($label, FALSE, FALSE, 4);

    my $store = Gtk3::ListStore->new('Glib::String', 'Glib::String');
    for my $t (@templates) {
        my $iter = $store->append;
        my $display = $t;
        $display =~ s/\.pl$//;
        $display =~ s/_/ /g;
        $display =~ s/\b(\w)/uc($1)/ge;
        $store->set($iter, 0, $display, 1, $t);
    }

    my $tree = Gtk3::TreeView->new($store);
    $tree->set_headers_visible(FALSE);
    my $col = Gtk3::TreeViewColumn->new_with_attributes(
        'Template', Gtk3::CellRendererText->new, text => 0,
    );
    $tree->append_column($col);

    my $sw = Gtk3::ScrolledWindow->new(undef, undef);
    $sw->add($tree);
    $content->pack_start($sw, TRUE, TRUE, 4);

    $dialog->show_all;

    if ($dialog->run eq 'ok') {
        my ($sel_path) = $tree->get_selection->get_selected_rows;
        if ($sel_path) {
            my $iter = $store->get_iter($sel_path);
            my $filename = $store->get($iter, 1);
            my $filepath = "$templates_dir/$filename";
            if (-f $filepath) {
                open my $fh, '<:encoding(UTF-8)', $filepath;
                local $/;
                my $content_text = <$fh>;
                close $fh;
                $mw->editor->new_file;
                # Get the newest tab and set its content
                my $tabs = $mw->editor->{tabs};
                if (@$tabs) {
                    $tabs->[-1]{buffer}->set_text($content_text);
                }
            }
        }
    }

    $dialog->destroy;
}

sub show_tutorial_browser {
    my ($mw) = @_;
    my $tutorials_dir = $mw->app->share_dir . '/tutorials';

    my @tutorials;
    if (-d $tutorials_dir) {
        opendir(my $dh, $tutorials_dir);
        @tutorials = sort grep { /\.pod$/ } readdir $dh;
        closedir $dh;
    }

    if (!@tutorials) {
        my $info = Gtk3::MessageDialog->new(
            $mw->window, 'modal', 'info', 'ok',
            "No tutorials found in $tutorials_dir"
        );
        $info->run;
        $info->destroy;
        return;
    }

    my $dialog = Gtk3::Dialog->new_with_buttons(
        'Perl & Linux Tutorials',
        $mw->window,
        'modal',
        'gtk-close' => 'close',
    );
    $dialog->set_default_size(800, 600);

    my $content = $dialog->get_content_area;

    my $paned = Gtk3::Paned->new('horizontal');
    $paned->set_position(220);

    # Left: tutorial list
    my $store = Gtk3::ListStore->new('Glib::String', 'Glib::String');
    for my $t (@tutorials) {
        my $iter = $store->append;
        my $display = $t;
        $display =~ s/^\d+_//;
        $display =~ s/\.pod$//;
        $display =~ s/_/ /g;
        $display =~ s/\b(\w)/uc($1)/ge;
        $store->set($iter, 0, $display, 1, "$tutorials_dir/$t");
    }

    my $tree = Gtk3::TreeView->new($store);
    $tree->set_headers_visible(FALSE);
    $tree->append_column(
        Gtk3::TreeViewColumn->new_with_attributes(
            'Tutorial', Gtk3::CellRendererText->new, text => 0,
        )
    );

    my $tree_sw = Gtk3::ScrolledWindow->new(undef, undef);
    $tree_sw->add($tree);
    $paned->pack1($tree_sw, FALSE, FALSE);

    # Right: tutorial content
    my $text_buffer = Gtk3::TextBuffer->new;
    my $tc = HBPerl::Config::theme_colors();
    $text_buffer->create_tag('body', foreground => $tc->{fg}, font => HBPerl::Config::get('font') // 'monospace 11');

    my $text_view = Gtk3::TextView->new_with_buffer($text_buffer);
    $text_view->set_editable(FALSE);
    $text_view->set_wrap_mode('word');
    $text_view->set_margin_start(12);
    $text_view->set_margin_end(12);
    $text_view->set_margin_top(8);

    my $text_sw = Gtk3::ScrolledWindow->new(undef, undef);
    $text_sw->add($text_view);
    $paned->pack2($text_sw, TRUE, TRUE);

    $tree->signal_connect('cursor-changed' => sub {
        my ($sel_model, $sel_iter) = $tree->get_selection->get_selected;
        return unless $sel_iter;
        my $filepath = $store->get($sel_iter, 1);
        if (-f $filepath) {
            my $pod_text = '';
            if (open(my $fh, '-|', 'pod2text', $filepath)) {
                local $/;
                $pod_text = <$fh> // '';
                close $fh;
            }
            $text_buffer->set_text('');
            my $end = $text_buffer->get_end_iter;
            $text_buffer->insert_with_tags_by_name($end, $pod_text, 'body');
        }
    });

    $content->pack_start($paned, TRUE, TRUE, 0);
    $dialog->show_all;

    # Select first tutorial
    if (@tutorials) {
        $tree->get_selection->select_path(Gtk3::TreePath->new_from_string('0'));
        $tree->signal_emit('cursor-changed');
    }

    $dialog->run;
    $dialog->destroy;
}

1;

__END__

=head1 NAME

HBPerl::GUI::Dialogs - Modal dialogs for the HB Perl IDE

=head1 DESCRIPTION

Provides standalone dialog functions called from the menu bar.  Each
function takes the main window reference and creates a transient modal
dialog.

=head1 FUNCTIONS

=over 4

=item B<show_about($mw)>

GTK AboutDialog with version, author, and license.

=item B<show_shortcuts($mw)>

Keyboard shortcut reference card.

=item B<show_preferences($mw)>

Settings dialog for theme, font, editor scheme, tab width, and editor
toggles.  Changes are applied immediately.

=item B<show_new_from_template($mw)>

Browse and preview script templates from F<share/templates/>.  The
selected template is opened as a new editor tab.

=item B<show_tutorial_browser($mw)>

Browse the 12 Perl tutorials from F<share/tutorials/>.  POD content is
rendered via C<pod2text>.

=back

=head1 AUTHOR

James

=head1 LICENSE

MIT

=cut
