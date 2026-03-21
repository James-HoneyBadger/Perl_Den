package HBPerl::GUI::Editor;
# ============================================================================
# HBPerl::GUI::Editor - Tabbed source code editor with GtkSourceView
# ============================================================================
use strict;
use warnings;
use utf8;
use Glib ('TRUE', 'FALSE');
use Gtk3;
use Gtk3::SourceView;
use File::Basename qw(basename dirname);
use HBPerl::Config;

sub new {
    my ($class, %args) = @_;
    my $self = bless {
        main_window => $args{main_window},
        notebook    => $args{notebook},
        tabs        => [],  # [ { file => path, view => widget, buffer => buf, label => lbl } ]
        untitled_count => 0,
        lang_manager   => Gtk3::SourceView::LanguageManager->get_default,
        scheme_manager => Gtk3::SourceView::StyleSchemeManager->get_default,
        find_bar       => undef,
    }, $class;
    return $self;
}

# ── Tab Management ──

sub new_file {
    my ($self) = @_;
    $self->{untitled_count}++;
    my $name = "Untitled-$self->{untitled_count}.pl";
    $self->_create_tab(undef, $name, "#!/usr/bin/perl\nuse strict;\nuse warnings;\n\n");
}

sub open_file {
    my ($self, $filepath) = @_;
    return unless $filepath;

    # Check if already open
    for my $i (0 .. $#{$self->{tabs}}) {
        if ($self->{tabs}[$i]{file} && $self->{tabs}[$i]{file} eq $filepath) {
            $self->{notebook}->set_current_page($i + 1);  # +1 for dashboard
            return;
        }
    }

    # Large file guard: warn if >1MB
    my $file_size = -s $filepath // 0;
    my $disable_highlight = 0;
    if ($file_size > 1_048_576) {
        my $dialog = Gtk3::MessageDialog->new(
            $self->{main_window}->window,
            'modal',
            'warning',
            'yes-no',
            "This file is %s. Syntax highlighting may be slow.\n\nDisable highlighting for better performance?",
            sprintf('%.1f MB', $file_size / 1_048_576),
        );
        $disable_highlight = 1 if $dialog->run eq 'yes';
        $dialog->destroy;
    }

    my $content;
    eval {
        open my $fh, '<:encoding(UTF-8)', $filepath or die "open: $!";
        local $/;
        $content = <$fh>;
        close $fh;
    };
    if ($@) {
        # Fallback to Latin-1 if UTF-8 decoding fails
        eval {
            open my $fh, '<:encoding(iso-8859-1)', $filepath or die "open: $!";
            local $/;
            $content = <$fh>;
            close $fh;
        };
        if ($@) {
            $self->{main_window}->set_status("Error: Cannot open $filepath");
            return;
        }
        $self->{main_window}->set_status("Warning: $filepath opened as Latin-1 (not valid UTF-8)");
    }

    my $name = basename($filepath);
    $self->_create_tab($filepath, $name, $content, 0, $disable_highlight);
    HBPerl::Config::add_recent_file($filepath);
    $self->{main_window}->set_status("Opened: $filepath");
}

sub open_file_dialog {
    my ($self) = @_;
    my $dialog = Gtk3::FileChooserDialog->new(
        'Open File',
        $self->{main_window}->window,
        'open',
        'gtk-cancel' => 'cancel',
        'gtk-open'   => 'ok',
    );

    # Add Perl file filter
    my $filter_pl = Gtk3::FileFilter->new;
    $filter_pl->set_name('Perl Files (*.pl, *.pm, *.t)');
    $filter_pl->add_pattern('*.pl');
    $filter_pl->add_pattern('*.pm');
    $filter_pl->add_pattern('*.t');
    $dialog->add_filter($filter_pl);

    my $filter_all = Gtk3::FileFilter->new;
    $filter_all->set_name('All Files');
    $filter_all->add_pattern('*');
    $dialog->add_filter($filter_all);

    if ($dialog->run eq 'ok') {
        my $file = $dialog->get_filename;
        $self->open_file($file);
    }
    $dialog->destroy;
}

sub save_current_file {
    my ($self) = @_;
    my $tab = $self->_current_tab;
    return unless $tab;

    if (!$tab->{file}) {
        return $self->save_file_as;
    }

    $self->_save_tab($tab);
}

