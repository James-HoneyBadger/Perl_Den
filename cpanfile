# HB Perl IDE - Dependencies
# Install with: cpanm --installdeps .

# ── GUI Toolkit ──
requires 'Glib',                        '1.329';
requires 'Glib::Object::Introspection', '0.049';
requires 'Gtk3',                        '0.038';
requires 'Gtk3::SourceView',            '0.12';

# ── Sysadmin Modules ──
requires 'Proc::ProcessTable',          '0.634';
requires 'Net::DNS',                    '1.36';
requires 'IO::Socket::SSL',             '2.085';
requires 'Net::SSLeay',                 '1.92';
requires 'Archive::Tar';                            # core
requires 'IO::Compress::Gzip';                      # core
requires 'Digest::SHA';                             # core
requires 'Digest::MD5';                             # core
requires 'Text::Diff',                  '1.45';
requires 'YAML::XS',                   '0.88';
requires 'JSON::MaybeXS',              '1.004';
requires 'File::HomeDir',              '1.006';

# ── Developer Tools ──
requires 'Perl::Tidy',                 '20230309';
requires 'Perl::Critic',               '1.152';

# ── Testing ──
on 'test' => sub {
    requires 'Test::More',             '1.302';
    requires 'Test::Exception',        '0.43';
    requires 'Test::MockModule',       '0.177';
    requires 'Test::Pod',              '1.52';
    requires 'File::Temp';                          # core
};
