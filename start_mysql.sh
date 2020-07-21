#!/bin/bash
set -e -o pipefail
basedir=$(cd $(dirname $(readlink -f ${BASH_SOURCE:-$0}));pwd)
cd ${basedir}
name=doris_fe_mysql
ip=$(perl -aF/\\s+/ -ne "print \$F[0] if /\b${name}\b/" hosts)
query_port=$(perl -ne 'print $1 if /^\s*query_port\s*=\s*(\b\d+\b)/' doris_fe_conf/fe.conf)
dockerFlags="--rm --name ${name} --hostname ${name}  --net static_net0 --ip ${ip} -v ${PWD}/hosts:/etc/hosts"
docker run -it ${dockerFlags} mysql:5.7 mysql -h doris_fe0 -P ${query_port} -u root -p
