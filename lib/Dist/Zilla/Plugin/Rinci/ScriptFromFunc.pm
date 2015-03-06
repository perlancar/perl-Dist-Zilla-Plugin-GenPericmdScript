package Dist::Zilla::Plugin::Rinci::ScriptFromFunc;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;

use Moose;
with (
        'Dist::Zilla::Role::FileGatherer',
);

use namespace::autoclean;

use App::GenPericmdScript qw(gen_perinci_cmdline_script);
use Module::Load;

sub mvp_multivalue_args { qw(script) }

# one or more script specification
has script => (is => 'rw');

has snippet_before_instantiate_cmdline => (is=>'rw');

our %KNOWN_SCRIPT_SPEC_PROPS = (
    func => 1, # XXX old, will be removed later
    url => 1,
    name => 1,
    cmdline => 1,
    prefer_lite => 1,
    default_log_level => 1,
    log => 1,
    ssl_verify_hostname => 1,
    snippet_before_instantiate_cmdline => 1,
    config_filename => 1,
    load_modules => 1,
    subcommands => 1,
);

sub gather_files {
    my ($self, $arg) = @_;

    # i do it this way (unshift @INC, "lib" + require "Foo/Bar.pm" instead of
    # unshift @INC, "." + require "lib/Foo/Bar.pm") in my all other Dist::Zilla
    # and Pod::Weaver plugin, so they can work together (require "Foo/Bar.pm"
    # and require "lib/Foo/Bar.pm" would cause Perl to load the same file twice
    # and generate redefine warnings).
    local @INC = ("lib", @INC);

    require Dist::Zilla::File::InMemory;

    my $scripts = $self->script;
    return unless $scripts;
    for my $script (ref($scripts) eq 'ARRAY' ? @$scripts : ($scripts)) {
        my %scriptspec = map { split /\s*=\s*/, $_, 2 }
            split /\s*,\s*/, $script;
        for (keys %scriptspec) {
            $self->log_fatal("Unknown spec property '$_' (script=$script)")
                unless $KNOWN_SCRIPT_SPEC_PROPS{$_};
        }
        my $url = $scriptspec{url} // $scriptspec{func} # XXX func is deprecated
            or $self->log_fatal("No URL specified (script=$script)");
        my $scriptname = $scriptspec{name};
        if (!$scriptname) {
            $scriptname = $url;
            $scriptname =~ s!.+/!!;
            $scriptname =~ s/[^A-Za-z0-9]+/-/g;
            $scriptname =~ s/^-//;
            $scriptname = "script" if length($script) == 0;
        }

        my $snippet_before_instantiate_cmdline =
            $scriptspec{snippet_before_instantiate_cmdline} //
                $self->snippet_before_instantiate_cmdline;

        my $subcommands;
        if ($scriptspec{subcommands}) {
            $subcommands = [split /\s*;\s*/, $scriptspec{subcommands}];
        }

        my $res = gen_perinci_cmdline_script(
            url => $url,
            script_name => $scriptname,
            interpreter_path => 'perl',
            load_module => $scriptspec{load_modules} ? [split(/\s*,\s*/, $scriptspec{load_modules})] : undef,
            log => $scriptspec{log},
            default_log_level => $scriptspec{default_log_level},
            cmdline => $scriptspec{cmdline},
            prefer_lite => $scriptspec{prefer_lite},
            ssl_verify_hostname => $scriptspec{ssl_verify_hostname},
            snippet_before_instantiate_cmdline => $snippet_before_instantiate_cmdline,
            config_filename => $scriptspec{config_filename},
            subcommand => $subcommands,
        );
        $self->log_fatal("Failed generating $scriptname: $res->[0] - $res->[1]")
            unless $res->[0] == 200;

        {
            my $ver = 0;
            $self->zilla->register_prereqs(
                {phase => 'runtime'}, $res->[3]{'func.cmdline_module'} =>
                    $res->[3]{'func.cmdline_module_version'});
        }

        my $file = Dist::Zilla::File::InMemory->new(
            name => "bin/$scriptname", content => $res->[2]);
        $self->log("Creating script 'bin/$scriptname' from Riap function '$url'");
        $self->add_file($file);
    }
}


__PACKAGE__->meta->make_immutable;
1;
# ABSTRACT: Create or fill out script details from Riap function metadata

=for Pod::Coverage .+

=head1 SYNOPSIS

