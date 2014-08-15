package Dist::Zilla::Plugin::Rinci::ScriptFromFunc;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;

use Moose;
with (
	'Dist::Zilla::Role::FileFinderUser' => {
		default_finders => [ ':ExecFiles' ],
	},
        'Dist::Zilla::Role::FileGatherer',
	#'Dist::Zilla::Role::FileMunger',
);

use namespace::autoclean;
use Data::Dump qw(dump);

sub mvp_multivalue_args { qw(script) }

# one or more script specification
has script => (is => 'rw');

sub _get_meta {
    my ($self, $url) = @_;

    state $pa = do {
        require Perinci::Access;
        my $pa = Perinci::Access->new;
        $pa;
    };

    # i do it this way (unshift @INC, "lib" + require "Foo/Bar.pm" instead of
    # unshift @INC, "." + require "lib/Foo/Bar.pm") in my all other Dist::Zilla
    # and Pod::Weaver plugin, so they can work together (require "Foo/Bar.pm"
    # and require "lib/Foo/Bar.pm" would cause Perl to load the same file twice
    # and generate redefine warnings).

    local @INC = ("lib", @INC);

    my $res = $pa->request(meta => $url);
    $self->log_fatal("Can't get meta $url: $res->[0] - $res->[1]")
        unless $res->[0] == 200;
    $res->[2];
}

sub munge_files {
    my $self = shift;

    $self->munge_file($_) for @{ $self->found_files };
    return;
}

sub munge_file {
    my ($self, $file) = @_;

    my $filename = $file->name;
    my $filebasename = $filename; $filebasename =~ s!.+/!!;

    unless ($file->name =~ m!(script|bin)/!) {
        $self->log_debug('Skipping $filename: not script');
        return;
    }

    my $content = $file->content;

    # do stuffs with content

    $file->content($content);

    return;
}

sub gather_files {
    my ($self, $arg) = @_;

    require Dist::Zilla::File::InMemory;

    my $scripts = $self->script;
    return unless $scripts;
    for my $script (ref($scripts) eq 'ARRAY' ? @$scripts : ($scripts)) {
        my %scriptspec = map { split /\s*=\s*/, $_, 2 }
            split /\s*,\s*/, $script;
        my $url = $scriptspec{func}
            or $self->log_fatal("No func URL ('func') specified (script=$script)");
        my $scriptname = $scriptspec{name};
        if (!$scriptname) {
            $scriptname = $url;
            $scriptname =~ s!.+/!!;
            $scriptname =~ s/[^A-Za-z0-9]+/-/g;
            $scriptname =~ s/^-//;
            $scriptname = "script" if length($script) == 0;
        }
        my $meta = $self->_get_meta($url);

        my $content = "";

        # code
        my $cmdline_mod = "Perinci::CmdLine::Any";
        if ($scriptspec{cmdline}) {
            my $val = $scriptspec{cmdline};
            if ($val eq 'any') {
                $cmdline_mod = "Perinci::CmdLine::Any";
            } elsif ($val eq 'classic') {
                $cmdline_mod = "Perinci::CmdLine";
            } elsif ($val eq 'lite') {
                $cmdline_mod = "Perinci::CmdLine::Lite";
            } else {
                $cmdline_mod = $val;
            }
        }
        $content .= join(
            "",
            "#!perl\n",
            "\n",
            "# Note: This script is a CLI interface to Riap function $url\n",
            "# and generated automatically using ", __PACKAGE__,
            " version ", ($Dist::Zilla::Plugin::Rinci::ScriptFromFunc::VERSION // '?'), "\n",
            "\n",
            "# DATE\n",
            "# VERSION\n",
            "\n",
            "use 5.010001;\n",
            "use strict;\n",
            "use warnings;\n",
            "\n",
            "use $cmdline_mod",
            ($cmdline_mod eq 'Perinci::CmdLine::Any' &&
                 $scriptspec{prefer_lite} ?
                 " -prefer_lite=>1" : ""),
            ";\n",
            "$cmdline_mod->new(url => ", dump($url), ")->run;\n",
        );

        # abstract line
        $content .= "# ABSTRACT: " . ($meta->{summary} // $scriptname) . "\n";

        # podname
        $content .= "# PODNAME: $scriptname\n";

        # Synopsis POD section
        $content .= join(
            "",
            "\n=head1 SYNOPSIS\n\n",
            "Usage:\n\n % $scriptname\n\n", # XXX
            "Examples:\n\n TODO\n\n", # XXX
            "To see all options:\n\n % $scriptname --help\n\n",
            "\n",
        );

        # Description POD section
        require Markdown::To::POD;
        $content .= join(
            "",
            "\n=head1 DESCRIPTION\n\n",
            $meta->{description} ?
                Markdown::To::POD::markdown_to_pod($meta->{description}) : '',
            "\n",
        );

        # Options POD section
        $content .= join(
            "",
            "\n=head1 OPTIONS\n\n",
            " TODO\n",
            "\n",
        );

        my $file = Dist::Zilla::File::InMemory->new(
            name => "bin/$scriptname", content => $content);
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
 script= func=/My/Palindrome/check_palindrome,
 script= name=lssrv, func=/My/App/list_servers

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

B<Creating scripts.> To create a script, put this in C<dist.ini>:

 [Rinci::ScriptFromFunc]
 script= func=/My/Palindrome/check_palindrome, abstract=Check if a text is a palindrome

To create more scripts, add more C<script=...> lines. Each C<script=...> line is
a script specification, containing comma-separated key=value items. Known keys:

=over

=item * func => str

Riap function URL.

=item * name => str

Name of script to create. Default will be taken from function name, with C<_>
replaced to C<->.

=item * cmdline => str

Select module to use. Default is L<Perinci::CmdLine::Any>, but you can set this
to C<classic> (equals to L<Perinci::CmdLine>), C<any>
(L<Perinci::CmdLine::Any>), or C<lite> (L<Perinci::CmdLine::Lite>) or module
name.

=item * prefer_lite => bool

If set to 1 and you are using C<Perinci::CmdLine::Any>, C<-prefer_lite> option
will be passed in the code.

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


=head1 TODO

=over

=item * completion

If C<completion=1>, add instruction on how to enable bash completion in
Synopsis.

=item * see also

Link to Perl module (the Version POD section already mentions the dist name
though).

=back


=head1 SEE ALSO

L<Rinci>

Other C<Dist::Zilla::Plugin::Rinci::*> for plugins that utilize Rinci metadata.
