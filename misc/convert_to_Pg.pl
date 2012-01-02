#!/usr/bin/perl
#
# Copyright (c) 2011  S2 Factory, Inc.  All rights reserved.
#
# $Id$

use strict;
use warnings;
use File::Slurp;

my ($file) = @ARGV;

$_ = read_file($file) or die "open($file): $!";

my @idx;
s| ENGINE=InnoDB||g;
s|BIGINT +UNSIGNED|BIGINT|g;
s|UNIQUE KEY\(|UNIQUE(|g;
s|TINYINT |SMALLINT |g;
s|CREATE TABLE (\w+) SELECT |CREATE TABLE $1 AS SELECT |g;
s|PRIMARY KEY id |PRIMARY KEY |g;

s{CREATE TABLE (\w+) \((.*?)\);}{indexing($1, $2)}egs;

print <<END;
DROP TABLE IF EXISTS storage;
DROP TABLE IF EXISTS bucket;
DROP TABLE IF EXISTS object;
DROP TABLE IF EXISTS deleted_object;
DROP TABLE IF EXISTS deleted_bucket;
DROP TABLE IF EXISTS entity;
END
print $_, join("", @idx);

# ============================================================
sub indexing {
  my ($tbl, $body) = @_;
  while ($body =~ s{,\n       KEY\(([a-z_, ]+)\)}{}s) {
    my $col = $1;
#warn "[$body] $tbl, $col";
    (my $cid = $col) =~ s|, |_|g;
    push @idx, sprintf("CREATE INDEX $tbl\_$cid\_idx ON $tbl($col);\n");
  }
  "CREATE TABLE $tbl ($body);";
}
