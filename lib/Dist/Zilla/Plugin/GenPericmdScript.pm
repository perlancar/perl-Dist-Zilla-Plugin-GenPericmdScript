package Dist::Zilla::Plugin::GenPericmdScript;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;

use Moose;
with (
    'Dist::Zilla::Role::FileFinderUser' => {
        default_finders => [':InstallModules'],
    },
    'Dist::Zilla::Role::FileGatherer',
    'Dist::Zilla::Role::FileMunger',
    'Dist::Zilla::Role::PERLANCAR::WriteModules',
);

use namespace::autoclean;

use App::GenPericmdScript qw(gen_perinci_cmdline_script);
use Module::Load;

has build_load_modules => (is=>'rw');

has url => (is=>'rw', required=>1);
has subcommands => (is=>'rw');
has subcommands_from_package_functions => (is=>'rw');
has include_package_functions_match => (is=>'rw');
has exclude_package_functions_match => (is=>'rw');
has name => (is=>'rw');
has cmdline => (is=>'rw');
has prefer_lite => (is=>'rw');
has enable_log => (is=>'rw');
has default_log_level => (is=>'rw');
has extra_urls_for_version => (is=>'rw');
has config_filename => (is=>'rw');
has ssl_verify_hostname => (is=>'rw');
has load_modules => (is=>'rw');
has snippet_before_instantiate_cmdline => (is=>'rw');
has skip_format => (is=>'rw');

sub gather_files {
    # we actually don't generate scripts in this phase but in the later stage
    # (FileMunger) to be able to get more built version of modules. we become
    # FileGatherer plugin too to get add_file().
}

# XXX extract list_own_modules, is_own_module to its own role/dist
sub is_own_module {
    use experimental 'smartmatch';

    my ($self, $mod) = @_;

    state $own_modules = do {
        my @list;
        for my $file (@{ $self->found_files }) {
            my $name = $file->name;
            next unless $name =~ s!^lib[/\\]!!;
            $name =~ s![/\\]!::!g;
            $name =~ s/\.(pm|pod)$//;
            push @list, $name;
        }
        \@list;
    };

    $mod ~~ @$own_modules ? 1:0;
}

sub munge_files {
    my ($self, $arg) = @_;

    # i do it this way (unshift @INC, "lib" + require "Foo/Bar.pm" instead of
    # unshift @INC, "." + require "lib/Foo/Bar.pm") in my all other Dist::Zilla
    # and Pod::Weaver plugin, so they can work together (require "Foo/Bar.pm"
    # and require "lib/Foo/Bar.pm" would cause Perl to load the same file twice
    # and generate redefine warnings).
    local @INC = ("lib", @INC);

    require Dist::Zilla::File::InMemory;

    my $scriptname = $self->name;
    if (!$scriptname) {
        $scriptname = $self->url;
        $scriptname =~ s!.+/!!;
        $scriptname =~ s/[^A-Za-z0-9]+/-/g;
        $scriptname =~ s/^-//;
        $scriptname = "script" if length($scriptname) == 0;
    }

    my $subcommands;
    if ($self->subcommands) {
        $subcommands = [split /\s*,\s*/, $self->subcommands];
    }

    my $res;
    {
        # if we use Perinci::CmdLine::Inline, the script might include module(s)
        # from the current dist and we need the built version, not the source
        # version
        $self->write_modules_to_dir;
        my $mods_tempdir = $self->written_modules_dir;

        local @INC = ($mods_tempdir, @INC);

        if ($self->build_load_modules) {
            for (split(/\s*,\s*/, $self->build_load_modules)) {
                load $_;
            }
        }

        $res = gen_perinci_cmdline_script(
            url => $self->url,
            script_name => $scriptname,
            script_version => $self->zilla->version,
            interpreter_path => 'perl',
            load_module => $self->load_modules ? [split(/\s*,\s*/, $self->load_modules)] : undef,
            log => $self->enable_log,
            ($self->extra_urls_for_version ? (extra_urls_for_version => [split(/\s*,\s*/, $self->extra_urls_for_version)]) : ()),
            default_log_level => $self->default_log_level,
            cmdline => $self->cmdline,
            prefer_lite => $self->prefer_lite,
            ssl_verify_hostname => $self->ssl_verify_hostname,
            snippet_before_instantiate_cmdline => $self->snippet_before_instantiate_cmdline,
            config_filename => $self->config_filename,
            (subcommand => $subcommands) x !!$subcommands,
            subcommands_from_package_functions => $self->subcommands_from_package_functions,
            (include_package_functions_match => $self->include_package_functions_match) x !!$self->include_package_functions_match,
            (exclude_package_functions_match => $self->exclude_package_functions_match) x !!$self->exclude_package_functions_match,
            skip_format => $self->skip_format ? 1:0,
        );
        $self->log_fatal("Failed generating $scriptname: $res->[0] - $res->[1]")
            unless $res->[0] == 200;
    }

    {
        my $ver = 0;
        my %mem;
        my $perimod = $res->[3]{'func.cmdline_module'};
        $self->log_debug(["Adding prereq to %s", $perimod]);
        $self->zilla->register_prereqs(
            {phase => $res->[3]{'func.cmdline_module_inlined'} ?
                 'develop' : 'runtime'},
            $perimod => $res->[3]{'func.cmdline_module_version'});
        $mem{$perimod}++;

        my @urls = ($self->url);
        if ($subcommands && @$subcommands) {
            for my $sc (@$subcommands) {
                /:(.+)/;
                push @urls, $1;
            }
        }
        # add prereq to script backend modules
        for my $url (@urls) {
            my ($pkg) = $url =~ m!^(?:pm:)?/(.+)/.*!;
            next unless $pkg;
            $pkg =~ s!/!::!g;
            next if $self->is_own_module($pkg);
            next if $mem{$pkg}++;
            $self->log_debug(["Adding prereq to %s", $pkg]);
            $self->zilla->register_prereqs({phase => 'runtime'}, $pkg => 0);
        }
    }

    my $fileobj = Dist::Zilla::File::InMemory->new(
        name => "bin/$scriptname", content => $res->[2]);
    $self->log(["Creating script 'bin/%s' from Riap function '%s'", $scriptname, $self->url]);
    $self->add_file($fileobj);
}


