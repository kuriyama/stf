#!/usr/bin/perl

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
s|created_at INT NOT NULL|created_at INTEGER NOT NULL default floor(extract(epoch from now()))|g;
s|updated_at TIMESTAMP|updated_at TIMESTAMP default now()|g;

s{CREATE TABLE (\w+) \((.*?)\);}{indexing($1, $2)}egs;

print <<END;
DROP TABLE IF EXISTS entity;
DROP TABLE IF EXISTS deleted_bucket;
DROP TABLE IF EXISTS deleted_object;
DROP TABLE IF EXISTS object;
DROP TABLE IF EXISTS bucket;
DROP TABLE IF EXISTS storage;
END
print $_, join("", @idx);

print <<'END';
CREATE OR REPLACE FUNCTION update_stamp() RETURNS trigger AS $update_stamp$
  BEGIN
    NEW.updated_at = current_timestamp;
    RETURN NEW;
  END;
$update_stamp$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION unix_timestamp(timestamp with time zone) RETURNS int AS $unix_timestamp$
  DECLARE
    date alias for $1;
  BEGIN
    RETURN extract(epoch from date)::int;
  END
$unix_timestamp$ LANGUAGE plpgsql;
END

foreach (qw(storage bucket object entity)) {
  print <<"END";
CREATE TRIGGER $_\_stamp BEFORE INSERT OR UPDATE ON $_ FOR EACH ROW EXECUTE PROCEDURE update_stamp();
END
}

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