sub save_file_as {
    my ($self) = @_;
    my $tab = $self->_current_tab;
    return unless $tab;

    my $dialog = Gtk3::FileChooserDialog->new(
        'Save File As',
        $self->{main_window}->window,
        'save',
        'gtk-cancel' => 'cancel',
        'gtk-save'   => 'ok',
    );
    $dialog->set_do_overwrite_confirmation(TRUE);

    if ($tab->{file}) {
        $dialog->set_filename($tab->{file});
    } else {
        $dialog->set_current_name($tab->{name});
    }

    if ($dialog->run eq 'ok') {
        my $file = $dialog->get_filename;
        $tab->{file} = $file;
        $tab->{name} = basename($file);
        $tab->{label}->set_text($tab->{name});
        $self->_save_tab($tab);
        HBPerl::Config::add_recent_file($file);
    }
    $dialog->destroy;
}

sub close_current_tab {
    my ($self) = @_;
    my $page = $self->{notebook}->get_current_page;
    return if $page <= 0;  # Don't close dashboard (page 0)

    my $tab_idx = $page - 1;  # -1 for dashboard offset
    my $tab = $self->{tabs}[$tab_idx];
    return unless $tab;

    if ($tab->{buffer}->get_modified) {
        my $dialog = Gtk3::MessageDialog->new(
            $self->{main_window}->window,
            'modal',
            'question',
            'none',
            "Save changes to %s?",
            $tab->{name},
        );
        $dialog->add_button('Don\'t Save', 'reject');
        $dialog->add_button('Cancel', 'cancel');
        $dialog->add_button('Save', 'accept');

        my $response = $dialog->run;
        $dialog->destroy;

        if ($response eq 'accept') {
            $self->save_current_file;
        } elsif ($response eq 'cancel') {
            return;
        }
    }

    $self->{notebook}->remove_page($page);
    splice @{$self->{tabs}}, $tab_idx, 1;

    # Hide find bar if no tabs left
    if (!@{$self->{tabs}} && $self->{find_bar}) {
        $self->{find_bar}->hide;
    }
}

# ── Editor Actions ──

sub undo {
    my ($self) = @_;
    my $tab = $self->_current_tab or return;
    $tab->{buffer}->undo if $tab->{buffer}->can_undo;
}

sub redo {
    my ($self) = @_;
    my $tab = $self->_current_tab or return;
    $tab->{buffer}->redo if $tab->{buffer}->can_redo;
}

sub syntax_check {
    my ($self) = @_;
    my $tab = $self->_current_tab or return;
    my $file = $tab->{file};

    if (!$file) {
        # Save to temp for checking
        require File::Temp;
        my $tmp = File::Temp->new(SUFFIX => '.pl', UNLINK => 0);
        my $text = $self->_get_buffer_text($tab->{buffer});
        print $tmp $text;
        close $tmp;
        $file = $tmp->filename;
    }

    my $output;
    {
        my $pid = open(my $fh, '-|');
        if (!defined $pid) {
            $output = "Failed to fork: $!\n";
        } elsif ($pid == 0) {
            open STDERR, '>&', \*STDOUT;
            exec($^X, '-c', $file) or die "exec failed: $!";
        } else {
            local $/;
            $output = <$fh> // '';
            close $fh;
        }
    }
    my $rc = $? >> 8;

    # Clean up temp file
    if (!$tab->{file}) {
        unlink $file;
    }

    $self->{main_window}->append_output(
        "=== Syntax Check: $tab->{name} ===\n$output\n",
        $rc == 0 ? 'success' : 'error',
    );
    $self->{main_window}->set_status(
        $rc == 0 ? "Syntax OK: $tab->{name}" : "Syntax errors in $tab->{name}"
    );
}

