package Config::IOD::INI::Reader;

use 5.010001;
use strict;
use warnings;

use parent qw(Config::IOD::Reader);

# AUTHORITY
# DATE
# DIST
# VERSION

sub new {
    my ($class, %attrs) = @_;
    $attrs{enable_directive} //= 0;
    $attrs{enable_encoding}  //= 0;
    $attrs{enable_quoting}   //= 0;
    $attrs{enable_bracket}   //= 0;
    $attrs{enable_brace}     //= 0;
    $attrs{enable_tilde}     //= 0;
    $class->SUPER::new(%attrs);
}

1;
#ABSTRACT: Read INI configuration files (using Config::IOD::Reader)

=head1 SYNOPSIS

 use Config::IOD::INI::Reader;
 my $reader = Config::IOD::INI::Reader->new();
 my $config_hash = $reader->read_file('config.ini');


=head1 DESCRIPTION

This module is just a L<Config::IOD::Reader> subclass. It uses the following
defaults to make the reader's behavior closer to a typical "regular INI files
parser".

    enable_directive = 0
    enable_encoding  = 0
    enable_quoting   = 0
    enable_bracket   = 0
    enable_brace     = 0
    enable_tilde     = 0


=head1 SEE ALSO

L<Config::IOD::Reader>

=cut
