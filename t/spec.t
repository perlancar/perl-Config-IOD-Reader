#!perl

use 5.010;
use strict;
use warnings;

use Config::IOD::Reader;
use File::ShareDir ':ALL';
use Test::More 0.98;

my $dir = dist_dir('IOD-Examples');
diag ".IOD files are at $dir";

my $reader = Config::IOD::Reader->new;

my @files = glob "$dir/examples/*.iod";
diag explain \@files;

for my $file (@files) {
    next if $file =~ /TODO-|invalid-/;

    my $res = $reader->read_file($file);
    my $expected = Config::IOD::Reader::__decode_json(
        Config::IOD::Reader::__read_file("$file.json")
      );

    subtest "file $file" => sub {
        is_deeply($res, $expected->[2])
            or diag explain $res, $expected->[2];
    };
}

DONE_TESTING:
done_testing;
