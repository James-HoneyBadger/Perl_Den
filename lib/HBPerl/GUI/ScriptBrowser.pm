package HBPerl::GUI::ScriptBrowser;
# ============================================================================
# HBPerl::GUI::ScriptBrowser - Tree view of sysadmin script categories
# ============================================================================
use strict;
use warnings;
use utf8;
use Glib ('TRUE', 'FALSE');
use Gtk3;
use FindBin qw($RealBin);
use HBPerl::ScriptRegistry qw(script_categories);

sub new {
    my ($class, %args) = @_;
    my $self = bless {
        main_window => $args{main_window},
        share_dir   => $args{share_dir},
    }, $class;
    $self->_build_ui;
    return $self;
}

sub _build_ui {
    my ($self) = @_;

    my $vbox = Gtk3::Box->new('vertical', 0);

    # Header
    my $header = Gtk3::Label->new(undef);
    $header->set_markup('<span font="Adwaita Sans Bold 11" letter_spacing="2048" foreground="#3794ff">SCRIPT LIBRARY</span>');
    $header->get_style_context->add_class('sidebar-header');
    $header->set_halign('start');
    $header->set_margin_start(12);
    $header->set_margin_top(10);
    $header->set_margin_bottom(6);
    $vbox->pack_start($header, FALSE, FALSE, 0);

    # TreeStore: icon, name, filepath, description
    my $store = Gtk3::TreeStore->new(
        'Glib::String', 'Glib::String', 'Glib::String', 'Glib::String'
    );
    $self->{store} = $store;

    # Populate categories
    $self->_populate_tree;

    # TreeView
    my $tree = Gtk3::TreeView->new($store);
    $tree->set_headers_visible(FALSE);
    $tree->set_enable_tree_lines(FALSE);
    $tree->set_tooltip_column(3);
    $tree->set_level_indentation(4);
    $tree->get_style_context->add_class('sidebar-tree');

    # Column: icon + name with Pango markup via cell data func
    my $col = Gtk3::TreeViewColumn->new;
    $col->set_spacing(6);

    my $icon_r = Gtk3::CellRendererPixbuf->new;
    $icon_r->set_property('xpad', 4);

    my $text_r = Gtk3::CellRendererText->new;
    $text_r->set_property('ellipsize', 'end');

    $col->pack_start($icon_r, FALSE);
    $col->pack_start($text_r, TRUE);
    $col->add_attribute($icon_r, 'icon-name', 0);

    # Use a cell data function to render categories and scripts differently
    $col->set_cell_data_func($text_r, sub {
        my ($column, $renderer, $model, $iter) = @_;
        my $filepath = $model->get($iter, 2);
        my $name     = $model->get($iter, 1);
        my $safe     = Glib::Markup::escape_text($name);
        if (!$filepath || $filepath eq '') {
            # Category header row — bold, uppercase, accent color, larger
            $renderer->set_property('markup',
                "<span font='Adwaita Sans Bold 10' letter_spacing='1024' foreground='#3794ff'>$safe</span>");
            $renderer->set_property('ypad', 6);
            $renderer->set_property('xpad', 2);
        } else {
            # Script item row — clean proportional font
            $renderer->set_property('markup',
                "<span font='Adwaita Sans 10.5'>$safe</span>");
            $renderer->set_property('ypad', 4);
            $renderer->set_property('xpad', 14);
        }
    }, undef);

    $tree->append_column($col);

    # Double-click opens file in editor
    $tree->signal_connect('row-activated' => sub {
        my ($tv, $path, $column) = @_;
        my $iter = $store->get_iter($path);
        my $filepath = $store->get($iter, 2);
        if ($filepath && -f $filepath) {
            $self->{main_window}->open_file_in_editor($filepath);
        } else {
            # Category row — toggle expand/collapse
            if ($tv->row_expanded($path)) {
                $tv->collapse_row($path);
            } else {
                $tv->expand_row($path, FALSE);
            }
        }
    });

    # Right-click context menu
    $tree->signal_connect('button-press-event' => sub {
        my ($tv, $event) = @_;
        if ($event->button == 3) {
            $self->_show_context_menu($tv, $event);
            return TRUE;
        }
        return FALSE;
    });

    my $sw = Gtk3::ScrolledWindow->new(undef, undef);
    $sw->set_policy('automatic', 'automatic');
    $sw->add($tree);
    $vbox->pack_start($sw, TRUE, TRUE, 0);

    $self->{tree} = $tree;
    $self->{widget} = $vbox;
}

sub _populate_tree {
    my ($self) = @_;
    my $store = $self->{store};
    my $scripts_dir = "$RealBin/../scripts";

    for my $cat (script_categories()) {
        my $parent = $store->append(undef);
        $store->set($parent,
            0, $cat->{icon} // 'folder-symbolic',
            1, uc($cat->{name}),
            2, '',
            3, '',
        );
        for my $item (@{$cat->{items}}) {
            my ($name, $script, $desc) = @$item;
            my $filepath = "$scripts_dir/$script";
            my $child = $store->append($parent);
            $store->set($child,
                0, 'text-x-script-symbolic',
                1, $name,
                2, $filepath,
                3, $desc,
            );
        }
    }
}

sub _show_context_menu {
    my ($self, $tree, $event) = @_;
    my ($path) = $tree->get_path_at_pos($event->x, $event->y);
    return unless $path;

    my $iter = $self->{store}->get_iter($path);
    my $filepath = $self->{store}->get($iter, 2);
    return unless $filepath && -f $filepath;

    my $menu = Gtk3::Menu->new;

    my $open_item = Gtk3::MenuItem->new_with_label('Open in Editor');
    $open_item->signal_connect(activate => sub {
        $self->{main_window}->open_file_in_editor($filepath);
    });
    $menu->append($open_item);

    my $run_item = Gtk3::MenuItem->new_with_label('Run Script');
    $run_item->signal_connect(activate => sub {
        $self->{main_window}->terminal->run_command("perl '$filepath'");
    });
    $menu->append($run_item);

    my $run_root = Gtk3::MenuItem->new_with_label('Run as Root');
    $run_root->signal_connect(activate => sub {
        $self->{main_window}->terminal->run_command("pkexec perl '$filepath'");
    });
    $menu->append($run_root);

    $menu->show_all;
    $menu->popup_at_pointer($event);
}

sub widget { return $_[0]->{widget} }

1;

__END__

=head1 NAME

HBPerl::GUI::ScriptBrowser - Sidebar tree view of sysadmin scripts

=head1 DESCRIPTION

Displays the 15 toolkit scripts in a categorised tree view populated
from L<HBPerl::ScriptRegistry>.  Double-click opens a script in the
editor; right-click shows a context menu with Open, Run, and Run as
Root options.

=head1 METHODS

=over 4

=item B<new(main_window =E<gt> $mw, share_dir =E<gt> $path)>

Build the sidebar tree.

=item B<widget()>

Return the top-level GTK widget.

=back

=head1 AUTHOR

James

=head1 LICENSE

MIT

=cut
