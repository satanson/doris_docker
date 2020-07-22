#!/bin/bash
set -e -o pipefail
basedir=$(cd $(dirname $(readlink -f ${BASH_SOURCE:-$0}));pwd)
cd ${basedir}

source ${basedir}/functions.sh
source ${basedir}/doris_ops.sh

yellow_print "service: "
service=$(selectOption "doris_fe" "doris_be")

yellow_print "cmd: "
cmd=$(selectOption "restart" "restart_all" "stop" "stop_all" "start" "start_all" "bootstrap" "bootstrap_all" "destroy" "destroy_all")
if isIn ${cmd} "restart_all|stop_all|start_all|bootstrap_all|destroy_all";then
  green_print "exec: ${cmd}_${service}"
  confirm
  ${cmd}_${service}
elif isIn ${cmd} "restart|stop|start|bootstrap|destroy";then
  yellow_print "node: "
  if isIn ${service} "doris_fe";then
    node=$(selectOption ${doris_fe_list})
  elif isIn ${service} "doris_be";then
    node=$(selectOption ${doris_be_list})
  fi
  green_print "exec: ${cmd}_${service} ${node}"
  confirm
  ${cmd}_${service} ${node}
fi
