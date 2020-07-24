#!/bin/bash
set -e -o pipefail
basedir=$(cd $(dirname $(readlink -f ${BASH_SOURCE:-$0}));pwd)
test  ${basedir} == ${PWD}
dorisLocalRoot=$(cd ${basedir}/../doris_all;pwd)
dorisDockerRoot=/root/doris

doris_fe_list=$(perl -lne 'print $1 if /^\s*\d+(?:\.\d+){3}\s+(doris_fe_(:?follower|observer)\d+)\s*$/' ${PWD}/hosts )
doris_fe_follower_list=$(perl -lne 'print $1 if /^\s*\d+(?:\.\d+){3}\s+(doris_fe_follower\d+)\s*$/' ${PWD}/hosts )
doris_fe_observer_list=$(perl -lne 'print $1 if /^\s*\d+(?:\.\d+){3}\s+(doris_fe_observer\d+)\s*$/' ${PWD}/hosts )
doris_be_list=$(perl -lne 'print $1 if /^\s*\d+(?:\.\d+){3}\s+(doris_be\d+)\s*$/' ${PWD}/hosts )
doris_hdfs_broker_list=$(perl -lne 'print $1 if /^\s*\d+(?:\.\d+){3}\s+(doris_hdfs_broker\d+)\s*$/' ${PWD}/hosts )

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
      if ${basedir}/mysql1.sh "SHOW PROC '/frontends';" | grep ${node};then
        ${basedir}/mysql1.sh "ALTER SYSTEM DROP ${role} '${ip}:${editLogPort}';"
      fi
    fi

    [ -d "${PWD}/${node}_data" ] && sudo rm -fr ${PWD}/${node}_data/*
    mkdir -p ${PWD}/${node}_data
  fi
}

stop_doris_fe(){
  stop_doris_fe_args ${1:?"missing 'node'"} "false"
}

destroy_doris_fe(){
  stop_doris_fe_args ${1:?"missing 'node'"} "true"
}

do_all(){
  local func=${1:?"missing 'func'"}
  set -- $(perl -e "print qq/\$1 \$2/ if qq/${func}/ =~ /^(\\w+)_all_(\\w+)\$/")
  local cmd=${1:?"missing 'cmd'"};shift
  local role=${1:?"missing 'role'"};shift
  local service=${role};
  if startsWith ${service} doris_fe;then
    service=doris_fe
  fi
  green_print "BEGIN: ${func}"
  for node in $(eval "echo \${${role}_list}"); do
    green_print "run: ${cmd}_${role} ${node}"
    ${cmd}_${service} ${node}
  done
  green_print "END: ${func}"
}

stop_all_doris_fe_follower(){ do_all ${FUNCNAME};}
stop_all_doris_fe_observer(){ do_all ${FUNCNAME};}
stop_all_doris_fe(){ do_all ${FUNCNAME};}

destroy_all_doris_fe_follower(){ do_all ${FUNCNAME};}
destroy_all_doris_fe_observer(){ do_all ${FUNCNAME};}
destroy_all_doris_fe(){ do_all ${FUNCNAME};}

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
  [ "x${bootstrap}x" != "xfalsex" -a -d "${PWD}/${node}_data" ] && sudo rm -fr ${PWD}/${node}_data/*
  mkdir -p ${PWD}/${node}_data

  # bootstrap-mode: doris-fe instances other than the first one should register itself to the first one.
  # ALTER SYSTEM ADD FOLLOWER|OBSERVER 'self_ip:self_port'
  # fe/bin/start_fe.sh --helper 'masterFs_ip:masterFe_port'
  local helpOption=""
  if [ "x${bootstrap}x" != "xfalsex" ] && isContainerRunning doris_fe_follower;then
    echo "Another doris_fe instances have already started, so get editlog_port via mysql"
    masterFe=$(${basedir}/mysql1.sh "SHOW PROC '/frontends';" |perl -aF'\s+' -lne  'print "$F[1]:$F[3]" if /doris_fe/ && $F[8] eq qq/true/'|head -1)
    editLogPort=$(perl -lne 'print $1 if /^\s*edit_log_port\s*=\s*(\b\d+\b)/' ${PWD}/doris_fe_conf/fe.conf)
    editLogPort=${editLogPort:-9010}
    ${basedir}/mysql1.sh "ALTER SYSTEM ADD ${role} '${ip}:${editLogPort}'"
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

bootstrap_all_doris_fe_follower(){ do_all ${FUNCNAME};}
bootstrap_all_doris_fe_observer(){ do_all ${FUNCNAME};}
bootstrap_all_doris_fe(){ do_all ${FUNCNAME};}

start_doris_fe(){
  start_doris_fe_args ${1:?"undefined 'node'"} "false"
}

start_all_doris_fe_follower(){ do_all ${FUNCNAME};}
start_all_doris_fe_observer(){ do_all ${FUNCNAME};}
start_all_doris_fe(){ do_all ${FUNCNAME};}

restart_doris_fe(){
  local node=${1:?"undefined 'doris_fe'"};shift
  stop_doris_fe ${node}
  start_doris_fe ${node}
}

restart_all_doris_fe_follower(){ do_all ${FUNCNAME};}
restart_all_doris_fe_observer(){ do_all ${FUNCNAME};}
restart_all_doris_fe(){ do_all ${FUNCNAME};}

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
      ${basedir}/mysql1.sh "ALTER SYSTEM DROPP BACKEND '${ip}:${heartbeatServicePort}';"
    fi

    [ -d "${PWD}/${node}_data" ] && sudo rm -fr ${PWD}/${node}_data/*
    mkdir -p ${PWD}/${node}_data
  fi
}

stop_doris_be(){
  stop_doris_be_args ${1:?"missing 'node'"} "false"
}

destroy_doris_be(){
  stop_doris_be_args ${1:?"missing 'node'"} "true"
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

  if [ "x${bootstrap}x" != "xfalsex" ];then
    [ -d "${PWD}/${node}_data" ] && sudo rm -fr ${PWD}/${node}_data/*
    mkdir -p ${PWD}/${node}_data
    heartbeatServicePort=$(perl -lne 'print $1 if /^\s*heartbeat_service_port\s*=\s*(\b\d+\b)/' ${PWD}/doris_be_conf/be.conf)
    heartbeatServicePort=${heartbeatServicePort:-9050}
    ${basedir}/mysql1.sh "ALTER SYSTEM ADD BACKEND '${ip}:${heartbeatServicePort}';"
  fi

  docker run ${dockerFlags} ${flags} apachedoris/doris-dev:build-env-1.2 ${dorisDockerRoot}/be/bin/start_be.sh 
}

bootstrap_doris_be(){
  start_doris_be_args ${1:?"missing 'node'"} "true"
}


start_doris_be(){
  start_doris_be_args ${1:?"missing 'node'"} "false"
}

restart_doris_be(){
  local node=$1;shift
  stop_node ${node}
  start_doris_be ${node}
}

stop_all_doris_be(){ do_all ${FUNCNAME};}
destroy_all_doris_be(){ do_all ${FUNCNAME};}
bootstrap_all_doris_be(){ do_all ${FUNCNAME};}
start_all_doris_be(){ do_all ${FUNCNAME};}
restart_all_doris_be(){ do_all ${FUNCNAME};}

#############################################################################
## doris hdfs-broker

stop_doris_hdfs_broker_args(){
  local node=${1:?"missing 'node'"};shift
  local finalize=${1:-"false"}

  stop_node ${node}
  if [ "x${finalize}x" != 'xfalsex' ];then
    if isContainerRunning doris_fe_follower;then
      local ip=$(perl -aF/\\s+/ -ne "print \$F[0] if /\b$node\b/" hosts)
      local brokerIpcPort=$(perl -lne 'print $1 if /^\s*broker_ipc_port\s*=\s*(\b\d+\b)/' ${PWD}/hdfs_broker_conf/apache_hdfs_broker.conf)
      brokerIpcPort=${brokerIpcPort:-8000}
      ${basedir}/mysql1.sh "ALTER SYSTEM DROP BROKER hdfs '${ip}:${brokerIpcPort}';"
    fi

    [ -d "${PWD}/${node}_data" ] && sudo rm -fr ${PWD}/${node}_data/*
    mkdir -p ${PWD}/${node}_data
  fi
}

start_doris_hdfs_broker_args(){
  local node=${1:?"missing 'node'"};shift
  local bootstrap=${1:-"false"};shift
  ip=$(perl -aF/\\s+/ -ne "print \$F[0] if /\b$node\b/" hosts)
  flags="
  -v ${PWD}/${node}_data:${dorisDockerRoot}/apache_hdfs_broker/data
  -v ${PWD}/${node}_logs:${dorisDockerRoot}/apache_hdfs_broker/log
  -v ${PWD}/hdfs_broker_conf:${dorisDockerRoot}/apache_hdfs_broker/conf
  --name $node
  --hostname $node
  --ip $ip
  "

  [ -d "${PWD}/${node}_logs" ] && rm -fr ${PWD}/${node}_logs/*
  mkdir -p ${PWD}/${node}_logs

  if [ "x${bootstrap}x" != "xfalsex" ];then
    [ -d "${PWD}/${node}_data" ] && sudo rm -fr ${PWD}/${node}_data/*
    mkdir -p ${PWD}/${node}_data
    brokerIpcPort=$(perl -lne 'print $1 if /^\s*broker_ipc_port\s*=\s*(\b\d+\b)/' ${PWD}/hdfs_broker_conf/apache_hdfs_broker.conf)
    brokerIpcPort=${brokerIpcPort:-8000}
    ${basedir}/mysql1.sh "ALTER SYSTEM ADD BROKER hdfs '${ip}:${brokerIpcPort}';"
  fi
  docker run ${dockerFlags} ${flags} apachedoris/doris-dev:build-env-1.2 ${dorisDockerRoot}/apache_hdfs_broker/bin/start_broker.sh 
}

stop_doris_hdfs_broker(){
  stop_doris_hdfs_broker_args ${1:?"missing 'node'"} "false"
}

destroy_doris_hdfs_broker(){
  stop_doris_hdfs_broker_args ${1:?"missing 'node'"} "true"
}

bootstrap_doris_hdfs_broker(){
  start_doris_hdfs_broker_args ${1:?"missing 'node'"} "true"
}

start_doris_hdfs_broker(){
  start_doris_hdfs_broker_args ${1:?"missing 'node'"} "false"
}

restart_doris_hdfs_broker(){
  stop_doris_hdfs_broker ${1:?"mssing 'node'"}
  start_doris_hdfs_broker $1
}

stop_all_doris_hdfs_broker(){ do_all ${FUNCNAME};}
destroy_all_doris_hdfs_broker(){ do_all ${FUNCNAME};}
bootstrap_all_doris_hdfs_broker(){ do_all ${FUNCNAME};}
start_all_doris_hdfs_broker(){ do_all ${FUNCNAME};}
restart_all_doris_hdfs_broker(){ do_all ${FUNCNAME};}

## cluster
start_doris_cluster(){
  start_all_doris_fe
  start_all_doris_be
  start_all_doris_hdfs_broker
}

stop_doris_cluster(){
  stop_all_doris_hdfs_broker
  stop_all_doris_be
  stop_all_doris_fe
}

restart_doris_cluster(){
  restart_all_doris_hdfs_broker
  restart_all_doris_be
  restart_all_doris_fe
}

bootstrap_doris_cluster(){
  stop_doris_cluster
  for fe in ${doris_fe_follower_list};do
    bootstrap_doris_fe ${fe}
    sleep 20
  done

  for fe in ${doris_fe_observer_list};do
    bootstrap_doris_fe ${fe}
  done

  sleep 5

  bootstrap_all_doris_be
  bootstrap_all_doris_hdfs_broker
}

destroy_doris_cluster(){
  destroy_all_doris_hdfs_broker
  destroy_all_doris_be
  destroy_all_doris_fe
}
