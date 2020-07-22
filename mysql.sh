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
if [ $# -ge 1 ];then
  if [ "x${1%%.sql}x" != "x${1}x" -a -f "${1}" ];then
    localSql=$(readlink -f ${1})
    dockerSql=/tmp/$(basename ${1})
  else
    localSql=/tmp/tmp.sql
    dockerSql=${localSql}
    echo "$*" >/tmp/tmp.sql
  fi
  sqlBindFlag="-v ${localSql}:${dockerSql}"
  sqlRedirect="<${dockerSql}"
fi

# get read-only follower from docker-ps
follower=$(docker ps -f status=running -f name=doris_fe_follower --format={{.Names}}|head -1)
if [ -z "${follower}" ];then
  echo "No doris-fe follower exists!!!" >&2
  exit 1 
fi
followerIp=$(perl -aF/\\s+/ -ne "print \$F[0] if /\b${follower}\b/" hosts)


cat <<'DONE' >ls_fe.sql
SHOW PROC '/frontends';
DONE

# query master follower from the readonly follower
masterFeIp=$(docker run -it ${dockerFlags} -v ${PWD}/ls_fe.sql:/tmp/ls_fe.sql mysql:5.7 \
  bash -c "mysql -h ${followerIp} -P ${query_port} -u root </tmp/ls_fe.sql" | \
  perl -aF'\s+' -lne  'print "$F[1]" if /doris_fe/ && $F[8] eq qq/true/'|\
  head -1)

if [ -z "${masterFeIp}" ];then
  echo "No master doris-fe exists!!!" >&2
  exit 1 
fi
docker run -it ${dockerFlags} ${sqlBindFlag}  mysql:5.7 bash -c "mysql -h ${masterFeIp} -P ${query_port} -u root ${sqlRedirect}"
