package HBPerl::GUI::Terminal;
# ============================================================================
# HBPerl::GUI::Terminal - Embedded VTE terminal and output panel
# ============================================================================
use strict;
use warnings;
use utf8;
use Glib ('TRUE', 'FALSE');
use Gtk3;
use HBPerl::Config;
use HBPerl::Runner;

sub new {
    my ($class, %args) = @_;
    my $self = bless {
        main_window => $args{main_window},
        has_vte     => $args{has_vte},
        runner      => undef,
        visible     => 1,
    }, $class;
    $self->_build_ui;
    return $self;
}

sub _build_ui {
    my ($self) = @_;

    # Bottom panel with notebook: Terminal tab + Output tab
    my $notebook = Gtk3::Notebook->new;
    $notebook->set_tab_pos('bottom');
    $self->{widget} = $notebook;
    $self->{notebook} = $notebook;

    # ── Terminal Tab (VTE) ──
    if ($self->{has_vte}) {
        my $terminal = Vte::Terminal->new;
        $terminal->set_scrollback_lines(10000);
        $terminal->set_scroll_on_output(TRUE);
        $terminal->set_scroll_on_keystroke(TRUE);

        # Font
        my $font_str = HBPerl::Config::get('font') // 'monospace 11';
        my $font = Pango::FontDescription::from_string($font_str);
        $terminal->set_font($font);

        # Colors from current theme palette
        my $tc = HBPerl::Config::theme_colors();
        my $bg = Gtk3::Gdk::RGBA->new($tc->{vte_bg_r}, $tc->{vte_bg_g}, $tc->{vte_bg_b}, 1.0);
        my $fg = Gtk3::Gdk::RGBA->new($tc->{vte_fg_r}, $tc->{vte_fg_g}, $tc->{vte_fg_b}, 1.0);

        $terminal->set_color_background($bg);
        $terminal->set_color_foreground($fg);

        # Spawn shell — prefer user's $SHELL, fall back to /bin/bash
        my $shell = $ENV{SHELL} || '/bin/bash';
        eval {
            $terminal->spawn_sync(
                ['default'],     # pty_flags (as array for GI)
                undef,           # working_directory
                [$shell],        # argv
                undef,           # envv
                ['default'],     # spawn_flags
                undef,           # child_setup
                undef,           # child_setup_data (not needed)
            );
        };
        if ($@) {
            # Try alternative spawn
            eval {
                $terminal->spawn_async(
                    'default', undef, [$shell], undef,
                    'default', undef, -1, undef, undef,
                );
            };
        }

        $terminal->signal_connect('child-exited' => sub {
            # Respawn on exit
            eval {
                $terminal->spawn_sync(
                    ['default'], undef, [$shell], undef,
                    ['default'], undef, undef,
                );
            };
        });

        my $term_sw = Gtk3::ScrolledWindow->new(undef, undef);
        $term_sw->set_policy('automatic', 'always');
        $term_sw->add($terminal);

        my $term_label = Gtk3::Label->new('⌨ Terminal');
        $notebook->append_page($term_sw, $term_label);
        $self->{terminal_widget} = $terminal;
    }

    # ── Script Output Tab ──
    my $output_buffer = Gtk3::TextBuffer->new;
    $self->{output_buffer} = $output_buffer;

    # Create tags for colored output (theme-aware)
    my $tc = HBPerl::Config::theme_colors();
    $output_buffer->create_tag('normal',  foreground => $tc->{fg});
    $output_buffer->create_tag('error',   foreground => $tc->{error},   weight => 700);
    $output_buffer->create_tag('success', foreground => $tc->{success});
    $output_buffer->create_tag('warning', foreground => $tc->{warning});
    $output_buffer->create_tag('info',    foreground => $tc->{info});
    $output_buffer->create_tag('header',  foreground => $tc->{accent},  weight => 700, scale => 1.1);
    $output_buffer->create_tag('dim',     foreground => $tc->{dim});

    my $output_view = Gtk3::TextView->new_with_buffer($output_buffer);
    $output_view->set_editable(FALSE);
    $output_view->set_cursor_visible(FALSE);
    $output_view->set_wrap_mode('word-char');
    $output_view->get_style_context->add_class('output-panel');

    my $cfg_font = HBPerl::Config::get('font') // 'monospace 11';
    my $font = Pango::FontDescription::from_string($cfg_font);
    my $size = $font->get_size;
    $font->set_size($size * 10 / 11) if $size > 0;  # slightly smaller for output
    $output_view->override_font($font);

    my $output_sw = Gtk3::ScrolledWindow->new(undef, undef);
    $output_sw->set_policy('automatic', 'always');
    $output_sw->add($output_view);

    # Toolbar above output
    my $output_box = Gtk3::Box->new('vertical', 0);

    my $output_toolbar = Gtk3::Box->new('horizontal', 4);
    $output_toolbar->set_margin_start(4);
    $output_toolbar->set_margin_end(4);
    $output_toolbar->set_margin_top(2);
    $output_toolbar->set_margin_bottom(2);

    my $clear_btn = Gtk3::Button->new_with_label('Clear');
    $clear_btn->set_relief('none');
    $clear_btn->signal_connect(clicked => sub {
        $output_buffer->set_text('');
    });
    $output_toolbar->pack_end($clear_btn, FALSE, FALSE, 0);

    my $stop_btn = Gtk3::Button->new_with_label('Stop');
    $stop_btn->set_relief('none');
    $stop_btn->signal_connect(clicked => sub { $self->stop_running });
    $output_toolbar->pack_end($stop_btn, FALSE, FALSE, 0);

    $output_box->pack_start($output_toolbar, FALSE, FALSE, 0);
    $output_box->pack_start($output_sw, TRUE, TRUE, 0);

    my $output_label = Gtk3::Label->new('📋 Output');
    $notebook->append_page($output_box, $output_label);

    $self->{output_view} = $output_view;
}