__PACKAGE__->meta->make_immutable;
1;
# ABSTRACT: Generate Perinci::CmdLine script

=for Pod::Coverage .+

=head1 SYNOPSIS

In F<dist.ini>:

 ; generate a script, by default called bin/check-palindrome
 [GenPericmdScript]
 url=/My/Palindrome/check_palindrome

 ; generate another script, called bin/lssrv
 [GenPericmdScript / Gen_lssrv]
 url=/My/App/list_servers
 name=lssrv

After build, C<bin/check-palindrome> and C<bin/lssrv> will be created.


=head1 DESCRIPTION

After you add L<Rinci> metadata to your function, e.g.:

 package My::Palindrome;
 $SPEC{check_palindrome} = {
     v => 1.1,
     args => {
         text => { schema=>'str*', req=>1, pos=>0 },
         ci   => { schema=>'bool*', cmdline_aliases=>{i=>{}} },
     },
     result_naked => 1,
 };
 sub check_palindrome {
     my %args = @_;
     my $text = $args{ci} ? lc($args{text}) : $args{text};
     $text eq reverse($text);
 }

you can create a command-line script for that function that basically is not
much more than:

 #!perl
 use Perinci::CmdLine::Any;
 Perinci::CmdLine::Any->new(url => '/My/Palindrome/check_palindrome');

This Dist::Zilla plugin lets you automate the creation of such scripts.

B<Creating scripts.> To create a single script, put this in C<dist.ini>:

 [GenPericmdScript]
 ;required
 url=/My/Palindrome/check_palindrome
 ;optional
 abstract=Check if a text is a palindrome
 ; ...

To create more scripts, load the plugin again using the C<[Plugin/Name]> syntax,
e.g.:

 [GenPericmdScript / GenAnotherScript]
 ...


=head1 CONFIGURATION (SCRIPT SPECIFICATION)

=head2 url* => str

Riap URL. If the script does not contain subcommand, this should refer to a
function URL. If the script contains subcommands, this should usually refer to a
package URL.

=head2 subcommands => str

For creating a CLI script with subcommands. Value is a comma-separated entries
of subcommand specification. Each subcommand specification must be in the form
of SUBCOMMAND_NAME:URL[:SUMMARY]. Example:

 delete:/My/App/delete_item, add:/My/App/add_item, refresh:/My/App/refresh_item:Refetch an item from source

=head2 subcommands_from_package_functions => bool

Will be passed to App::GenPericmdScript::gen_perinci_cmdline_script() backend.

=head2 include_package_functions_match => re

Will be passed to App::GenPericmdScript::gen_perinci_cmdline_script() backend.

=head2 exclude_package_functions_match => re

Will be passed to App::GenPericmdScript::gen_perinci_cmdline_script() backend.

=head2 name => str

Name of script to create. Default will be taken from function name, with C<_>
replaced to C<->.

=head2 cmdline => str

Select module to use. Default is L<Perinci::CmdLine::Any>, but you can set this
to C<classic> (equals to L<Perinci::CmdLine::Classic>), C<any>
(L<Perinci::CmdLine::Any>), or C<lite> (L<Perinci::CmdLine::Lite>) or module
name.

=head2 prefer_lite => bool (default: 1)

If set to 0 and you are using C<Perinci::CmdLine::Any>, C<-prefer_lite> option
will be passed in the code.

=head2 enable_log => bool

Will be passed to Perinci::CmdLine object construction code (as C<log>).

=head2 default_log_level => str

If set, will add this code to the generated script:

 BEGIN { no warnings; $main::Log_Level = "..." }

This can be used if you want your script to be verbose by default, for example.

=head2 extra_urls_for_version => str

Comma-separated string, will be passed to Perinci::CmdLine object construction
code (as array).

=head2 config_filename => str

Will be passed to Perinci::CmdLine object construction code.

=head2 ssl_verify_hostname => bool (default: 1)

If set to 0, will add this code to the generated script:

 $ENV{PERL_LWP_SSL_VERIFY_HOSTNAME} = 0;

This can be used if the Riap function URL is https and you don't want to verify.

=head2 load_modules => str

Comma-separated string, extra modules to load in the generated script.

=head2 snippet_before_instantiate_cmdline => str

This is like the configuration, but per-script.

=head2 skip_format => bool

Passed to Perinci::CmdLine object construction code.


=head1 CONFIGURATION (OTHER)

=head2 build_load_modules => str

A comma-separated string. Load module(s) during build process.


=head1 SEE ALSO

L<Rinci>

L<Pod::Weaver::Plugin::Rinci> to fill more stuffs to the POD of the generated
script.

C<Dist::Zilla::Plugin::Rinci::*> for plugins that utilize Rinci metadata.
