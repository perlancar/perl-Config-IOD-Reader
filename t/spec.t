#!perl

use 5.010;
use strict;
use warnings;

use Config::IOD::Reader;
use File::ShareDir ':ALL';
use Test::Exception;
use Test::More 0.98;

my $dir = dist_dir('IOD-Examples');
diag ".IOD files are at $dir";

my $reader = Config::IOD::Reader->new;

my @files = glob "$dir/examples/*.iod";
diag explain \@files;

for my $file (@files) {
    next if $file =~ /TODO-/;

    subtest "file $file" => sub {
        if ($file =~ /invalid-/) {
            dies_ok { $reader->read_file($file) } "dies";
        } else {
            my $res = $reader->read_file($file);
            my $expected = Config::IOD::Reader::__decode_json(
                Config::IOD::Reader::__read_file("$file.json")
              );
            is_deeply($res, $expected->[2])
                or diag explain $res, $expected->[2];
        };
    }
}

DONE_TESTING:
done_testing;
