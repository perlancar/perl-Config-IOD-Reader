package Config::IOD::Reader;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;

use parent qw(Config::IOD::Base);

sub _merge {
    my ($self, $section) = @_;

    my $res = $self->{_res};
    for my $msect (@{ $self->{_merge} }) {
        if ($msect eq $section) {
            # ignore merging self
            next;
            #local $self->{_linum} = $self->{_linum}-1;
            #$self->_err("Can't merge section '$msect' to '$section': ".
            #                "Same section");
        }
        if (!exists($res->{$msect})) {
            local $self->{_linum} = $self->{_linum}-1;
            $self->_err("Can't merge section '$msect' to '$section': ".
                            "Section '$msect' not seen yet");
        }
        for my $k (keys %{ $res->{$msect} }) {
            $res->{$section}{$k} //= $res->{$msect}{$k};
        }
    }
}

sub _init_read {
    my $self = shift;

    $self->SUPER::_init_read;
    $self->{_res} = {};
    $self->{_merge} = undef;
    $self->{_num_seen_section_lines} = 0;
    $self->{_cur_section} = $self->{default_section};
    $self->{_arrayified} = {};
}

sub _read_string {
    my ($self, $str) = @_;

    my $res = $self->{_res};
    my $cur_section = $self->{_cur_section};

    my $directive_re = $self->{allow_bang_only} ?
        qr/^;?\s*!\s*(\w+)\s*/ :
        qr/^;\s*!\s*(\w+)\s*/;

    my @lines = split /^/, $str;
    local $self->{_linum} = 0;
  LINE:
    for my $line (@lines) {
        $self->{_linum}++;

        # blank line
        if ($line !~ /\S/) {
            next LINE;
        }

        # directive line
        if ($line =~ s/$directive_re//) {
            my $directive = $1;
            if ($self->{allow_directives}) {
                $self->_err("Directive '$directive' is not in ".
                                "allow_directives list")
                    unless grep { $_ eq $directive }
                        @{$self->{allow_directives}};
            }
            if ($self->{disallow_directives}) {
                $self->_err("Directive '$directive' is in ".
                                "disallow_directives list")
                    if grep { $_ eq $directive }
                        @{$self->{disallow_directives}};
            }
            my $args = $self->_parse_command_line($line);
            if (!defined($args)) {
                $self->_err("Invalid arguments syntax '$line'");
            }
            if ($directive eq 'include') {
                my $path;
                if (! @$args) {
                    $self->_err("Missing filename to include");
                } elsif (@$args > 1) {
                    $self->_err("Extraneous arguments");
                } else {
                    $path = $args->[0];
                }
                my $res = $self->_push_include_stack($path);
                if ($res->[0] != 200) {
                    $self->_err("Can't include '$path': $res->[1]");
                }
                $path = $res->[2];
                $self->_read_string($self->_read_file($path));
                $self->_pop_include_stack;
            } elsif ($directive eq 'merge') {
                $self->{_merge} = @$args ? $args : undef;
            } elsif ($directive eq 'noop') {
            } else {
                $self->_err("Unknown directive '$directive'");
            }
            next LINE;
        }

        # comment line
        if ($line =~ /^\s*[;#]/) {
            next LINE;
        }

        # section line
        if ($line =~ /^\s*\[\s*(.+?)\s*\](?: \s*[;#].*)?/) {
            my $prev_section = $self->{_cur_section};
            $self->{_cur_section} = $cur_section = $1;
            $res->{$cur_section} //= {};
            $self->{_num_seen_section_lines}++;

            # previous section exists? do merging for previous section
            if ($self->{_merge} && $self->{_num_seen_section_lines} > 1) {
                $self->_merge($prev_section);
            }

            next LINE;
        }

        # key line
        if ($line =~ /^\s*([^=]+?)\s*=\s*(.*)/) {
            my $name = $1;
            my $val  = $2;

            # the common case is that value are not decoded or
            # quoted/bracketed/braced, so we avoid calling _parse_raw_value here
            # to avoid overhead
            if ($val =~ /\A["!\\[\{]/) {
                my ($err, $parse_res, $decoded_val) = $self->_parse_raw_value($val);
                $self->_err("Invalid value: " . $err) if $err;
                $val = $decoded_val;
            } else {
                $val =~ s/\s*[#;].*//; # strip comment
            }

            if (exists $res->{$cur_section}{$name}) {
                if (!$self->{allow_duplicate_key}) {
                    $self->_err("Duplicate key: $name (section $cur_section)");
                } elsif ($self->{_arrayified}{$cur_section}{$name}++) {
                    push @{ $res->{$cur_section}{$name} }, $val;
                } else {
                    $res->{$cur_section}{$name} = [
                        $res->{$cur_section}{$name}, $val];
                }
            } else {
                $res->{$cur_section}{$name} = $val;
            }

            next LINE;
        }

        $self->_err("Invalid syntax");
    }

    if ($self->{_merge} && $self->{_num_seen_section_lines} > 1) {
        $self->_merge($cur_section);
    }

    $res;
}

1;
#ABSTRACT: Read IOD configuration files

=head1 SYNOPSIS

 use Config::IOD::Reader;
 my $reader = Config::IOD::Reader->new(
     # list of known attributes, with their default values
     # default_section     => 'GLOBAL',
     # enable_encoding     => 1,
     # enable_quoting      => 1,
     # enable_backet       => 1,
     # enable_brace        => 1,
     # allow_encodings     => undef, # or ['base64','json',...]
     # disallow_encodings  => undef, # or ['base64','json',...]
     # allow_directives    => undef, # or ['include','merge',...]
     # disallow_directives => undef, # or ['include','merge',...]
     # allow_bang_only     => 1,
     # enable_expr         => 0,
 );
 my $config_hash = $reader->read_file('config.iod');


=head1 DESCRIPTION

This module reads L<IOD> configuration files. It is a minimalist alternative to
the more fully-featured L<Config::IOD>. It cannot write IOD files and is
optimized for low startup overhead.


=head1 EXPRESSION

# INSERT_BLOCK: lib/Config/IOD/Base.pm expression


=head1 ATTRIBUTES

# INSERT_BLOCK: lib/Config/IOD/Base.pm attributes


=head1 METHODS

=head2 new(%attrs) => obj

=head2 $reader->read_file($filename) => hash

Read IOD configuration from a file. Die on errors.

=head2 $reader->read_string($str) => hash

Read IOD configuration from a string. Die on errors.


=head1 SEE ALSO

L<IOD> - specification

L<Config::IOD> - round-trip parser for reading as well as writing IOD documents

L<IOD::Examples> - sample documents

=cut
