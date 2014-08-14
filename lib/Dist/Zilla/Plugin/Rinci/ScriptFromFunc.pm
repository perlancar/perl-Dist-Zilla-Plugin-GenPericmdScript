package Dist::Zilla::Plugin::Rinci::ScriptFromFunc;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;

use Moose;
with (
	'Dist::Zilla::Role::FileMunger',
	'Dist::Zilla::Role::FileFinderUser' => {
		default_finders => [ ':ExecFiles' ],
	},
);

use namespace::autoclean;

sub munge_files {
    my $self = shift;

    $self->munge_file($_) for @{ $self->found_files };
    return;
}

sub munge_file {
	my ( $self, $file ) = @_;

        my $filename = $file->name;
        my $filebasename = $filename; $filebasename =~ s!.+/!!;

	unless ($file->name =~ m!(script|bin)/!) {
            $self->log_debug('Skipping $filename: not script');
            return;
	}

	my $version = $self->zilla->version;

	my $content = $file->content;

        $content =~ m/^# FUNC: (.+)/m or do {
            $self->log_debug("Skipping $filename: no '# FUNC: <funcname>' line in script");
            return;
        };

        my $repl = "";
        $repl .= "# ABSTRACT: Some abstract\n";
        $repl .= "# PODNAME: $filebasename\n";
        $repl .= "# DATE\n";
        $repl .= "# VERSION\n";
        $repl .= "# code ...\n";
        $repl .= "\n=head1 SYNOPSIS\n\n blah\n\n";
        $repl .= "\n=head1 DESCRIPTION\n\n blah\n";

        $content =~ s/^(# FUNC: .+)/$1\n$repl/m;
        $self->log("Filling out script information for '$filename'");
        $file->content($content);
	return;
}
__PACKAGE__->meta->make_immutable;
1;
# ABSTRACT: Fill out script details from Rinci function metadata

=for Pod::Coverage .+

=head1 SYNOPSIS

in dist.ini

 [Rinci::ScriptFromFunc]

in your CLI script, e.g. bin/create-foo

 #!perl
 # FUNC: /Your/Package/create_foo

This plugin will then fill out the script's Synopsis POD section (from examples
in Rinci function metadata), Description POD section (from metadata), Options
POD section (from metadata), code (using C<Perinci::CmdLine::Any> to run the
function via command-line). So basically your script now just needs to contain
the C<# FUNC: ...> line.


=head1 DESCRIPTION


=head1 SEE ALSO