In C<dist.ini>:

 [Rinci::ScriptFromFunc]
 script= url=/My/Palindrome/check_palindrome
 script= name=lssrv, url=/My/App/list_servers

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

 [Rinci::ScriptFromFunc]
 script= url=/My/Palindrome/check_palindrome, abstract=Check if a text is a palindrome

To create more scripts, add more C<script=...> lines. Each C<script=...> line is
a script specification, containing semicolon-separated key=value items. Known
keys:

=over

=item * url => str

Riap URL. If the script does not contain subcommand, this should refer to a
function URL. If the script contains subcommands, this should usually refer to a
package URL.

=item * name => str

Name of script to create. Default will be taken from function name, with C<_>
replaced to C<->.

=item * cmdline => str

Select module to use. Default is L<Perinci::CmdLine::Any>, but you can set this
to C<classic> (equals to L<Perinci::CmdLine::Classic>), C<any>
(L<Perinci::CmdLine::Any>), or C<lite> (L<Perinci::CmdLine::Lite>) or module
name.

=item * prefer_lite => bool (default: 1)

If set to 0 and you are using C<Perinci::CmdLine::Any>, C<-prefer_lite> option
will be passed in the code.

=item * default_log_level => str

If set, will add this code to the generated script:

 BEGIN { no warnings; $main::Log_Level = "..." }

This can be used if you want your script to be verbose by default, for example.

=item * log => bool

Will be passed to Perinci::CmdLine object construction code.

=item * config_filename => str

Will be passed to Perinci::CmdLine object construction code.

=item * ssl_verify_hostname => bool (default: 1)

If set to 0, will add this code to the generated script:

 $ENV{PERL_LWP_SSL_VERIFY_HOSTNAME} = 0;

This can be used if the Riap function URL is https and you don't want to verify.

=item * snippet_before_instantiate_cmdline => str

This is like the configuration, but per-script.

=item * subcommands => str

For creating a CLI script with subcommands. Value is a comma-separated entries
of subcommand specification. Each subcommand specification must be in the form
of SUBCOMMAND_NAME:URL[:SUMMARY]. Example:

 delete:/My/App/delete_item, add:/My/App/add_item, refresh:/My/App/refresh_item:Refetch an item from source

=back

B<Filling out script details.> (NOT YET IMPLEMENTED.) You can also create the
script manually in C<bin/>, but put this marker at the top of the script:

 C<# FROMFUNC: ...>

Where C<...> contains the same comma-separated key=value items, for example:

 C<# FROMFUNC: func=/My/Palindrome/check-palindrome>

B<What are put in the script.> Below are the things put in the script by this
plugin:

=over

=item * shebang line

 #!perl

Not added when not creating.

=item * C<# DATE> line

See L<Dist::Zilla::Plugin::OurDate>. Not added if already there.

=item * C<# VERSION> line

See L<Dist::Zilla::Plugin::OurVersion>. Not added if already there.

=item * C<# ABSTRACT> line

Value will be taken from C<summary> property of the Rinci metadata. Not added if
already there.

=item * C<# PODNAME> line

Value will be taken from function name, with underscore (C<_>) replaced with
dash (C<->). Not added if already there.

=item * Perl code to use the function as a CLI script

By default it's something like this (some aspects customizable):

 use 5.010001;
 use strict;
 use warnings;

 use Perinci::CmdLine::Any;
 Perinci::CmdLine::Any->new(
     url => '/My/Palindrome/check_palindrome',
 );

=item * Synopsis POD section

Will display script's usage as well as examples from the C<examples> property in
the Rinci metadata, if any. Not added if already there.

=item * Description POD section

Value taken from C<description> property of the Rinci metadata. Not added if
already there.

=item * Options POD section

List all the command-line options that the script accepts. Not added if already
there.

=back


=head1 CONFIGURATION

=head2 script => str (multiple allowed)

Specify script to be generated (name, source function, etc). See
L</"DESCRIPTION"> for more details.

=head2 snippet_* => str

Insert code snippet in various places, for some customization in the process of
code generation.

 snippet_before_instantiate_cmdline


=head1 SEE ALSO

L<Rinci>

L<Pod::Weaver::Plugin::Rinci> to fill more stuffs to the POD of the generated
script.

Other C<Dist::Zilla::Plugin::Rinci::*> for plugins that utilize Rinci metadata.
