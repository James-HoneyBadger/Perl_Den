use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME         => 'Perl Den',
    VERSION_FROM => 'lib/PerlDen/App.pm',
    ABSTRACT     => 'Perl Den IDE - Linux Sysadmin Toolkit & Perl Development Environment v2',
    AUTHOR       => 'James Temple <james@amiga-fan.net>',
    LICENSE      => 'mit',
    MIN_PERL_VERSION => '5.028',
    EXE_FILES    => [
        'bin/perlden-ide',
        'bin/perlden-cli',
        'bin/perlden-tui',
    ],
    PREREQ_PM    => {
        'Glib'                        => '1.329',
        'Glib::Object::Introspection' => '0.049',
        'Gtk3'                        => '0.038',
        'Proc::ProcessTable'          => '0.634',
        'Net::DNS'                    => '1.36',
        'IO::Socket::SSL'             => '2.085',
        'Text::Diff'                  => '1.45',
        'YAML::XS'                    => '0.88',
        'JSON::MaybeXS'               => '1.004',
        'File::HomeDir'               => '1.006',
        'Try::Tiny'                   => '0.31',
        'Perl::Tidy'                  => '20230309',
        'Perl::Critic'                => '1.152',
    },
    TEST_REQUIRES => {
        'Test::More'       => '1.302',
        'Test::Exception'  => '0.43',
        'Test::MockModule' => '0.177',
        'Test::Pod'        => '1.52',
        'Devel::Cover'     => '1.36',
    },
    META_MERGE => {
        'meta-spec' => { version => 2 },
        resources   => {
            homepage   => 'https://github.com/James-HoneyBadger/Perl Den',
            repository => {
                type => 'git',
                url  => 'https://github.com/James-HoneyBadger/PerlDen.git',
            },
        },
    },
    test => { TESTS => 't/*.t t/unit/*.t t/integration/*.t' },
);

# ── Coverage target: `make cover` ──
sub MY::postamble {
    return <<'MAKE';
cover :: pure_all
	$(NOECHO) cover -delete
	HARNESS_PERL_SWITCHES=-MDevel::Cover $(MAKE) test
	cover -report html -report text
	$(NOECHO) $(ECHO) "Coverage report: cover_db/coverage.html"

MAKE
}
