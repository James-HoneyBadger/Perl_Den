package BadgerOps::GUI::Dialogs;
# ============================================================================
# BadgerOps::GUI::Dialogs - About, Preferences, Templates, Tutorials dialogs
# ============================================================================
use strict;
use warnings;
use utf8;
use Glib ('TRUE', 'FALSE');
use Gtk3;
use BadgerOps::Config;
use BadgerOps::ScriptRegistry qw(plugins_dir invalidate_cache);
use File::Basename qw(basename);

sub show_about {
    my ($mw) = @_;
    my $dialog = Gtk3::AboutDialog->new;
    $dialog->set_transient_for($mw->window);
    $dialog->set_modal(TRUE);
    $dialog->set_program_name('BadgerOps IDE');
    $dialog->set_version($BadgerOps::App::VERSION // '1.00');
    $dialog->set_comments("Linux Sysadmin Toolkit & Perl Development Environment\n\nA professional IDE for writing, running, and managing\nPerl scripts for Linux system administration.");
    $dialog->set_copyright("© 2026 Honey Badger Universe");
    $dialog->set_license_type('mit-x11');
    $dialog->set_website('https://github.com/James-HoneyBadger/BadgerOps');
    $dialog->set_website_label('GitHub Repository');
    $dialog->set_authors(['James Temple <james@amiga-fan.net>']);
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
        ['  Go to Line',      'Ctrl+G'],
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
    $dialog->set_default_size(520, 500);

    my $content = $dialog->get_content_area;
    $content->set_margin_start(8);
    $content->set_margin_end(8);
    $content->set_margin_top(8);

    # ── Top-level Notebook (Editor | Plugins) ──
    my $notebook = Gtk3::Notebook->new;
    $content->pack_start($notebook, TRUE, TRUE, 0);

    # ── Tab 1: Editor Settings ──
    my $editor_grid = Gtk3::Grid->new;
    $editor_grid->set_row_spacing(10);
    $editor_grid->set_column_spacing(12);
    $editor_grid->set_margin_start(12);
    $editor_grid->set_margin_end(12);
    $editor_grid->set_margin_top(12);
    $editor_grid->set_margin_bottom(8);

    my $row = 0;

    # Font
    my $font_label = Gtk3::Label->new('Editor Font:');
    $font_label->set_halign('end');
    my $font_btn = Gtk3::FontButton->new_with_font(BadgerOps::Config::get('font') // 'monospace 11');
    $editor_grid->attach($font_label, 0, $row, 1, 1);
    $editor_grid->attach($font_btn,   1, $row, 1, 1);
    $row++;

    # Tab width
    my $tab_label = Gtk3::Label->new('Tab Width:');
    $tab_label->set_halign('end');
    my $tab_spin = Gtk3::SpinButton->new_with_range(2, 8, 1);
    $tab_spin->set_value(BadgerOps::Config::get('tab_width') // 4);
    $editor_grid->attach($tab_label, 0, $row, 1, 1);
    $editor_grid->attach($tab_spin,  1, $row, 1, 1);
    $row++;

    # Font scale
    my $scale_label = Gtk3::Label->new('Text Scale:');
    $scale_label->set_halign('end');
    my $scale_box = Gtk3::Box->new('horizontal', 6);
    my $scale_slider = Gtk3::Scale->new_with_range('horizontal', 50, 200, 10);
    $scale_slider->set_value(BadgerOps::Config::get('font_scale') // 100);
    $scale_slider->set_hexpand(TRUE);
    $scale_slider->set_size_request(200, -1);
    my $scale_value_label = Gtk3::Label->new(sprintf('%d%%', BadgerOps::Config::get('font_scale') // 100));
    $scale_slider->signal_connect('value-changed' => sub {
        $scale_value_label->set_text(sprintf('%d%%', $scale_slider->get_value));
    });
    $scale_box->pack_start($scale_slider, TRUE, TRUE, 0);
    $scale_box->pack_start($scale_value_label, FALSE, FALSE, 0);
    $editor_grid->attach($scale_label, 0, $row, 1, 1);
    $editor_grid->attach($scale_box,  1, $row, 1, 1);
    $row++;

    # Theme
    my $theme_label = Gtk3::Label->new('Theme:');
    $theme_label->set_halign('end');
    my $theme_combo = Gtk3::ComboBoxText->new;
    my @themes = (
        ['VS Code Dark+',  'vscode-dark-plus'],
        ['VS Code Light+', 'vscode-light-plus'],
        ['High Contrast',  'high-contrast'],
    );
    $theme_combo->append_text($_->[0]) for @themes;
    my $current_theme = BadgerOps::Config::get('theme') // 'vscode-dark-plus';
    my $theme_idx = 0;
    for my $i (0 .. $#themes) {
        $theme_idx = $i if $themes[$i][1] eq $current_theme;
    }
    $theme_combo->set_active($theme_idx);
    $editor_grid->attach($theme_label, 0, $row, 1, 1);
    $editor_grid->attach($theme_combo, 1, $row, 1, 1);
    $row++;

    # Editor color scheme
    my $scheme_label = Gtk3::Label->new('Color Scheme:');
    $scheme_label->set_halign('end');
    my $scheme_combo = Gtk3::ComboBoxText->new;
    my $ssm = Gtk3::SourceView::StyleSchemeManager::get_default();
    my @schemes = $ssm->get_scheme_ids;
    my $current_scheme = BadgerOps::Config::get('editor_scheme') // 'oblivion';
    my $active_idx = 0;
    for my $i (0 .. $#schemes) {
        $scheme_combo->append_text($schemes[$i]);
        $active_idx = $i if $schemes[$i] eq $current_scheme;
    }
    $scheme_combo->set_active($active_idx);
    $editor_grid->attach($scheme_label, 0, $row, 1, 1);
    $editor_grid->attach($scheme_combo, 1, $row, 1, 1);
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
        for my $i (0 .. $#schemes) {
            if ($schemes[$i] eq $suggested) {
                $scheme_combo->set_active($i);
                last;
            }
        }
    });

    # Dashboard refresh interval
    my $dash_label = Gtk3::Label->new('Dashboard Refresh (s):');
    $dash_label->set_halign('end');
    my $dash_spin = Gtk3::SpinButton->new_with_range(1, 300, 1);
    $dash_spin->set_value(BadgerOps::Config::get('dashboard_refresh_seconds') // 5);
    $dash_spin->set_tooltip_text('How often the dashboard auto-refreshes (in seconds)');
    $editor_grid->attach($dash_label, 0, $row, 1, 1);
    $editor_grid->attach($dash_spin,  1, $row, 1, 1);
    $row++;

    # Batch notifications
    my $notify_label = Gtk3::Label->new('Batch Notifications:');
    $notify_label->set_halign('end');
    my $notify_combo = Gtk3::ComboBoxText->new;
    my @notify_values = (['Always', 'always'], ['Errors only', 'errors'], ['Off', 'off']);
    $notify_combo->append_text($_->[0]) for @notify_values;
    my $cur_notify = BadgerOps::Config::get('notifications') // 'errors';
    my $notify_idx = 1;
    for my $i (0 .. $#notify_values) {
        $notify_idx = $i if $notify_values[$i][1] eq $cur_notify;
    }
    $notify_combo->set_active($notify_idx);
    $notify_combo->set_tooltip_text('When to send desktop notifications after batch runs');
    $editor_grid->attach($notify_label, 0, $row, 1, 1);
    $editor_grid->attach($notify_combo, 1, $row, 1, 1);
    $row++;

    # Show line numbers
    my $ln_check = Gtk3::CheckButton->new_with_label('Show line numbers');
    $ln_check->set_active(BadgerOps::Config::get('show_line_numbers') ? TRUE : FALSE);
    $editor_grid->attach($ln_check, 0, $row, 2, 1);
    $row++;

    # Highlight current line
    my $hl_check = Gtk3::CheckButton->new_with_label('Highlight current line');
    $hl_check->set_active(BadgerOps::Config::get('highlight_line') ? TRUE : FALSE);
    $editor_grid->attach($hl_check, 0, $row, 2, 1);
    $row++;

    # Word wrap
    my $wrap_check = Gtk3::CheckButton->new_with_label('Word wrap');
    $wrap_check->set_active(BadgerOps::Config::get('word_wrap') ? TRUE : FALSE);
    $editor_grid->attach($wrap_check, 0, $row, 2, 1);

    my $editor_sw = Gtk3::ScrolledWindow->new(undef, undef);
    $editor_sw->set_policy('never', 'automatic');
    $editor_sw->add_with_viewport($editor_grid);
    $notebook->append_page($editor_sw, Gtk3::Label->new('Editor'));

    # ── Tab 2: Plugin Manager ──
    my $plugin_vbox = Gtk3::Box->new('vertical', 8);
    $plugin_vbox->set_margin_start(12);
    $plugin_vbox->set_margin_end(12);
    $plugin_vbox->set_margin_top(12);
    $plugin_vbox->set_margin_bottom(8);

    my $plugin_header = Gtk3::Label->new;
    $plugin_header->set_markup('<b>Installed Plugins</b>');
    $plugin_header->set_halign('start');
    $plugin_vbox->pack_start($plugin_header, FALSE, FALSE, 0);

    my $plugin_desc = Gtk3::Label->new(
        "Drop .pm files into ~/.config/badgerops/plugins/ to install plugins.\n" .
        "Toggle the checkbox to enable or disable each plugin."
    );
    $plugin_desc->set_line_wrap(TRUE);
    $plugin_desc->set_halign('start');
    $plugin_desc->get_style_context->add_class('dim-label');
    $plugin_vbox->pack_start($plugin_desc, FALSE, FALSE, 0);

    # ListStore: (bool enabled, string name, string status)
    my $plugin_store = Gtk3::ListStore->new('Glib::Boolean', 'Glib::String', 'Glib::String');
    my $pdir         = plugins_dir();
    my @disabled_now = @{ BadgerOps::Config::get('disabled_plugins') // [] };
    my %disabled_map = map { $_ => 1 } @disabled_now;

    if (-d $pdir) {
        opendir(my $dh, $pdir) or warn "Cannot open plugins dir: $!";
        my @pm_files = sort grep { /\.pm$/ } readdir $dh;
        closedir $dh;
        for my $f (@pm_files) {
            (my $name = $f) =~ s/\.pm$//;
            my $enabled = !$disabled_map{$name};
            my $iter    = $plugin_store->append;
            $plugin_store->set($iter,
                0, $enabled ? TRUE : FALSE,
                1, $name,
                2, $enabled ? 'Enabled' : 'Disabled',
            );
        }
    }

    my $plugin_tv = Gtk3::TreeView->new($plugin_store);
    $plugin_tv->set_headers_visible(TRUE);

    my $toggle_r = Gtk3::CellRendererToggle->new;
    $toggle_r->set_activatable(TRUE);
    $toggle_r->signal_connect(toggled => sub {
        my ($cell, $path_str) = @_;
        my $path = Gtk3::TreePath->new_from_string($path_str);
        my $iter = $plugin_store->get_iter($path);
        my $cur  = $plugin_store->get($iter, 0);
        my $new  = $cur ? FALSE : TRUE;
        $plugin_store->set($iter, 0, $new, 2, $new ? 'Enabled' : 'Disabled');
    });
    my $toggle_col = Gtk3::TreeViewColumn->new_with_attributes(
        'Enabled', $toggle_r, active => 0,
    );
    $plugin_tv->append_column($toggle_col);

    my $name_r   = Gtk3::CellRendererText->new;
    my $name_col = Gtk3::TreeViewColumn->new_with_attributes(
        'Plugin', $name_r, text => 1,
    );
    $name_col->set_expand(TRUE);
    $plugin_tv->append_column($name_col);

    my $status_r   = Gtk3::CellRendererText->new;
    my $status_col = Gtk3::TreeViewColumn->new_with_attributes(
        'Status', $status_r, text => 2,
    );
    $plugin_tv->append_column($status_col);

    my $plugin_sw = Gtk3::ScrolledWindow->new(undef, undef);
    $plugin_sw->set_policy('automatic', 'automatic');
    $plugin_sw->set_min_content_height(160);
    $plugin_sw->add($plugin_tv);
    $plugin_vbox->pack_start($plugin_sw, TRUE, TRUE, 0);

    my $open_dir_btn = Gtk3::Button->new_with_label('Open Plugins Folder');
    $open_dir_btn->set_tooltip_text($pdir);
    $open_dir_btn->signal_connect(clicked => sub {
        system('xdg-open', $pdir) if -d $pdir;
    });
    $plugin_vbox->pack_start($open_dir_btn, FALSE, FALSE, 0);

    $notebook->append_page($plugin_vbox, Gtk3::Label->new('Plugins'));

    $dialog->show_all;

    if ($dialog->run eq 'ok') {
        # Save editor settings
        BadgerOps::Config::set('font',              $font_btn->get_font_name);
        BadgerOps::Config::set('tab_width',         $tab_spin->get_value_as_int);
        BadgerOps::Config::set('font_scale',        int($scale_slider->get_value));
        my $sel_idx = $theme_combo->get_active;
        my $theme_id = ($sel_idx >= 0 && $sel_idx <= $#themes)
            ? $themes[$sel_idx][1]
            : 'vscode-dark-plus';
        BadgerOps::Config::set('theme',             $theme_id);
        BadgerOps::Config::set('editor_scheme',     $scheme_combo->get_active_text);
        my $ni = $notify_combo->get_active;
        BadgerOps::Config::set('notifications',
            ($ni >= 0 && $ni <= $#notify_values) ? $notify_values[$ni][1] : 'errors');
        BadgerOps::Config::set('dashboard_refresh_seconds', $dash_spin->get_value_as_int);
        BadgerOps::Config::set('show_line_numbers', $ln_check->get_active ? 1 : 0);
        BadgerOps::Config::set('highlight_line',    $hl_check->get_active ? 1 : 0);
        BadgerOps::Config::set('word_wrap',         $wrap_check->get_active ? 1 : 0);

        # Save plugin enabled/disabled state
        my @new_disabled;
        my $iter = $plugin_store->get_iter_first;
        while (defined $iter) {
            my ($enabled, $name) = $plugin_store->get($iter, 0, 1);
            push @new_disabled, $name unless $enabled;
            last unless $plugin_store->iter_next($iter);
        }
        BadgerOps::Config::set('disabled_plugins', \@new_disabled);
        invalidate_cache();
        BadgerOps::Config::save();

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
    my $tc = BadgerOps::Config::theme_colors();
    $text_buffer->create_tag('body', foreground => $tc->{fg}, font => BadgerOps::Config::get('font') // 'monospace 11');

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

BadgerOps::GUI::Dialogs - Modal dialogs for the BadgerOps IDE

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

James Temple <james@amiga-fan.net>

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2026 Honey Badger Universe

MIT License

=cut
