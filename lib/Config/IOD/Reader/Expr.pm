package Config::IOD::Reader::Expr;

# DATE
# VERSION

use 5.010;
use strict;
use warnings;

my $EXPR_RE = qr{

(?&ANSWER)

(?(DEFINE)

(?<ANSWER>    (?&ADD))
(?<ADD>       (?&MULT)   | (?&MULT)  (?: \s* ([+.-]) \s* (?&MULT)  )+)
(?<MULT>      (?&UNARY)  | (?&UNARY) (?: \s* ([*/x%]) \s* (?&UNARY))+)
(?<UNARY>     (?&POWER)  | [!~+-] (?&POWER))
(?<POWER>     (?&TERM)   | (?&TERM) (?: \s* \*\* \s* (?&TERM))+)

(?<TERM>
    (?&NUM)
  | (?&STR_SINGLE)
  | (?&STR_DOUBLE)
  | undef
  | (?&FUNC)
  | \( \s* ((?&ANSWER)) \s* \)
)

(?<FUNC> val \s* \( (?&TERM) \))

(?<NUM>
    (
     -?
     (?: 0 | [1-9]\d* )
     (?: \. \d+ )?
     (?: [eE] [-+]? \d+ )?
    )
)

(?<STR_SINGLE>
    (
     '
     (?:
         [^\\']+
       |
         \\ ['\\]
       |
         \\
     )*
     '
    )
)

(?<STR_DOUBLE>
    (
     "
     (?:
         [^\\"]+
       |
         \\ ["'\\\$tnrfbae]
# octal, hex, wide hex
     )*
     "
    )
)

) # DEFINE

}msx;

sub _parse_expr {
    my $str = shift;

    return [400, 'Not a valid expr'] unless $str =~ m{\A$EXPR_RE\z}o;
    my $res = eval $str;
    return [500, "Died when evaluating expr: $@"] if $@;
    [200, "OK", $res];
}

1;
# ABSTRACT: Parse expression
