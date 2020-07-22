#!/bin/bash
set -e -o pipefail
basedir=$(cd $(dirname $(readlink -f ${BASH_SOURCE:-$0}));pwd)
cd ${basedir}
name=doris_fe_mysql
ip=$(perl -aF/\\s+/ -ne "print \$F[0] if /\b${name}\b/" hosts)
query_port=$(perl -ne 'print $1 if /^\s*query_port\s*=\s*(\b\d+\b)/' doris_fe_conf/fe.conf)
dockerFlags="--rm --name ${name} --hostname ${name}  --net static_net0 --ip ${ip} -v ${PWD}/hosts:/etc/hosts"

sqlBindFlag=""
sqlRedirect=""
if [ $# -ge 1 -a "x${1%%.sql}x" != "x${1}x" -a -f "${1}" ];then
  localSql=$(readlink -f ${1})
  dockerSql=/tmp/$(basename ${1})
  sqlBindFlag="-v ${localSql}:${dockerSql}"
  sqlRedirect="<${dockerSql}"
fi
docker run -it ${dockerFlags} ${sqlBindFlag}  mysql:5.7 bash -c "mysql -h doris_fe0 -P ${query_port} -u root ${sqlRedirect}"
