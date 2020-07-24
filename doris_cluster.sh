#!/bin/bash
set -e -o pipefail
basedir=$(cd $(dirname $(readlink -f ${BASH_SOURCE:-$0}));pwd)
cd ${basedir}

source ${basedir}/functions.sh
source ${basedir}/doris_ops.sh
alternatives="start|stop|restart|bootstrap|destroy"
action=${1:?"missging 'action', accepted values are '${alternatives}'"};shift
checkArgument "action" ${action} ${alternatives}
${action}_doris_cluster
