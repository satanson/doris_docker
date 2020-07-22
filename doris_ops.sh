#!/bin/bash
set -e -o pipefail
basedir=$(cd $(dirname $(readlink -f ${BASH_SOURCE:-$0}));pwd)
test  ${basedir} == ${PWD}
dorisLocalRoot=$(cd ${basedir}/../doris_all;pwd)
dorisDockerRoot=/root/doris

doris_fe_list=$(perl -lne 'print $1 if /^\s*\d+(?:\.\d+){3}\s+(doris_fe_(:?follower|observer)\d+)\s*$/' ${PWD}/hosts )
doris_be_list=$(perl -lne 'print $1 if /^\s*\d+(?:\.\d+){3}\s+(doris_be\d+)\s*$/' ${PWD}/hosts )

dockerFlags="-tid --rm -u root --privileged --net static_net0 -v ${PWD}/hosts:/etc/hosts -v ${dorisLocalRoot}:${dorisDockerRoot}"

stop_node(){
  local name=$1;shift
  set +e +o pipefail
  docker kill ${name}
  docker rm ${name}
  set -e -o pipefail
}

## doris-fe


stop_doris_fe_args(){
  local node=${1:?"undefined 'doris_fe'"};shift
  local finalize=${1:-"false"}
  stop_node ${node}
  if [ "x${finalize}x" != 'xfalsex' ];then
    if isContainerRunning doris_fe_follower;then
      local ip=$(perl -aF/\\s+/ -ne "print \$F[0] if /\b$node\b/" hosts)
      local editLogPort=$(perl -lne 'print $1 if /^\s*edit_log_port\s*=\s*(\b\d+\b)/' ${PWD}/doris_fe_conf/fe.conf)
      editLogPort=${editLogPort:-9010}

      # parse Role of doris-fe naming convention: doris_fe_follower0, doris_fe_observer2 and etc.
      local role=$(echo $node | perl -lne 'print qq/\U$1\E/ if /doris_fe_(follower|observer)\d+/')
      if [ -z "${role}" ];then
        echo $(red_print "Role of doris-fe must be FOLLOWER|OBSERVER") >&2;
        exit 1;
      fi
      ${basedir}/mysql.sh "ALTER SYSTEM DROP ${role} '${ip}:${editLogPort}';"
    fi

    [ -d "${PWD}/${node}_data" ] && rm -fr ${PWD}/${node}_data/*
    mkdir -p ${PWD}/${node}_data
  fi
}

stop_doris_fe(){
  stop_doris_fe_args ${1:?"missing 'node'"} "false"
}

destroy_doris_fe(){
  stop_doris_fe_args ${1:?"missing 'node'"} "true"
}

stop_all_doris_fe(){
  for node in ${doris_fe_list} ;do
    stop_doris_fe ${node}
  done
}

start_doris_fe_args(){
  local node=${1:?"undefined 'doris_fe'"};shift
  local bootstrap=${1:-"false"};shift;
  local ip=$(perl -aF/\\s+/ -ne "print \$F[0] if /\b$node\b/" hosts)
  local flags="
  -v ${PWD}/${node}_data:${dorisDockerRoot}/fe/doris-meta
  -v ${PWD}/${node}_logs:${dorisDockerRoot}/fe/log
  -v ${PWD}/${node}_run:${dorisDockerRoot}/fe/run
  -v ${PWD}/doris_fe_conf:${dorisDockerRoot}/fe/conf
  -e PID_DIR=${dorisDockerRoot}/fe/run
  --name $node
  --hostname $node
  --ip $ip
  "

  [ -d "${PWD}/${node}_run" ] && rm -fr ${PWD}/${node}_run/*
  mkdir -p ${PWD}/${node}_run
  [ -d "${PWD}/${node}_logs" ] && rm -fr ${PWD}/${node}_logs/*
  mkdir -p ${PWD}/${node}_logs

  # parse Role of doris-fe naming convention: doris_fe_follower0, doris_fe_observer2 and etc.
  local role=$(echo $node | perl -lne 'print qq/\U$1\E/ if /doris_fe_(follower|observer)\d+/')
  if [ -z "${role}" ];then
    echo $(red_print "Role of doris-fe must be FOLLOWER|OBSERVER") >&2;
    exit 1;
  fi

  # bootstrap-mode: cleanup datadir of doris-fe 
  [ "x${bootstrap}x" != "xfalse" -a -d "${PWD}/${node}_data" ] && rm -fr ${PWD}/${node}_data/*
  mkdir -p ${PWD}/${node}_data

  # bootstrap-mode: doris-fe instances other than the first one should register itself to the first one.
  # ALTER SYSTEM ADD FOLLOWER|OBSERVER 'self_ip:self_port'
  # fe/bin/start_fe.sh --helper 'masterFs_ip:masterFe_port'
  local helpOption=""
  if [ "x${bootstrap}x" != "xfalsex" ] && isContainerRunning doris_fe_follower;then
    echo "Another doris_fe instances have already started, so get editlog_port via mysql"
    masterFe=$(${basedir}/mysql.sh "SHOW PROC '/frontends';" |perl -aF'\s+' -lne  'print "$F[1]:$F[3]" if /doris_fe/ && $F[8] eq qq/true/'|head -1)
    editLogPort=$(perl -lne 'print $1 if /^\s*edit_log_port\s*=\s*(\b\d+\b)/' ${PWD}/doris_fe_conf/fe.conf)
    editLogPort=${editLogPort:-9010}
    ${basedir}/mysql.sh "ALTER SYSTEM ADD ${role} '${ip}:${editLogPort}'"
    helpOption="--helper ${masterFe}"
  else
    echo "It is the first doris_fe instance or non-bootstrap startup: ${node}"
  fi

  # run docker
  docker run ${dockerFlags} ${flags} apachedoris/doris-dev:build-env-1.2 ${dorisDockerRoot}/fe/bin/start_fe.sh ${helpOption}
}

bootstrap_doris_fe(){
  start_doris_fe_args ${1:?"undefined 'node'"} "true"
}

bootstrap_all_doris_fe(){
  for node in ${doris_fe_list} ;do
    bootstrap_doris_fe ${node}
  done
}

start_doris_fe(){
  start_doris_fe_args ${1:?"undefined 'node'"} "false"
}

start_all_doris_fe(){
  for node in ${doris_fe_list} ;do
    start_doris_fe ${node}
  done
}

restart_doris_fe(){
  local node=${1:?"undefined 'doris_fe'"};shift
  stop_doris_fe ${node}
  start_doris_fe ${node}
}

restart_all_doris_fe(){
  for node in ${doris_fe_list} ;do
    restart_doris_fe ${node}
  done
}

#################################################################
## doris-be 


stop_doris_be_args(){
  local node=${1:?"missing 'node'"};shift
  local finalize=${1:-"false"}

  stop_node ${node}
  if [ "x${finalize}x" != 'xfalsex' ];then
    if isContainerRunning doris_fe_follower;then
      local ip=$(perl -aF/\\s+/ -ne "print \$F[0] if /\b$node\b/" hosts)
      local heartbeatServicePort=$(perl -lne 'print $1 if /^\s*heartbeat_service_port\s*=\s*(\b\d+\b)/' ${PWD}/doris_be_conf/be.conf)
      heartbeatServicePort=${heartbeatServicePort:-9050}
      ${basedir}/mysql.sh "ALTER SYSTEM DROP BACKEND '${ip}:${heartbeatServicePort}';"
    fi

    [ -d "${PWD}/${node}_data" ] && rm -fr ${PWD}/${node}_data/*
    mkdir -p ${PWD}/${node}_data
  fi
}

stop_doris_be(){
  stop_doris_be_args ${1:?"missing 'node'"} "false"
}

stop_all_doris_be(){
  for node in ${doris_be_list} ;do
    stop_doris_be ${node}
  done
}

destroy_doris_be(){
  stop_doris_be_args ${1:?"missing 'node'"} "true"
}

destroy_all_doris_be(){
  for node in ${doris_be_list};do
    destroy_doris_be ${node}
  done
}

start_doris_be_args(){
  local node=${1:?"missing 'node'"};shift
  local bootstrap=${1:-"false"};shift
  ip=$(perl -aF/\\s+/ -ne "print \$F[0] if /\b$node\b/" hosts)
  flags="
  -v ${PWD}/${node}_data:${dorisDockerRoot}/be/storage
  -v ${PWD}/${node}_logs:${dorisDockerRoot}/be/log
  -v ${PWD}/doris_be_conf:${dorisDockerRoot}/be/conf
  --name $node
  --hostname $node
  --ip $ip
  "

  [ -d "${PWD}/${node}_logs" ] && rm -fr ${PWD}/${node}_logs/*
  mkdir -p ${PWD}/${node}_logs

  if [ "x${bootstrap}x" != "false" ];then
    [ -d "${PWD}/${node}_data" ] && rm -fr ${PWD}/${node}_data/*
    mkdir -p ${PWD}/${node}_data
    heartbeatServicePort=$(perl -lne 'print $1 if /^\s*heartbeat_service_port\s*=\s*(\b\d+\b)/' ${PWD}/doris_be_conf/be.conf)
    heartbeatServicePort=${heartbeatServicePort:-9050}
    ${basedir}/mysql.sh "ALTER SYSTEM ADD BACKEND '${ip}:${heartbeatServicePort}';"
  fi

  docker run ${dockerFlags} ${flags} \
    apachedoris/doris-dev:build-env-1.2 \
    ${dorisDockerRoot}/be/bin/start_be.sh 
  }

bootstrap_doris_be(){
  start_doris_be_args ${1:?"missing 'node'"} "true"
}

bootstrap_all_doris_be(){
  for node in ${doris_be_list}; do
    bootstrap_doris_be ${node}
  done
}

start_doris_be(){
  start_doris_be_args ${1:?"missing 'node'"} "false"
}

start_all_doris_be(){
  for node in ${doris_be_list}; do
    start_doris_be ${node}
  done
}

restart_doris_be(){
  local node=$1;shift
  stop_node ${node}
  start_doris_be ${node}
}

restart_all_doris_be(){
  for node in ${doris_be_list}; do
    restart_doris_be ${node}
  done
}
