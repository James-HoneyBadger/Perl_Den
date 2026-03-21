package HBPerl::GUI::ScriptBrowser;
# ============================================================================
# HBPerl::GUI::ScriptBrowser - Tree view of sysadmin script categories
# ============================================================================
use strict;
use warnings;
use utf8;
use Glib ('TRUE', 'FALSE');
use Gtk3;
use File::Basename qw(basename);
use FindBin qw($RealBin);
use HBPerl::ScriptRegistry qw(script_categories);
use HBPerl::Config;
use HBPerl::Util qw(shell_quote);

sub new {
    my ($class, %args) = @_;
    my $self = bless {
        main_window => $args{main_window},
        share_dir   => $args{share_dir},
        mode        => 'scripts',   # 'scripts' or 'files'
    }, $class;
    $self->_build_ui;
    return $self;
}

sub _build_ui {
    my ($self) = @_;

    my $vbox = Gtk3::Box->new('vertical', 0);

    # Mode toggle bar: Scripts | Files
    my $toggle_bar = Gtk3::Box->new('horizontal', 0);
    $toggle_bar->set_margin_start(8);
    $toggle_bar->set_margin_end(8);
    $toggle_bar->set_margin_top(6);
    $toggle_bar->set_margin_bottom(2);

    my $scripts_btn = Gtk3::ToggleButton->new_with_label('Scripts');
    $scripts_btn->set_active(TRUE);
    my $files_btn = Gtk3::ToggleButton->new_with_label('Files');
    $files_btn->set_active(FALSE);

    $scripts_btn->signal_connect('toggled' => sub {
        return if $self->{_toggling};
        $self->{_toggling} = 1;
        $files_btn->set_active(!$scripts_btn->get_active);
        $self->_switch_mode('scripts') if $scripts_btn->get_active;
        $self->{_toggling} = 0;
    });
    $files_btn->signal_connect('toggled' => sub {
        return if $self->{_toggling};
        $self->{_toggling} = 1;
        $scripts_btn->set_active(!$files_btn->get_active);
        $self->_switch_mode('files') if $files_btn->get_active;
        $self->{_toggling} = 0;
    });

    $toggle_bar->pack_start($scripts_btn, TRUE, TRUE, 0);
    $toggle_bar->pack_start($files_btn, TRUE, TRUE, 0);
    $vbox->pack_start($toggle_bar, FALSE, FALSE, 0);
    $self->{scripts_btn} = $scripts_btn;
    $self->{files_btn}   = $files_btn;

    # Stack to hold both views
    my $stack = Gtk3::Stack->new;
    $stack->set_transition_type('crossfade');
    $self->{stack} = $stack;

    # ── Scripts view ──
    my $scripts_box = Gtk3::Box->new('vertical', 0);

    # Header
    my $header = Gtk3::Label->new(undef);
    $header->set_markup('<span font="Adwaita Sans Bold 11" letter_spacing="2048" foreground="#3794ff">SCRIPT LIBRARY</span>');
    $header->get_style_context->add_class('sidebar-header');
    $header->set_halign('start');
    $header->set_margin_start(12);
    $header->set_margin_top(10);
    $header->set_margin_bottom(6);
    $scripts_box->pack_start($header, FALSE, FALSE, 0);

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
    eval { $tree->get_accessible->set_name('Script library browser') };
    # Fallback: set_name may not exist on all ATK/Accessible backends

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
    $scripts_box->pack_start($sw, TRUE, TRUE, 0);

    $self->{tree} = $tree;

    $stack->add_named($scripts_box, 'scripts');

    # ── Files view ──
    my $files_box = $self->_build_file_browser;
    $stack->add_named($files_box, 'files');

    $stack->set_visible_child_name('scripts');
    $vbox->pack_start($stack, TRUE, TRUE, 0);

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
        $self->{main_window}->terminal->run_command("perl " . shell_quote($filepath));
    });
    $menu->append($run_item);

    my $run_root = Gtk3::MenuItem->new_with_label('Run as Root');
    $run_root->signal_connect(activate => sub {
        my $priv_tool = HBPerl::Config::privilege_tool();
        $self->{main_window}->terminal->run_command("$priv_tool perl " . shell_quote($filepath));
    });
    $menu->append($run_root);

    $menu->show_all;
    $menu->popup_at_pointer($event);
}

sub _switch_mode {
    my ($self, $mode) = @_;
    $self->{mode} = $mode;
    $self->{stack}->set_visible_child_name($mode);
    if ($mode eq 'files' && !$self->{_files_loaded}) {
        $self->_populate_file_tree("$RealBin/..");
        $self->{_files_loaded} = 1;
    }
}

