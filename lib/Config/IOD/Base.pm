package Config::IOD::Base;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;

sub new {
    my ($class, %attrs) = @_;
    $attrs{default_section} //= 'GLOBAL';
    $attrs{allow_bang_only} //= 1;
    $attrs{enable_encoding} //= 1;
    $attrs{enable_quoting}  //= 1;
    $attrs{enable_bracket}  //= 1;
    $attrs{enable_brace}    //= 1;
    $attrs{enable_expr}     //= 0;
    # allow_encodings
    # disallow_encodings
    # allow_directives
    # disallow_directives
    bless \%attrs, $class;
}

# borrowed from Parse::CommandLine. differences: returns arrayref. return undef
# on error (instead of dying).
sub _parse_command_line {
    my ($self, $str) = @_;

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

sub _decode_json {
    my ($self, $val) = @_;
    state $json = do {
        require JSON;
        JSON->new->allow_nonref;
    };
    my $res;
    eval { $res = $json->decode($val) };
    if ($@) {
        return [500, "Invalid JSON: $@"];
    } else {
        return [200, "OK", $res];
    }
}

sub _decode_hex {
    my ($self, $val) = @_;
    pack("H*", $val);
}

sub _decode_base64 {
    my ($self, $val) = @_;
    require MIME::Base64;
    MIME::Base64::decode_base64($val);
}

sub _decode_expr {
    require Config::IOD::Expr;

    my ($self, $val) = @_;
    no strict 'refs';
    local *{"Config::IOD::Expr::val"} = sub {
        my $arg = shift;
        if ($arg =~ /(.+)\.(.+)/) {
            return $self->{_res}{$1}{$2};
        } else {
            return $self->{_res}{ $self->{_cur_section} }{$arg};
        }
    };
    my $res = Config::IOD::Expr::_parse_expr($val);
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

sub _init_read {
    my $self = shift;

    $self->{_include_stack} = [];
}

sub _read_file {
    my ($self, $filename) = @_;
    open my $fh, "<", $filename
        or die "Can't open file '$filename': $!";
    binmode($fh, ":utf8");
    local $/;
    return ~~<$fh>;
}

sub read_file {
    my ($self, $filename) = @_;
    $self->_init_read;
    my $res = $self->_push_include_stack($filename);
    die "Can't read '$filename': $res->[1]" unless $res->[0] == 200;
    $res =
        $self->_read_string($self->_read_file($filename));
    $self->_pop_include_stack;
    $res;
}

sub read_string {
    my ($self, $str) = @_;
    $self->_init_read;
    $self->_read_string($str);
}

1;
#ABSTRACT: Base class for Config::IOD and Config::IOD::Reader

=head1 ATTRIBUTES

=for BEGIN_BLOCK: attributes

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

=for END_BLOCK: attributes


=head1 EXPRESSION

=for BEGIN_BLOCK: expression

Expression allows you to do things like:

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

For safety, you'll need to set C<enable_expr> attribute to 1 first to enable
this feature.

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

=for END_BLOCK: expression


=head1 METHODS

=for BEGIN_BLOCK: methods

=head2 new(%attrs) => obj

=head2 $reader->read_file($filename)

Read IOD configuration from a file. Die on errors.

=head2 $reader->read_string($str)

Read IOD configuration from a string. Die on errors.