sub run_command {
    my ($self, $command) = @_;

    if ($self->{has_vte} && $self->{terminal_widget}) {
        # Switch to terminal tab and type the command
        $self->{notebook}->set_current_page(0);
        $self->{terminal_widget}->feed_child("$command\n", -1);
    } else {
        # Fall back to Runner with output panel
        $self->{notebook}->set_current_page($self->{has_vte} ? 1 : 0);
        $self->_run_in_output($command);
    }
}

sub run_in_output {
    my ($self, $command) = @_;
    # Always use the output panel
    $self->{notebook}->set_current_page($self->{has_vte} ? 1 : 0);
    $self->_run_in_output($command);
}

sub _run_in_output {
    my ($self, $command) = @_;

    $self->append_output("▶ $command\n", 'header');

    $self->{runner}->kill_running if $self->{runner} && $self->{runner}->is_running;

    $self->{runner} = HBPerl::Runner->new(
        on_stdout => sub {
            my ($text) = @_;
            $self->append_output($text, 'normal');
        },
        on_stderr => sub {
            my ($text) = @_;
            $self->append_output($text, 'error');
        },
        on_exit => sub {
            my ($code) = @_;
            my $tag = $code == 0 ? 'success' : 'error';
            $self->append_output(
                "\n⏹ Process exited with code $code\n\n",
                $tag,
            );
            $self->{main_window}->set_status(
                $code == 0 ? "Script finished successfully" : "Script exited with code $code"
            );
        },
    );

    $self->{runner}->run_script(command => $command);
}

sub append_output {
    my ($self, $text, $tag_name) = @_;
    $tag_name //= 'normal';
    my $buffer = $self->{output_buffer};
    my $end = $buffer->get_end_iter;

    if ($tag_name && $buffer->get_tag_table->lookup($tag_name)) {
        $buffer->insert_with_tags_by_name($end, $text, $tag_name);
    } else {
        $buffer->insert($end, $text);
    }

    # Cap output buffer at 50000 lines to prevent unbounded memory growth
    my $max_lines = 50000;
    my $line_count = $buffer->get_line_count;
    if ($line_count > $max_lines) {
        my $trim_start = $buffer->get_start_iter;
        my $trim_end   = $buffer->get_iter_at_line($line_count - $max_lines);
        $buffer->delete($trim_start, $trim_end);
    }

    # Auto-scroll to bottom
    my $mark = $buffer->create_mark('end', $buffer->get_end_iter, FALSE);
    $self->{output_view}->scroll_to_mark($mark, 0.0, TRUE, 0.0, 1.0);
    $buffer->delete_mark($mark);
}