sub _build_file_browser {
    my ($self) = @_;
    my $box = Gtk3::Box->new('vertical', 0);

    my $fheader = Gtk3::Label->new(undef);
    $fheader->set_markup('<span font="Adwaita Sans Bold 11" letter_spacing="2048" foreground="#3794ff">FILE EXPLORER</span>');
    $fheader->set_halign('start');
    $fheader->set_margin_start(12);
    $fheader->set_margin_top(10);
    $fheader->set_margin_bottom(6);
    $box->pack_start($fheader, FALSE, FALSE, 0);

    # TreeStore: icon, name, full-path
    my $fstore = Gtk3::TreeStore->new('Glib::String', 'Glib::String', 'Glib::String');
    $self->{file_store} = $fstore;

    my $ftree = Gtk3::TreeView->new($fstore);
    $ftree->set_headers_visible(FALSE);
    $ftree->set_enable_tree_lines(TRUE);
    $ftree->get_style_context->add_class('sidebar-tree');
    eval { $ftree->get_accessible->set_name('Project file browser') };

    my $fcol = Gtk3::TreeViewColumn->new;
    $fcol->set_spacing(4);
    my $ficon = Gtk3::CellRendererPixbuf->new;
    $ficon->set_property('xpad', 4);
    my $fname = Gtk3::CellRendererText->new;
    $fname->set_property('ellipsize', 'end');
    $fcol->pack_start($ficon, FALSE);
    $fcol->pack_start($fname, TRUE);
    $fcol->add_attribute($ficon, 'icon-name', 0);
    $fcol->add_attribute($fname, 'text', 1);
    $ftree->append_column($fcol);

    # Lazy-load: expand populates children
    $ftree->signal_connect('row-expanded' => sub {
        my ($tv, $iter, $path) = @_;
        my $full_path = $fstore->get($iter, 2);
        # Check if placeholder child exists
        my $child = $fstore->iter_children($iter);
        if ($child && $fstore->get($child, 1) eq '...') {
            $fstore->remove($child);
            $self->_populate_dir($fstore, $iter, $full_path);
        }
    });

    # Double-click opens file
    $ftree->signal_connect('row-activated' => sub {
        my ($tv, $path, $column) = @_;
        my $iter = $fstore->get_iter($path);
        my $full = $fstore->get($iter, 2);
        if (-f $full) {
            $self->{main_window}->open_file_in_editor($full);
        } elsif (-d $full) {
            if ($tv->row_expanded($path)) {
                $tv->collapse_row($path);
            } else {
                $tv->expand_row($path, FALSE);
            }
        }
    });

    # Right-click context menu for files
    $ftree->signal_connect('button-press-event' => sub {
        my ($tv, $event) = @_;
        if ($event->button == 3) {
            $self->_show_file_context_menu($tv, $event);
            return TRUE;
        }
        return FALSE;
    });

    my $fsw = Gtk3::ScrolledWindow->new(undef, undef);
    $fsw->set_policy('automatic', 'automatic');
    $fsw->add($ftree);
    $box->pack_start($fsw, TRUE, TRUE, 0);

    $self->{file_tree} = $ftree;
    return $box;
}

sub _populate_file_tree {
    my ($self, $root_dir) = @_;
    my $store = $self->{file_store};
    $store->clear;
    $self->_populate_dir($store, undef, $root_dir);
}

sub _populate_dir {
    my ($self, $store, $parent, $dir) = @_;
    opendir(my $dh, $dir) or return;
    my @entries = sort { lc($a) cmp lc($b) } grep { $_ ne '.' && $_ ne '..' } readdir $dh;
    closedir $dh;

    # Directories first, then files
    my @dirs  = grep { -d "$dir/$_" } @entries;
    my @files = grep { -f "$dir/$_" } @entries;

    for my $d (@dirs) {
        next if $d =~ /^\./;  # skip hidden dirs
        my $full = "$dir/$d";
        my $iter = $store->append($parent);
        $store->set($iter, 0, 'folder-symbolic', 1, $d, 2, $full);
        # Add placeholder child for lazy loading
        my $placeholder = $store->append($iter);
        $store->set($placeholder, 0, '', 1, '...', 2, '');
    }

    for my $f (@files) {
        next if $f =~ /^\./;  # skip hidden files
        my $full = "$dir/$f";
        my $icon = $f =~ /\.pl$/i ? 'text-x-script-symbolic'
                 : $f =~ /\.pm$/i ? 'text-x-generic-symbolic'
                 : $f =~ /\.t$/i  ? 'dialog-question-symbolic'
                 : 'text-x-generic-symbolic';
        my $iter = $store->append($parent);
        $store->set($iter, 0, $icon, 1, $f, 2, $full);
    }
}

sub _show_file_context_menu {
    my ($self, $tree, $event) = @_;
    my ($path) = $tree->get_path_at_pos($event->x, $event->y);
    return unless $path;

    my $iter = $self->{file_store}->get_iter($path);
    my $filepath = $self->{file_store}->get($iter, 2);
    return unless $filepath;

    my $menu = Gtk3::Menu->new;

    if (-f $filepath) {
        my $open_item = Gtk3::MenuItem->new_with_label('Open in Editor');
        $open_item->signal_connect(activate => sub {
            $self->{main_window}->open_file_in_editor($filepath);
        });
        $menu->append($open_item);

        if ($filepath =~ /\.pl$/i) {
            my $run_item = Gtk3::MenuItem->new_with_label('Run Script');
            $run_item->signal_connect(activate => sub {
                $self->{main_window}->terminal->run_command("perl " . shell_quote($filepath));
            });
            $menu->append($run_item);
        }
    }

    if (-d $filepath) {
        my $refresh = Gtk3::MenuItem->new_with_label('Refresh');
        $refresh->signal_connect(activate => sub {
            $self->_populate_file_tree($filepath);
        });
        $menu->append($refresh);
    }

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

James Temple <james@amiga-fan.net>

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2026 Honey Badger Universe

MIT License

=cut
