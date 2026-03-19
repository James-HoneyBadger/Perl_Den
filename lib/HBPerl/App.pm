package HBPerl::App;
# ============================================================================
# HBPerl::App - Main application controller
# ============================================================================
use strict;
use warnings;
use utf8;
use FindBin qw($RealBin);
use Glib ('TRUE', 'FALSE');
use Gtk3 -init;
use Gtk3::SourceView;

our $VERSION = '1.00';

# Load Vte terminal widget via GObject Introspection
eval {
    Glib::Object::Introspection->setup(
        basename => 'Vte',
        version  => '2.91',
        package  => 'Vte',
    );
};
my $HAS_VTE = !$@;

use HBPerl::Config;
use HBPerl::GUI::MainWindow;

sub new {
    my ($class) = @_;
    my $self = bless {
        share_dir => _find_share_dir(),
        has_vte   => $HAS_VTE,
    }, $class;
    return $self;
}

sub run {
    my ($self) = @_;

    # Load config and session
    HBPerl::Config::load();
    HBPerl::Config::load_session();

    # Apply CSS theme
    $self->_apply_theme();

    # Trap exceptions in signal handlers so we get useful errors
    Glib->install_exception_handler(sub {
        my ($msg) = @_;
        warn "GTK Exception: $msg\n";
        return 1;  # keep running
    });

    # Build and show the main window
    my $main_window = HBPerl::GUI::MainWindow->new(
        app       => $self,
        share_dir => $self->{share_dir},
        has_vte   => $self->{has_vte},
    );
    $self->{main_window} = $main_window;

    $main_window->show;

    # Enter GTK main loop
    Gtk3::main();
}

sub apply_theme {
    my ($self) = @_;
    my $theme = HBPerl::Config::get('theme') // 'vscode-dark-plus';
    my %theme_css = (
        'vscode-light-plus' => 'light.css',
        'vscode-dark-plus'  => 'dark.css',
        'vscode-light'      => 'light.css',
        'vscode-dark'       => 'dark.css',
        'light'             => 'light.css',
        'dark'              => 'dark.css',
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
        eval {
            open my $fh, '<', $css_file or die "Cannot read $css_file: $!";
            local $/;
            my $css = <$fh>;
            close $fh;
            $provider->load_from_data($css);
        };
        if ($@) {
            warn "CSS load error: $@\n";
            return;
        }
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

sub _find_share_dir {
    my @candidates = (
        "$RealBin/../share",
        "$RealBin/share",
        "/usr/share/hb_perl",
        "$ENV{HOME}/.local/share/hb_perl",
    );
    for my $d (@candidates) {
        return $d if -d $d;
    }
    return "$RealBin/../share";
}

sub share_dir { return $_[0]->{share_dir} }
sub has_vte   { return $_[0]->{has_vte} }

sub quit {
    my ($self) = @_;
    if ($self->{main_window}) {
        $self->{main_window}->save_state;
    }
    HBPerl::Config::save();
    HBPerl::Config::save_session();
    Gtk3::main_quit();
}

1;

__END__

=head1 NAME

HBPerl::App - Main application controller for HB Perl IDE

=head1 SYNOPSIS

    use HBPerl::App;

    my $app = HBPerl::App->new;
    $app->run;   # enters GTK main loop

=head1 DESCRIPTION

Initializes the GTK3 toolkit, loads user configuration and session state,
applies the selected CSS theme, and launches the main window.  Acts as the
top-level coordinator between L<HBPerl::Config>, L<HBPerl::GUI::MainWindow>,
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

L<HBPerl::Config>, L<HBPerl::GUI::MainWindow>

=head1 AUTHOR

James

=head1 LICENSE

MIT

=cut
