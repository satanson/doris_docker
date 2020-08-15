#!/bin/bash
set -e -o pipefail
basedir=$(cd $(dirname $(readlink -f ${BASH_SOURCE:-$0}));pwd)
cd ${basedir}

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
name=doris_fe_mysql1
ip=$(perl -aF/\\s+/ -ne "print \$F[0] if /\b${name}\b/" hosts)
dockerFlags="--rm --name ${name} --hostname ${name}  --net static_net0 --ip ${ip} -v ${PWD}/hosts:/etc/hosts"
queryPort=$(perl -ne 'print $1 if /^\s*query_port\s*=\s*(\b\d+\b)/' doris_fe_conf/fe.conf)
masterFe=$(docker run -it ${dockerFlags} -v ${PWD}/ls_fe.sql:/tmp/ls_fe.sql mysql:5.7 \
  bash -c "mysql -h ${followerIp} -P ${queryPort} -u root </tmp/ls_fe.sql" | \
  perl -aF'\s+' -lne  'print "$F[1]:$F[4]" if /doris_fe/ && $F[8] eq qq/true/'|\
  head -1)

if [ -z "${masterFe}" ];then
  echo "No master doris-fe exists!!!" >&2
  exit 1 
else
  echo "Current master doris-fe is ${masterFe}"
fi

${basedir}/mysql1.sh "use example_db; truncate table table1;"

now=$(date +"%s")

cat <<'DONE' | curl --location-trusted -u test:test -H "label:table1_20170707_$now" -H "column_separator:," -T - http://${masterFe}/api/example_db/table1/_stream_load
1,1,jim,2
2,1,grace,2
3,2,tom,2
4,3,bush,3
5,3,helen,3
DONE
sleep 5
echo ""
${basedir}/mysql1.sh "use example_db; select * from table1;"