sub stop_running {
    my ($self) = @_;
    if ($self->{runner} && $self->{runner}->is_running) {
        $self->{runner}->kill_running;
        $self->{main_window}->set_status("Script stopped");
    }
}

sub apply_settings {
    my ($self) = @_;
    my $font_str  = HBPerl::Config::get('font') // 'monospace 11';
    my $font_desc = Pango::FontDescription::from_string($font_str);
    my $tc        = HBPerl::Config::theme_colors();

    # Update VTE terminal font + colours
    if ($self->{has_vte} && $self->{terminal_widget}) {
        $self->{terminal_widget}->set_font($font_desc);
        my $bg = Gtk3::Gdk::RGBA->new($tc->{vte_bg_r}, $tc->{vte_bg_g}, $tc->{vte_bg_b}, 1.0);
        my $fg = Gtk3::Gdk::RGBA->new($tc->{vte_fg_r}, $tc->{vte_fg_g}, $tc->{vte_fg_b}, 1.0);
        $self->{terminal_widget}->set_color_background($bg);
        $self->{terminal_widget}->set_color_foreground($fg);
    }

    # Update output panel font (keep it one size smaller)
    if ($self->{output_view}) {
        my $out_font = Pango::FontDescription::from_string($font_str);
        my $size = $out_font->get_size;
        $out_font->set_size($size * 10 / 11) if $size > 0;
        $self->{output_view}->override_font($out_font);
    }

    # Refresh output tag colours to match current theme
    if ($self->{output_buffer}) {
        my $table = $self->{output_buffer}->get_tag_table;
        my %tag_map = (
            normal  => $tc->{fg},
            error   => $tc->{error},
            success => $tc->{success},
            warning => $tc->{warning},
            info    => $tc->{info},
            header  => $tc->{accent},
            dim     => $tc->{dim},
        );
        while (my ($name, $color) = each %tag_map) {
            my $tag = $table->lookup($name);
            $tag->set(foreground => $color) if $tag;
        }
    }
}

sub toggle_visibility {
    my ($self) = @_;
    if ($self->{visible}) {
        $self->{widget}->hide;
        $self->{visible} = 0;
    } else {
        $self->{widget}->show;
        $self->{visible} = 1;
    }
}

sub widget { return $_[0]->{widget} }

1;

__END__

=encoding utf8

=head1 NAME

HBPerl::GUI::Terminal - Embedded VTE terminal and script output panel

=head1 DESCRIPTION

A two-tab panel at the bottom of the IDE:

=over 4

=item B<Terminal tab> — a VTE pseudo-terminal running the user's shell
(falls back to a simple output view if VTE is unavailable).

=item B<Output tab> — a read-only text view for script stdout/stderr,
colour-coded by stream.  Output is capped at 50,000 lines.

=back

=head1 METHODS

=over 4

=item B<new(main_window =E<gt> $mw, has_vte =E<gt> $bool)>

Build the terminal notebook.

=item B<run_command($cmd)>

Send a command to the VTE terminal.

=item B<run_in_output(command =E<gt> $cmd)>

Run a command with stdout/stderr captured into the Output tab.

=item B<append_output($text, $tag)>

Append text to the Output tab.  C<$tag> may be C<'stdout'>, C<'stderr'>,
C<'info'>, C<'success'>, or C<'error'>.

=item B<stop_running()>

Kill any command running in the Output tab.

=item B<apply_settings()>

Refresh font and colours for both tabs.

=item B<toggle_visibility()>

Show or hide the terminal panel.

=item B<widget()>

Return the top-level GTK widget.

=back

=head1 AUTHOR

James

=head1 LICENSE

MIT

=cut
