package Config::IOD::Reader;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;

our $DEBUG = 0;

sub new {
    my ($class, %attrs) = @_;
    $attrs{default_section} //= 'GLOBAL';
    $attrs{allow_bang_only} //= 1;
    $attrs{enable_encoding} //= 1;
    $attrs{enable_quoting}  //= 1;
    $attrs{enable_bracket}  //= 1;
    $attrs{enable_brace}    //= 1;
    $attrs{enable_expr}     //= 0;
    bless \%attrs, $class;
}

# borrowed from Parse::CommandLine. differences: returns arrayref. return undef
# on error (instead of dying).
sub __parse_command_line {
    my $str = shift;

    $str =~ s/\A\s+//ms;
    $str =~ s/\s+\z//ms;

    my @argv;
    my $buf;
    my $escaped;
    my $double_quoted;
    my $single_quoted;

    for my $char (split //, $str) {
        if ($escaped) {
            $buf .= $char;
            $escaped = undef;
            next;
        }

        if ($char eq '\\') {
            if ($single_quoted) {
                $buf .= $char;
            }
            else {
                $escaped = 1;
            }
            next;
        }

        if ($char =~ /\s/) {
            if ($single_quoted || $double_quoted) {
                $buf .= $char;
            }
            else {
                push @argv, $buf if defined $buf;
                undef $buf;
            }
            next;
        }

        if ($char eq '"') {
            if ($single_quoted) {
                $buf .= $char;
                next;
            }
            $double_quoted = !$double_quoted;
            next;
        }

        if ($char eq "'") {
            if ($double_quoted) {
                $buf .= $char;
                next;
            }
            $single_quoted = !$single_quoted;
            next;
        }

        $buf .= $char;
    }
    push @argv, $buf if defined $buf;

    if ($escaped || $single_quoted || $double_quoted) {
        return undef;
    }

    \@argv;
}

sub __read_file {
    my $filename = shift;
    open my $fh, "<", $filename
        or die "Can't open file '$filename': $!";
    binmode($fh, ":utf8");
    local $/;
    return ~~<$fh>;
}

sub __decode_json {
    state $json = do {
        require JSON;
        JSON->new->allow_nonref;
    };
    my $res;
    eval { $res = $json->decode(shift) };
    if ($@) {
        return [500, "Invalid JSON: $@"];
    } else {
        return [200, "OK", $res];
    }
}

sub __decode_hex {
    pack("H*", shift);
}

sub __decode_base64 {
    require MIME::Base64;
    MIME::Base64::decode_base64(shift);
}

sub _decode_expr {
    my ($self, $val) = @_;
    require Config::IOD::Reader::Expr;
    no strict 'refs';
    local *{"Config::IOD::Reader::Expr::val"} = sub {
        my $arg = shift;
        if ($arg =~ /(.+)\.(.+)/) {
            return $self->{_res}{$1}{$2};
        } else {
            return $self->{_res}{ $self->{_cur_section} }{$arg};
        }
    };
    my $res = Config::IOD::Reader::Expr::_parse_expr($val);
    $self->_err("Can't decode expr: $res->[1]") if $res->[0] != 200;
    $res->[2];
}

sub _err {
    my ($self, $msg) = @_;
    die join(
        "",
        @{ $self->{_include_stack} } ? "$self->{_include_stack}[0] " : "",
        "line $self->{_linum}: ",
        $msg
    );
}

sub _push_include_stack {
    require Cwd;

    my ($self, $path) = @_;

    # included file's path is based on the main (topmost) file
    if (@{ $self->{_include_stack} }) {
        require File::Spec;
        my (undef, $dir, $file) =
            File::Spec->splitpath($self->{_include_stack}[-1]);
        $path = File::Spec->rel2abs($path, $dir);
    }

    my $abs_path = Cwd::abs_path($path) or return [400, "Invalid path name"];
    return [409, "Recursive", $abs_path]
        if grep { $_ eq $abs_path } @{ $self->{_include_stack} };
    push @{ $self->{_include_stack} }, $abs_path;
    return [200, "OK", $abs_path];
}

sub _pop_include_stack {
    my $self = shift;

    die "BUG: Overpopped _pop_include_stack" unless @{$self->{_include_stack}};
    pop @{ $self->{_include_stack} };
}

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

