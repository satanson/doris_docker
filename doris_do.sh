#!/bin/bash
set -e -o pipefail
basedir=$(cd $(dirname $(readlink -f ${BASH_SOURCE:-$0}));pwd)
cd ${basedir}

source ${basedir}/functions.sh
source ${basedir}/doris_ops.sh

echo "service: "
service=$(selectOption "doris_fe" "doris_be")

echo "cmd: "
cmd=$(selectOption "restart" "restart_all" "stop" "stop_all" "start" "start_all")
if isIn ${cmd} "restart_all|stop_all|start_all";then
  echo "exec: ${cmd}_${service}"
  confirm
  ${cmd}_${service}
elif isIn ${cmd} "restart|stop|start";then
  echo "node: "
  if isIn ${service} "doris_fe";then
    node=$(selectOption $(eval "echo doris_fe{0..$((${doris_fe_num}-1))}"))
  elif isIn ${service} "doris_be";then
    node=$(selectOption $(eval "echo doris_be{0..$((${doris_be_num}-1))}"))
  fi
  echo "exec: ${cmd}_${service} ${node}"
  confirm
  ${cmd}_${service} ${node}
fi
