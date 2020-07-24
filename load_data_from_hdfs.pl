#!/usr/bin/perl
use strict;
use warnings;
use Getopt::Long;
use Carp;
use Cwd qw(abs_path);
use File::Basename qw(dirname);

our ($OPT_db, $OPT_hdfsPath, $OPT_table, $OPT_columnSeparator, $OPT_user, $OPT_password) = (undef, undef, undef, ",", "test", "");
sub options(){ map {/^OPT_(\w+)\b$/; ("$1=s" => eval "*${_}{SCALAR}") } grep {/^OPT_\w+\b$/} keys %:: }
sub usage(){
	my $name = qx(basename $0); chomp $name;
	"USAGE:\n\t" . "$name " . join " ", map{/^OPT_(\w+)$/; "--$1"} grep {/^OPT_\w+\b$/} keys %::;
}

sub show(){
	print join "\n", map {/^OPT_(\w+)\b$/; ("--$1=" . eval "\$$_" ) } grep {/^OPT_\w+\b$/} keys %::;
	print "\n";
}

GetOptions(options()) or die usage();
if (!defined($OPT_db) || !defined($OPT_hdfsPath) || !defined($OPT_table)) {
  die "missing db, hdfsPath or table, \n".usage();
}

my $basedir=dirname($0);
$basedir=abs_path(readlink($basedir)) if -l $basedir;
chdir $basedir;

show();
my $now=qx(date +"%s");chomp $now;
my $label="${OPT_table}_hdfs_load_$now";
qx(
cat >$label.sql <<"DONE" 
USE $OPT_db;
LOAD LABEL $label
(
  DATA INFILE("$OPT_hdfsPath")
  INTO TABLE `$OPT_table`
  COLUMNS TERMINATED BY "$OPT_columnSeparator"
)
WITH BROKER hdfs 
(
  "username"="$OPT_user",
  "password"="$OPT_password"
)
PROPERTIES
(
  "timeout"="3600",
  "max_filter_ratio"="0.1"
);
DONE
);

print "load data from ${OPT_hdfsPath} into ${OPT_table}, label=${label}\n";
qx($basedir/mysql1.sh $label.sql);
