#!/bin/bash
set -e -o pipefail
basedir=$(cd $(dirname $(readlink -f ${BASH_SOURCE:-$0}));pwd)
cd ${basedir}
query_port=$(perl -ne 'print $1 if /^\s*query_port\s*=\s*(\b\d+\b)/' doris_fe_conf/fe.conf)


# get read-only follower from docker-ps
follower=$(docker ps -f status=running -f name=doris_fe_follower --format={{.Names}}|head -1)
if [ -z "${follower}" ];then
  echo "No doris-fe follower exists!!!" >&2
  exit 1 
fi

followerIp=$(perl -aF/\\s+/ -ne "print \$F[0] if /\b${follower}\b/" hosts)

# query master follower from the readonly follower
masterFeIp=$(mysql -h ${followerIp} -P ${query_port} -u root <<<"SHOW PROC '/frontends';" | \
  perl -aF'\s+' -lne  'print "$F[1]" if /doris_fe/ && $F[8] eq qq/true/'|\
  head -1)

if [ -z "${masterFeIp}" ];then
  echo "No master doris-fe exists!!!" >&2
  exit 1 
fi


if [ $# -ge 1 ];then
  if [ "x${1%%.sql}x" != "x${1}x" -a -f "${1}" ];then
    sql=$(readlink -f ${1})
    echo "mysql -h ${masterFeIp} -P ${query_port} -u root <${sql}" >&2
    mysql -h ${masterFeIp} -P ${query_port} -u root <${sql}
  else
    echo "mysql -h ${masterFeIp} -P ${query_port} -u root <<<'$*'" >&2
    mysql -h ${masterFeIp} -P ${query_port} -u root <<<"$*"
  fi
else
  echo "mysql -h ${masterFeIp} -P ${query_port} -u root" >&2
  mysql -h ${masterFeIp} -P ${query_port} -u root
fi
