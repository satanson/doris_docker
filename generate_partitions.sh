#!/bin/bash
prevDay="2017-07-01"
currDay=$(date +"%Y-%m-%d" -d@$(($(date +"%s" -d ${prevDay})+3600*24)))
N=${1:-1000};shift
n=0
while : ; do
  partName=$(perl -e "\$a=join qq(), split /-/, qq{${prevDay}}; print qq/p\$a/")
  perl -le "print qq/PARTITION ${partName} VALUES LESS THAN ('${currDay}'),/"
  prevDay=${currDay}
  currDay=$(date +"%Y-%m-%d" -d@$(($(date +"%s" -d ${prevDay})+3600*24)))
  if [ $n -ge $N ];then
    break
  fi
  n=$((n+1))
done
