#!perl

use 5.010;
use strict;
use warnings;

use Config::IOD::Reader;
use Test::More 0.98;

subtest "opt: default_section" => sub {
    test_read_iod(
        args  => {default_section=>'bawaan'},
        input => <<'_',
a=1
_
        result => {bawaan=>{a=>1}},
    );
};

subtest "opt: allow_directives" => sub {
    test_read_iod(
        args  => {allow_directives=>['merge']},
        input => <<'_',
;!noop
_
        dies  => 1,
    );
    test_read_iod(
        args  => {allow_directives=>['noop']},
        input => <<'_',
;!noop
_
        result => {},
    );
};

subtest "opt: disallow_directives" => sub {
    test_read_iod(
        args  => {disallow_directives=>['noop']},
        input => <<'_',
;!noop
_
        dies  => 1,
    );
    test_read_iod(
        args  => {disallow_directives=>['merge']},
        input => <<'_',
;!noop
_
        result => {},
    );
};

subtest "opt: allow_directives + disallow_directives" => sub {
    test_read_iod(
        args  => {
            allow_directives    => ['noop'],
            disallow_directives => ['noop'],
        },
        input => <<'_',
;!noop
_
        dies  => 1,
    );
};

subtest "opt: enable_quoting=0" => sub {
    test_read_iod(
        args  => {enable_quoting=>0},
        input => <<'_',
name="1\n2"
_
        result => {GLOBAL=>{name=>'"1\\n2"'}},
    );
};

subtest "opt: enable_encoding=0" => sub {
    test_read_iod(
        args  => {enable_encoding=>0},
        input => <<'_',
name=!hex 5e5e
_
        result => {GLOBAL=>{name=>'!hex 5e5e'}},
    );
};

subtest "opt: allow_encodings" => sub {
    test_read_iod(
        args  => {allow_encodings=>['hex']},
        input => <<'_',
name=!json "1\n2"
_
        dies => 1,
    );
    test_read_iod(
        args  => {allow_encodings=>['json']},
        input => <<'_',
name=!json "1\n2"
_
        result => {GLOBAL=>{name=>"1\n2"}},
    );
};

subtest "opt: disallow_encodings" => sub {
    test_read_iod(
        args  => {disallow_encodings=>['json']},
        input => <<'_',
name=!json "1\n2"
_
        dies => 1,
    );
    test_read_iod(
        args  => {disallow_encodings=>['hex']},
        input => <<'_',
name=!json "1\n2"
_
        result => {GLOBAL=>{name=>"1\n2"}},
    );
};

subtest "opt: allow_encodings + disallow_encodings" => sub {
    test_read_iod(
        args  => {
            allow_encodings   =>['json'],
            disallow_encodings=>['json'],
        },
        input => <<'_',
name=!json "1\n2"
_
        dies => 1,
    );
};

subtest "opt: allow_bang_only=0" => sub {
    test_read_iod(
        args  => {allow_bang_only=>0},
        input => <<'_',
a=1
!noop
_
        dies => 1,
    );
};

DONE_TESTING:
done_testing;

sub test_read_iod {
    my %args = @_;

    my $reader_args = $args{args};
    my $test_name = $args{name} //
        "{". join(", ",
                  (map {"$_=$reader_args->{$_}"}
                       sort keys %$reader_args),
              ) . "}";
    subtest $test_name => sub {
        my $reader = Config::IOD::Reader->new(
            %{ $args{args} // {} }
        );
        my $res;
        eval { $res = $reader->read_string($args{input}) };
        my $err = $@;
        if ($args{dies}) {
            ok($err, "dies") or diag explain $res;
            return;
        } else {
            ok(!$err, "doesn't die")
                or do { diag explain "err=$err"; return };
            is_deeply($res, $args{result}, 'result')
                or diag explain $res;
        }
    };
}
