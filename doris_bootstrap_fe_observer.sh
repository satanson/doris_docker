#!/bin/bash
set -e -o pipefail
basedir=$(cd $(dirname $(readlink -f ${BASH_SOURCE:-$0}));pwd)
cd ${basedir}

source ${basedir}/functions.sh
source ${basedir}/doris_ops.sh

doris_fe_observer_list=$(perl -lne 'print $1 if /^\s*\d+(?:\.\d+){3}\s+(doris_fe_observer\d+)\s*$/' ${PWD}/hosts )
for node in ${doris_fe_observer_list};do
  set +e +o pipefail
  destroy_doris_fe ${node}
  set -e -o pipefail
done

for node in ${doris_fe_observer_list};do
  bootstrap_doris_fe ${node}
done