sub _read_string {
    my ($self, $str) = @_;

    my $res = $self->{_res};
    my $cur_section = $self->{_cur_section};

    my $directive_re = $self->{allow_bang_only} ?
        qr/^;?\s*!\s*(\w+)\s*/ :
        qr/^;\s*!\s*(\w+)\s*/;

    my @lines = split /^/, $str;
    $self->{_linum} = 0;
  LINE:
    for my $line (@lines) {
        chomp $line;
        $self->{_linum}++;

        $self->{_last} = '';

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
            my $args = __parse_command_line($line);
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
                $self->_read_string(__read_file($path));
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
            $self->{_last} = 'section';
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

            my $enc;
            if ($self->{enable_encoding} && $val =~ /^!(\w+) (.*)/) {
                $enc = $1;
                $val = $2;
            } elsif ($self->{enable_quoting} && $val =~ /^"/) {
                $val =~ s/\s*[;#][^"]*\z//; # allow comment if not ambiguous
                my $res = __decode_json($val);
                if ($res->[0] != 200) {
                    $self->_err("Invalid JSON string");
                }
                $val = $res->[2];
            } elsif ($self->{enable_bracket} && $val =~ /^\[/) {
                $val =~ s/\s*[;#][^\]]*\z//; # allow comment if not ambiguous
                my $res = __decode_json($val);
                if ($res->[0] != 200) {
                    $self->_err("Invalid JSON array");
                }
                $val = $res->[2];
            } elsif ($self->{enable_brace} && $val =~ /^\{/) {
                $val =~ s/\s*[;#][^}]*\z//; # allow comment if not ambiguous
                my $res = __decode_json($val);
                if ($res->[0] != 200) {
                    $self->_err("Invalid JSON object (hash)");
                }
                $val = $res->[2];
            }

            if (defined $enc) {
                # canonicalize shorthand
                $enc = "json" if $enc eq 'j';
                $enc = "hex"  if $enc eq 'h';
                $enc = "expr" if $enc eq 'e';
                if ($self->{allow_encodings}) {
                    $self->_err("Encoding '$enc' is not in ".
                                    "allow_encodings list")
                        unless grep { $_ eq $enc } @{$self->{allow_encodings}};
                }
                if ($self->{disallow_encodings}) {
                    $self->_err("Encoding '$enc' is in ".
                                    "disallow_encodings list")
                        if grep { $_ eq $enc } @{$self->{disallow_encodings}};
                }
                if ($enc eq 'json') {
                    my $res = __decode_json($val);
                    if ($res->[0] != 200) {
                        $self->_err("Invalid JSON");
                    }
                    $val = $res->[2];
                } elsif ($enc eq 'hex') {
                    $val =~ s/\s*[;#].*\z//; # shave comment
                    $val = __decode_hex($val);
                } elsif ($enc eq 'base64') {
                    $val =~ s/\s*[;#].*\z//; # shave comment
                    $val = __decode_base64($val);
                } elsif ($enc eq 'expr') {
                    $self->_err("Expr is not allowed (enable_expr=0)")
                        unless $self->{enable_expr};
                    $val = $self->_decode_expr($val);
                } else {
                    $self->_err("Unknown encoding '$enc'");
                }
            } else {
                $val =~ s/\s*[;#].*\z//; # shave comment
            }

            if (exists $res->{$cur_section}{$name}) {
                if ($self->{_arrayified}{$cur_section}{$name}++) {
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

sub _init_read {
    my $self = shift;
    $self->{_res} = {};
    $self->{_merge} = undef;
    $self->{_include_stack} = [];
    $self->{_num_seen_section_lines} = 0;
    $self->{_cur_section} = $self->{default_section};
}

sub read_file {
    my ($self, $filename) = @_;
    $self->_init_read;
    my $res = $self->_push_include_stack($filename);
    die "Can't read '$filename': $res->[1]" unless $res->[0] == 200;
    $res =
        $self->_read_string(__read_file($filename));
    $self->_pop_include_stack;
    $res;
}

sub read_string {
    my ($self, $str) = @_;
    $self->_init_read;
    $self->_read_string($str);
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

Config::IOD::Reader 0.05 adds experimental support for expression. This allows
you to do something like this:

 [section1]
 foo=1
 bar="monkey"

 [section2]
 baz =!e 1+1
 qux =!e "grease" . val("section1.bar")
 quux=!e val("qux") . " " . val('baz')

And the result will be:

 {
     section1 => {foo=>1, bar=>"monkey"},
     section2 => {baz=>2, qux=>"greasemonkey", quux=>"greasemonkey 2"},
 }

For safety, you'll need to set C<enable_expr> to 1 first.

The syntax of the expression (the C<expr> encoding) is not officially specified
yet in the L<IOD> specification. It will probably be Expr (see
L<Language::Expr::Manual::Syntax>). At the moment, this module implements a very
limited subset that is compatible (lowest common denominator) with Perl syntax
and uses C<eval()> to evaluate the expression. However, only the limited subset
is allowed (checked by Perl 5.10 regular expression).

The supported terms:

 number
 string (double-quoted and single-quoted)
 undef literal
 function call (only the 'val' function is supported)
 grouping (parenthesis)

The supported operators are:

 + - .
 * / % x
 **
 unary -, unary +, !, ~

The C<val()> function refers to the configuration key. If the argument contains
".", it will be assumed as C<SECTIONNAME.KEYNAME>, otherwise it will access the
current section's key. Since parsing is done in a single pass, you can only
refer to the already mentioned key.


=head1 ATTRIBUTES

=head2 default_section => str (default: C<GLOBAL>)

If a key line is specified before any section line, this is the section that the
key will be put in.

=head2 enable_encoding => bool (default: 1)

If set to false, then encoding notation will be ignored and key value will be
parsed as verbatim. Example:

 name = !json null

With C<enable_encoding> turned off, value will not be undef but will be string
with the value of (as Perl literal) C<"!json null">.

=head2 enable_quoting => bool (default: 1)

If set to false, then quotes on key value will be ignored and key value will be
parsed as verbatim. Example:

 name = "line 1\nline2"

With C<enable_quoting> turned off, value will not be a two-line string, but will
be a one line string with the value of (as Perl literal) C<"line 1\\nline2">.

=head2 enable_bracket => bool (default: 1)

If set to false, then JSON literal array will be parsed as verbatim. Example:

 name = [1,2,3]

With C<enable_bracket> turned off, value will not be a three-element array, but
will be a string with the value of (as Perl literal) C<"[1,2,3]">.

=head2 enable_brace => bool (default: 1)

If set to false, then JSON literal object (hash) will be parsed as verbatim.
Example:

 name = {"a":1,"b":2}

With C<enable_brace> turned off, value will not be a hash with two pairs, but
will be a string with the value of (as Perl literal) C<'{"a":1,"b":2}'>.

=head2 allow_encodings => array

If defined, set list of allowed encodings. Note that if C<disallow_encodings> is
also set, an encoding must also not be in that list.

Also note that, for safety reason, if you want to enable C<expr> encoding,
you'll also need to set C<enable_expr> to 1.

=head2 disallow_encodings => array

If defined, set list of disallowed encodings. Note that if C<allow_encodings> is
also set, an encoding must also be in that list.

Also note that, for safety reason, if you want to enable C<expr> encoding,
you'll also need to set C<enable_expr> to 1.

=head2 enable_expr => bool (default: 0)

Whether to enable C<expr> encoding. By default this is turned on, for safety.
Please see L</"EXPRESSION"> for more details.

=head2 allow_directives => array

If defined, only directives listed here are allowed. Note that if
C<disallow_directives> is also set, a directive must also not be in that list.

=head2 disallow_directives => array

If defined, directives listed here are not allowed. Note that if
C<allow_directives> is also set, a directive must also be in that list.

=head2 allow_bang_only => bool (default: 1)

Since the mistake of specifying a directive like this:

 !foo

instead of the correct:

 ;!foo

is very common, the spec allows it. This reader, however, can be configured to
be more strict.


=head1 METHODS

=head2 new(%attrs) => obj

=head2 $reader->read_file($filename) => hash

Read IOD configuration from a file. Die on errors.

=head2 $reader->read_string($str) => hash

Read IOD configuration from a string. Die on errors.


=head1 TODO

Add attribute: C<allow_dupe_section> (default: 1).

Add attribute to set behaviour when encountering duplicate key name? Default is
create array, but we can also croak, replace, ignore.


=head1 SEE ALSO

L<IOD>, L<Config::IOD>, L<IOD::Examples>

=cut
