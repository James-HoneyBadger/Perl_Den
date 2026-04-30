package BadgerOps::App;
# ============================================================================
# BadgerOps::App - Main application controller
# ============================================================================
use strict;
use warnings;
use utf8;
use FindBin qw($RealBin);
use Glib ('TRUE', 'FALSE');
use Gtk3 -init;

# Load GtkSourceView via GObject Introspection (maps to Gtk3::SourceView::* namespace)
Glib::Object::Introspection->setup(
    basename => 'GtkSource',
    version  => '4',
    package  => 'Gtk3::SourceView',
);

our $VERSION = '2.00';

# Load Vte terminal widget via GObject Introspection
eval {
    Glib::Object::Introspection->setup(
        basename => 'Vte',
        version  => '2.91',
        package  => 'Vte',
    );
};
my $HAS_VTE = !$@;

use BadgerOps::Config;
use BadgerOps::Util qw(find_share_dir);
use BadgerOps::GUI::MainWindow;
use Try::Tiny;

sub new {
    my ($class) = @_;
    my $self = bless {
        share_dir => find_share_dir(),
        has_vte   => $HAS_VTE,
    }, $class;
    return $self;
}

sub run {
    my ($self) = @_;

    # Load config and session
    BadgerOps::Config::load();
    BadgerOps::Config::load_session();

    # Apply CSS theme
    $self->_apply_theme();

    # Trap exceptions in signal handlers so we get useful errors
    Glib->install_exception_handler(sub {
        my ($msg) = @_;
        warn "GTK Exception: $msg\n";
        return 1;  # keep running
    });

    # Build and show the main window
    my $main_window = BadgerOps::GUI::MainWindow->new(
        app       => $self,
        share_dir => $self->{share_dir},
        has_vte   => $self->{has_vte},
    );
    $self->{main_window} = $main_window;

    $main_window->show;

    # Periodic session auto-save for crash recovery (every 60s)
    $self->{autosave_timer} = Glib::Timeout->add(60_000, sub {
        eval {
            $main_window->save_state if $main_window;
            BadgerOps::Config::save_session();
        };
        return TRUE;  # keep running
    });

    # Enter GTK main loop
    Gtk3::main();
}

sub apply_theme {
    my ($self) = @_;
    my $theme = BadgerOps::Config::get('theme') // 'vscode-dark-plus';
    my %theme_css = (
        'vscode-light-plus' => 'light.css',
        'vscode-dark-plus'  => 'dark.css',
        'vscode-light'      => 'light.css',
        'vscode-dark'       => 'dark.css',
        'light'             => 'light.css',
        'dark'              => 'dark.css',
        'high-contrast'     => 'high-contrast.css',
    );
    my $css_name = $theme_css{$theme} // "${theme}.css";
    my $css_file = "$self->{share_dir}/themes/${css_name}";

    my $screen = Gtk3::Gdk::Screen::get_default();

    # Remove previous provider if we stored one
    if ($self->{_css_provider}) {
        Gtk3::StyleContext::remove_provider_for_screen($screen, $self->{_css_provider});
        $self->{_css_provider} = undef;
    }

    if (-f $css_file) {
        my $provider = Gtk3::CssProvider->new;
        try {
            open my $fh, '<', $css_file or die "Cannot read $css_file: $!";
            local $/;
            my $css = <$fh>;
            close $fh;
            $provider->load_from_data($css);
        } catch {
            warn "CSS load error: $_\n";
            return;
        };
        Gtk3::StyleContext::add_provider_for_screen(
            $screen,
            $provider,
            800,  # GTK_STYLE_PROVIDER_PRIORITY_USER – overrides system themes
        );
        $self->{_css_provider} = $provider;
    }

    # Request dark/light window decorations
    my $settings = Gtk3::Settings::get_default();
    $settings->set('gtk-application-prefer-dark-theme', $theme =~ /dark/ ? TRUE : FALSE);
}

# Keep old name as alias for backward compat in startup path
sub _apply_theme { goto &apply_theme }

sub share_dir { return $_[0]->{share_dir} }
sub has_vte   { return $_[0]->{has_vte} }

sub quit {
    my ($self) = @_;
    # Stop auto-save timer
    if ($self->{autosave_timer}) {
        Glib::Source->remove($self->{autosave_timer});
        $self->{autosave_timer} = undef;
    }
    if ($self->{main_window}) {
        $self->{main_window}->save_state;
    }
    BadgerOps::Config::save();
    BadgerOps::Config::save_session();
    Gtk3::main_quit();
}

1;

__END__

=head1 NAME

BadgerOps::App - Main application controller for BadgerOps IDE

=head1 SYNOPSIS

    use BadgerOps::App;

    my $app = BadgerOps::App->new;
    $app->run;   # enters GTK main loop

=head1 DESCRIPTION

Initializes the GTK3 toolkit, loads user configuration and session state,
applies the selected CSS theme, and launches the main window.  Acts as the
top-level coordinator between L<BadgerOps::Config>, L<BadgerOps::GUI::MainWindow>,
and the GTK event loop.

=head1 METHODS

=over 4

=item B<new()>

Create a new application instance.  Locates the F<share/> directory and
probes for VTE terminal support.

=item B<run()>

Load configuration, apply the CSS theme, build the main window, and enter
the GTK main loop.  Does not return until the window is closed.

=item B<apply_theme()>

Re-apply the current CSS theme to the GTK screen.  Called on startup and
whenever the user changes the theme in Preferences.

=item B<quit()>

Save configuration and session state, then exit the GTK main loop.

=item B<share_dir()>

Return the resolved path to the F<share/> directory.

=item B<has_vte()>

Return true if the VTE terminal widget is available.

=back

=head1 SEE ALSO

L<BadgerOps::Config>, L<BadgerOps::GUI::MainWindow>

=head1 AUTHOR

James Temple <james@amiga-fan.net>

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2026 Honey Badger Universe

MIT License

=cut