sub format_code {
    my ($self) = @_;
    my $tab = $self->_current_tab or return;

    eval { require Perl::Tidy };
    if ($@) {
        $self->{main_window}->set_status("Perl::Tidy not installed");
        return;
    }

    my $source = $self->_get_buffer_text($tab->{buffer});
    my $result = '';
    my $stderr = '';

    eval {
        Perl::Tidy::perltidy(
            source      => \$source,
            destination => \$result,
            stderr      => \$stderr,
        );
    };

    if ($@ || $stderr) {
        $self->{main_window}->append_output("Tidy error: " . ($@ // $stderr) . "\n", 'error');
    } else {
        $tab->{buffer}->begin_not_undoable_action;
        $tab->{buffer}->set_text($result);
        $tab->{buffer}->end_not_undoable_action;
        $self->{main_window}->set_status("Code formatted: $tab->{name}");
    }
}

sub lint_code {
    my ($self) = @_;
    my $tab = $self->_current_tab or return;

    my $file = $tab->{file};
    if (!$file) {
        $self->{main_window}->set_status("Save file first to run Perl::Critic");
        return;
    }

    $self->save_current_file;

    my $output;
    {
        my $pid = open(my $fh, '-|');
        if (!defined $pid) {
            $output = "Failed to fork: $!\n";
        } elsif ($pid == 0) {
            open STDERR, '>&', \*STDOUT;
            exec('perlcritic', '--severity', '4', $file) or die "exec failed: $!";
        } else {
            local $/;
            $output = <$fh> // '';
            close $fh;
        }
    }
    $self->{main_window}->append_output(
        "=== Perl::Critic: $tab->{name} ===\n$output\n",
        'info',
    );
}

sub pod_preview {
    my ($self) = @_;
    my $tab = $self->_current_tab or return;
    my $text = $self->_get_buffer_text($tab->{buffer});

    # Convert POD to text using pod2text
    require File::Temp;
    my $tmp = File::Temp->new(SUFFIX => '.pm');
    print $tmp $text;
    close $tmp;

    my $pod_text;
    {
        my $pid = open(my $fh, '-|');
        if (!defined $pid) {
            $pod_text = '';
        } elsif ($pid == 0) {
            open STDERR, '>&', \*STDOUT;
            exec('pod2text', $tmp->filename) or die "exec failed: $!";
        } else {
            local $/;
            $pod_text = <$fh> // '';
            close $fh;
        }
    }

    if ($pod_text && $pod_text !~ /^\s*$/) {
        # Open a new read-only tab with POD content
        my $name = "POD: $tab->{name}";
        my $page_idx = $self->_create_tab(undef, $name, $pod_text, 1);
    } else {
        $self->{main_window}->set_status("No POD documentation found");
    }
}

# ── Find / Replace ──

sub show_find_bar {
    my ($self) = @_;
    $self->_ensure_find_bar;
    $self->{replace_entry}->hide if $self->{replace_entry};
    $self->{replace_btn}->hide if $self->{replace_btn};
    $self->{replace_all_btn}->hide if $self->{replace_all_btn};
    $self->{find_bar}->show_all;
    $self->{replace_entry}->hide;
    $self->{replace_btn}->hide;
    $self->{replace_all_btn}->hide;
    $self->{find_entry}->grab_focus;
}

sub show_find_replace_bar {
    my ($self) = @_;
    $self->_ensure_find_bar;
    $self->{find_bar}->show_all;
    $self->{find_entry}->grab_focus;
}

# ── Go-to-Line (Ctrl+G) ──

sub goto_line_dialog {
    my ($self) = @_;
    my $tab = $self->_current_tab or return;

    my $dialog = Gtk3::Dialog->new_with_buttons(
        'Go to Line',
        $self->{main_window}->window,
        'modal',
        'gtk-cancel' => 'cancel',
        'gtk-ok'     => 'ok',
    );
    $dialog->set_default_size(250, -1);

    my $content = $dialog->get_content_area;
    my $box = Gtk3::Box->new('horizontal', 8);
    $box->set_margin_start(12);
    $box->set_margin_end(12);
    $box->set_margin_top(8);
    $box->set_margin_bottom(8);

    my $label = Gtk3::Label->new('Line number:');
    $box->pack_start($label, FALSE, FALSE, 0);

    my $total_lines = $tab->{buffer}->get_line_count;
    my $entry = Gtk3::SpinButton->new_with_range(1, $total_lines, 1);
    # Start at current line
    my $iter = $tab->{buffer}->get_iter_at_mark($tab->{buffer}->get_insert);
    $entry->set_value($iter->get_line + 1);
    $entry->signal_connect('activate' => sub { $dialog->response('ok') });
    $box->pack_start($entry, TRUE, TRUE, 0);

    $content->pack_start($box, FALSE, FALSE, 0);
    $dialog->show_all;
    $entry->grab_focus;

    if ($dialog->run eq 'ok') {
        my $line = $entry->get_value_as_int - 1;
        $line = 0 if $line < 0;
        $line = $total_lines - 1 if $line >= $total_lines;
        my $target = $tab->{buffer}->get_iter_at_line($line);
        $tab->{buffer}->place_cursor($target);
        $tab->{view}->scroll_to_iter($target, 0.1, TRUE, 0.0, 0.5);
    }
    $dialog->destroy;
}

sub _ensure_find_bar {
    my ($self) = @_;
    return if $self->{find_bar};

    my $bar = Gtk3::Box->new('horizontal', 4);
    $bar->get_style_context->add_class('search-bar');
    $bar->set_margin_start(4);
    $bar->set_margin_end(4);
    $bar->set_margin_top(2);
    $bar->set_margin_bottom(2);

    my $find_label = Gtk3::Label->new('Find:');
    $bar->pack_start($find_label, FALSE, FALSE, 4);

    my $find_entry = Gtk3::Entry->new;
    $find_entry->set_width_chars(30);
    $find_entry->set_placeholder_text('Search...');
    $bar->pack_start($find_entry, FALSE, FALSE, 0);
    $self->{find_entry} = $find_entry;

    my $next_btn = Gtk3::Button->new_with_label('Next');
    $next_btn->signal_connect(clicked => sub { $self->_find_next });
    $bar->pack_start($next_btn, FALSE, FALSE, 2);

    my $prev_btn = Gtk3::Button->new_with_label('Prev');
    $prev_btn->signal_connect(clicked => sub { $self->_find_prev });
    $bar->pack_start($prev_btn, FALSE, FALSE, 2);

    my $replace_entry = Gtk3::Entry->new;
    $replace_entry->set_width_chars(20);
    $replace_entry->set_placeholder_text('Replace with...');
    $bar->pack_start($replace_entry, FALSE, FALSE, 4);
    $self->{replace_entry} = $replace_entry;

    my $replace_btn = Gtk3::Button->new_with_label('Replace');
    $replace_btn->signal_connect(clicked => sub { $self->_replace_one });
    $bar->pack_start($replace_btn, FALSE, FALSE, 2);
    $self->{replace_btn} = $replace_btn;

    my $replace_all_btn = Gtk3::Button->new_with_label('All');
    $replace_all_btn->signal_connect(clicked => sub { $self->_replace_all });
    $bar->pack_start($replace_all_btn, FALSE, FALSE, 2);
    $self->{replace_all_btn} = $replace_all_btn;

    my $menu_icon_size = Gtk3::IconSize::from_name('gtk-menu');
    my $close_btn = Gtk3::Button->new_from_icon_name('window-close-symbolic', $menu_icon_size);
    $close_btn->set_relief('none');
    $close_btn->signal_connect(clicked => sub { $bar->hide });
    $bar->pack_end($close_btn, FALSE, FALSE, 2);

    # Enter key triggers find
    $find_entry->signal_connect('activate' => sub { $self->_find_next });

    # Escape key dismisses find bar and returns focus to editor
    $find_entry->signal_connect('key-press-event' => sub {
        my ($widget, $event) = @_;
        if ($event->keyval == 0xff1b) {  # GDK_KEY_Escape
            $bar->hide;
            my $tab = $self->current_tab;
            $tab->{view}->grab_focus if $tab;
            return TRUE;
        }
        return FALSE;
    });
    $replace_entry->signal_connect('key-press-event' => sub {
        my ($widget, $event) = @_;
        if ($event->keyval == 0xff1b) {  # GDK_KEY_Escape
            $bar->hide;
            my $tab = $self->current_tab;
            $tab->{view}->grab_focus if $tab;
            return TRUE;
        }
        return FALSE;
    });

    # Insert the find bar above the notebook
    my $parent = $self->{notebook}->get_parent;
    if ($parent && $parent->isa('Gtk3::Paned')) {
        my $box = Gtk3::Box->new('vertical', 0);
        $parent->remove($self->{notebook});
        # Re-check child positioning
        $box->pack_start($bar, FALSE, FALSE, 0);
        $box->pack_start($self->{notebook}, TRUE, TRUE, 0);
        $parent->pack1($box, TRUE, TRUE);
        $box->show_all;
        $bar->hide;  # Start hidden
        $self->{editor_box} = $box;
    }

    $self->{find_bar} = $bar;
}

sub _find_next {
    my ($self) = @_;
    my $tab = $self->_current_tab or return;
    my $search_text = $self->{find_entry}->get_text;
    return unless length $search_text;

    my $buffer = $tab->{buffer};
    my $settings = Gtk3::SourceView::SearchSettings->new;
    $settings->set_search_text($search_text);
    $settings->set_case_sensitive(FALSE);
    $settings->set_wrap_around(TRUE);

    my $context = Gtk3::SourceView::SearchContext->new($buffer, $settings);

    my $iter = $buffer->get_iter_at_mark($buffer->get_insert);
    $iter->forward_char;  # Move past current position

    my ($match_start, $match_end, $wrapped) = $context->forward($iter);
    if ($match_start) {
        $buffer->select_range($match_start, $match_end);
        $tab->{view}->scroll_to_iter($match_start, 0.1, FALSE, 0, 0.5);
    }
}

sub _find_prev {
    my ($self) = @_;
    my $tab = $self->_current_tab or return;
    my $search_text = $self->{find_entry}->get_text;
    return unless length $search_text;

    my $buffer = $tab->{buffer};
    my $settings = Gtk3::SourceView::SearchSettings->new;
    $settings->set_search_text($search_text);
    $settings->set_case_sensitive(FALSE);
    $settings->set_wrap_around(TRUE);

    my $context = Gtk3::SourceView::SearchContext->new($buffer, $settings);
    my $iter = $buffer->get_iter_at_mark($buffer->get_insert);

    my ($match_start, $match_end, $wrapped) = $context->backward($iter);
    if ($match_start) {
        $buffer->select_range($match_start, $match_end);
        $tab->{view}->scroll_to_iter($match_start, 0.1, FALSE, 0, 0.5);
    }
}

sub _replace_one {
    my ($self) = @_;
    my $tab = $self->_current_tab or return;
    my $search_text  = $self->{find_entry}->get_text;
    my $replace_text = $self->{replace_entry}->get_text;
    return unless length $search_text;

    my $buffer = $tab->{buffer};
    my ($has_sel, $sel_start, $sel_end) = $buffer->get_selection_bounds;

    if ($has_sel) {
        my $settings = Gtk3::SourceView::SearchSettings->new;
        $settings->set_search_text($search_text);
        my $context = Gtk3::SourceView::SearchContext->new($buffer, $settings);
        eval { $context->replace($sel_start, $sel_end, $replace_text, -1) };
    }
    $self->_find_next;
}

sub _replace_all {
    my ($self) = @_;
    my $tab = $self->_current_tab or return;
    my $search_text  = $self->{find_entry}->get_text;
    my $replace_text = $self->{replace_entry}->get_text;
    return unless length $search_text;

    my $buffer = $tab->{buffer};
    my $settings = Gtk3::SourceView::SearchSettings->new;
    $settings->set_search_text($search_text);
    my $context = Gtk3::SourceView::SearchContext->new($buffer, $settings);
    my $count = eval { $context->replace_all($replace_text, -1) } // 0;

    $self->{main_window}->set_status("Replaced $count occurrence(s)");
}

# ── Internals ──

sub _create_tab {
    my ($self, $filepath, $name, $content, $readonly, $no_highlight) = @_;
    $content //= '';

    # Determine language from filename
    my $lang;
    if ($name =~ /\.(pl|pm|t|pod)$/i) {
        $lang = $self->{lang_manager}->get_language('perl');
    } elsif ($name =~ /\.py$/i) {
        $lang = $self->{lang_manager}->get_language('python');
    } elsif ($name =~ /\.sh$/i) {
        $lang = $self->{lang_manager}->get_language('sh');
    } elsif ($name =~ /\.css$/i) {
        $lang = $self->{lang_manager}->get_language('css');
    } elsif ($name =~ /\.ya?ml$/i) {
        $lang = $self->{lang_manager}->get_language('yaml');
    } elsif ($name =~ /\.json$/i) {
        $lang = $self->{lang_manager}->get_language('json');
    } else {
        $lang = $self->{lang_manager}->guess_language($name, undef);
    }

    # Create buffer
    my $buffer;
    if ($lang) {
        $buffer = Gtk3::SourceView::Buffer->new_with_language($lang);
    } else {
        $buffer = Gtk3::SourceView::Buffer->new(undef);
    }
    $buffer->set_highlight_syntax($no_highlight ? FALSE : TRUE);
    $buffer->set_highlight_matching_brackets(TRUE);
    $buffer->set_text($content);
    $buffer->set_modified(FALSE);
    $buffer->place_cursor($buffer->get_start_iter);

    # Apply color scheme
    my $scheme_name = HBPerl::Config::get('editor_scheme') // 'oblivion';
    my $scheme = $self->{scheme_manager}->get_scheme($scheme_name);
    $buffer->set_style_scheme($scheme) if $scheme;

    # Create view
    my $view = Gtk3::SourceView::View->new_with_buffer($buffer);
    $view->set_show_line_numbers(HBPerl::Config::get('show_line_numbers') // TRUE);
    $view->set_highlight_current_line(HBPerl::Config::get('highlight_line') // TRUE);
    $view->set_auto_indent(HBPerl::Config::get('auto_indent') // TRUE);
    $view->set_tab_width(HBPerl::Config::get('tab_width') // 4);
    $view->set_insert_spaces_instead_of_tabs(TRUE);
    $view->set_smart_backspace(TRUE);
    $view->set_show_right_margin(TRUE);
    $view->set_right_margin_position(100);
    $view->set_wrap_mode(HBPerl::Config::get('word_wrap') ? 'word' : 'none');
    $view->set_editable(!$readonly);

    # Font
    my $font = HBPerl::Config::get('font') // 'monospace 11';
    my $font_desc = Pango::FontDescription::from_string($font);
    my $font_scale = (HBPerl::Config::get('font_scale') // 100) / 100.0;
    if ($font_scale != 1.0 && $font_desc->get_size > 0) {
        $font_desc->set_size(int($font_desc->get_size * $font_scale));
    }
    $view->override_font($font_desc);

    # Wrap in scrolled window
    my $sw = Gtk3::ScrolledWindow->new(undef, undef);
    $sw->set_policy('automatic', 'automatic');
    $sw->add($view);

    # Tab label with close button
    my $tab_box = Gtk3::Box->new('horizontal', 4);
    my $label = Gtk3::Label->new($name);
    # Show full file path on hover
    if ($filepath) {
        $label->set_tooltip_text($filepath);
        $tab_box->set_tooltip_text($filepath);
    }
    my $menu_icon_size = Gtk3::IconSize::from_name('gtk-menu');
    my $close_btn = Gtk3::Button->new_from_icon_name('window-close-symbolic', $menu_icon_size);
    $close_btn->set_relief('none');
    $close_btn->get_style_context->add_class('flat');

    $tab_box->pack_start($label, TRUE, TRUE, 0);
    $tab_box->pack_start($close_btn, FALSE, FALSE, 0);
    $tab_box->show_all;

    # Add tab to notebook
    my $page_num = $self->{notebook}->append_page($sw, $tab_box);
    $self->{notebook}->set_tab_reorderable($sw, TRUE);
    $sw->show_all;
    $self->{notebook}->set_current_page($page_num);

    my $tab = {
        file   => $filepath,
        name   => $name,
        view   => $view,
        buffer => $buffer,
        label  => $label,
        sw     => $sw,
    };
    push @{$self->{tabs}}, $tab;

    # Close button handler
    $close_btn->signal_connect(clicked => sub {
        my $idx = $self->_find_tab_index($tab);
        if (defined $idx) {
            $self->{notebook}->set_current_page($idx + 1);
            $self->close_current_tab;
        }
    });

    # Track cursor position
    $buffer->signal_connect('notify::cursor-position' => sub {
        my $iter = $buffer->get_iter_at_mark($buffer->get_insert);
        my $line = $iter->get_line + 1;
        my $col  = $iter->get_line_offset + 1;
        $self->{main_window}->set_cursor_position($line, $col);
    });

    # Track modifications (update tab title)
    $buffer->signal_connect('modified-changed' => sub {
        if ($buffer->get_modified) {
            $label->set_text("● $name");
        } else {
            $label->set_text($name);
        }
    });

    return $page_num;
}

sub _save_tab {
    my ($self, $tab) = @_;
    return unless $tab && $tab->{file};

    my $text = $self->_get_buffer_text($tab->{buffer});

    open my $fh, '>:encoding(UTF-8)', $tab->{file} or do {
        $self->{main_window}->set_status("Error saving: $!");
        return;
    };
    print $fh $text;
    close $fh;

    $tab->{buffer}->set_modified(FALSE);
    $self->{main_window}->set_status("Saved: $tab->{file}");
}

sub _get_buffer_text {
    my ($self, $buffer) = @_;
    return $buffer->get_text(
        $buffer->get_start_iter,
        $buffer->get_end_iter,
        TRUE,
    );
}

sub _current_tab {
    my ($self) = @_;
    my $page = $self->{notebook}->get_current_page;
    return undef if $page <= 0;  # Dashboard or nothing
    my $idx = $page - 1;
    return $self->{tabs}[$idx];
}

sub _find_tab_index {
    my ($self, $target_tab) = @_;
    for my $i (0 .. $#{$self->{tabs}}) {
        return $i if $self->{tabs}[$i] == $target_tab;
    }
    return undef;
}

sub apply_settings {
    my ($self) = @_;
    my $font_str   = HBPerl::Config::get('font') // 'monospace 11';
    my $font_desc  = Pango::FontDescription::from_string($font_str);
    my $font_scale = (HBPerl::Config::get('font_scale') // 100) / 100.0;
    if ($font_scale != 1.0 && $font_desc->get_size > 0) {
        $font_desc->set_size(int($font_desc->get_size * $font_scale));
    }
    my $tab_width  = HBPerl::Config::get('tab_width') // 4;
    my $show_ln    = HBPerl::Config::get('show_line_numbers') // 1;
    my $hl_line    = HBPerl::Config::get('highlight_line') // 1;
    my $wrap       = HBPerl::Config::get('word_wrap') ? 'word' : 'none';
    my $scheme_name = HBPerl::Config::get('editor_scheme') // 'oblivion';
    my $scheme      = $self->{scheme_manager}->get_scheme($scheme_name);

    for my $tab (@{$self->{tabs}}) {
        my $view   = $tab->{view};
        my $buffer = $tab->{buffer};
        $view->override_font($font_desc);
        $view->set_tab_width($tab_width);
        $view->set_show_line_numbers($show_ln ? TRUE : FALSE);
        $view->set_highlight_current_line($hl_line ? TRUE : FALSE);
        $view->set_wrap_mode($wrap);
        $buffer->set_style_scheme($scheme) if $scheme;
    }
}

sub get_current_file {
    my ($self) = @_;
    my $tab = $self->_current_tab;
    return $tab ? $tab->{file} : undef;
}

sub get_open_files {
    my ($self) = @_;
    return map { $_->{file} } grep { $_->{file} } @{$self->{tabs}};
}

1;

__END__

=head1 NAME

HBPerl::GUI::Editor - GtkSourceView-based tabbed code editor

=head1 DESCRIPTION

A multi-tab code editor using GtkSourceView 3 with Perl syntax
highlighting, line numbers, bracket matching, and auto-indent.
Provides file operations, search/replace, syntax checking (C<perl -c>),
code formatting (L<Perl::Tidy>), linting (L<Perl::Critic>), and POD
preview.

=head1 METHODS

=over 4

=item B<new(main_window =E<gt> $mw, share_dir =E<gt> $path, has_vte =E<gt> $bool)>

Build the editor notebook.  The first tab is the Dashboard.

=item B<new_file()>, B<open_file($path)>, B<open_file_dialog()>

File opening operations.  Duplicate opens are focused rather than re-opened.

=item B<save_current_file()>, B<save_file_as()>

Save operations.  Modified tabs show a bullet indicator in the tab label.

=item B<close_current_tab()>

Close the active tab, prompting to save if modified.

=item B<undo()>, B<redo()>

Undo/redo via the GtkSourceView undo manager.

=item B<syntax_check()>

Run C<perl -c> on the current file in a child process.

=item B<format_code()>

Format the current buffer with L<Perl::Tidy>.

=item B<lint_code()>

Run L<Perl::Critic> on the current file and display violations.

=item B<pod_preview()>

Render the file's POD via C<pod2text> in a dialog.

=item B<show_find_bar()>, B<show_find_replace_bar()>

Show the find or find-and-replace toolbar.

=item B<apply_settings()>

Apply font, scheme, tab-width, and toggle changes to all open tabs.

=item B<get_current_file()>

Return the file path of the active tab, or C<undef>.

=item B<get_open_files()>

Return a list of file paths for all open tabs.

=back

=head1 AUTHOR

James

=head1 LICENSE

MIT

=cut
