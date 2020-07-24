#!/usr/bin/perl
use strict;
use warnings;
use Getopt::Long;
use Carp;

our ($OPT_concurrencyInit, $OPT_concurrencyLinearVarying, $OPT_concurrencyExponentialVarying) = (1, 0, 2);
our ($OPT_ioSizeInit, $OPT_ioSizeLinearVarying, $OPT_ioSizeExponentialVarying) = (256, 0, 1);
our ($OPT_fileSize, $OPT_directory, $OPT_timeout, $OPT_stopOnSaturation) = (1*2**19, "", 7200, "true");
our ($OPT_concurrencyMax, $OPT_ioSizeMax) = (500, 64*2**10);

sub options(){ map {/^OPT_(\w+)\b$/; ("$1=s" => eval "*${_}{SCALAR}") } grep {/^OPT_\w+\b$/} keys %:: }

sub usage(){
	my $name = qx(basename $0); chomp $name;
	"USAGE:\n\t" . "$name " . join " ", map{/^OPT_(\w+)$/; "--$1"} grep {/^OPT_\w+\b$/} keys %::;
}
label=
hdfsPath=
table=
user=
password=

cat<<"DONE"
LOAD LABEL {{LABEL}}
(
  DATA INFILE("{{HDFS_PATH}}")
  INTO TABLE `{{TABLE}}`
)
WITH BROKER hdfs 
(
  "username"="{{USER}}",
  "password"="{{PASSWORD}}"
)
PROPERTIES
(
  "timeout"="3600",
  "max_filter_ratio"="0.1"
);
DONE
