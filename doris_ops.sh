#!/bin/bash
set -e -o pipefail
basedir=$(cd $(dirname $(readlink -f ${BASH_SOURCE:-$0}));pwd)
test  ${basedir} == ${PWD}
dorisLocalRoot=$(cd ${basedir}/../doris_all;pwd)
dorisDockerRoot=/root/doris

doris_fe_num=$(perl -ne 'print if /^\s*\d+(\.\d+){3}\s+doris_fe\d+\s*$/' ${PWD}/hosts |wc -l);
doris_be_num=$(perl -ne 'print if /^\s*\d+(\.\d+){3}\s+doris_be\d+\s*$/' ${PWD}/hosts |wc -l);

dockerFlags="-tid --rm -u root --privileged --net static_net0 -v ${PWD}/hosts:/etc/hosts -v ${dorisLocalRoot}:${dorisDockerRoot}"

stop_node(){
  local name=$1;shift
  set +e +o pipefail
  docker kill ${name}
  docker rm ${name}
  set -e -o pipefail
}

## doris-fe

bootstrap_doris_fe(){
  local node=${1:?"undefined 'doris_fe'"};shift
  stop_node ${node}
  rm -fr ${basedir:?"undefined"}/${node}_data/*
  rm -fr ${basedir:?"undefined"}/${node}_logs/*
}

bootstrap_all_doris_fe(){
  for node in $(eval "echo doris_fe{0..$((${doris_fe_num}-1))}") ;do
    bootstrap_doris_fe ${node}
  done
}

stop_doris_fe(){
  local node=${1:?"undefined 'doris_fe'"};shift
  stop_node ${node}
}

stop_all_doris_fe(){
  for node in $(eval "echo doris_fe{0..$((${doris_fe_num}-1))}") ;do
    stop_doris_fe ${node}
  done
}

start_doris_fe(){
  local node=${1:?"undefined 'doris_fe'"};shift
	ip=$(perl -aF/\\s+/ -ne "print \$F[0] if /\b$node\b/" hosts)
  flags="
  -v ${PWD}/${node}_data:${dorisDockerRoot}/fe/doris-meta
  -v ${PWD}/${node}_logs:${dorisDockerRoot}/fe/log
  -v ${PWD}/doris_fe_conf:${dorisDockerRoot}/fe/conf
  --name $node
  --hostname $node
  --ip $ip
  "
  rm -fr ${PWD}/${node}_logs/*
  mkdir -p ${PWD}/${node}_logs
  docker run ${dockerFlags} ${flags} \
    apachedoris/doris-dev:build-env-1.2 \
    ${dorisDockerRoot}/fe/bin/start_fe.sh
}

start_all_doris_fe(){
  for node in $(eval "echo doris_fe{0..$((${doris_fe_num}-1))}") ;do
    start_doris_fe ${node}
  done
}

restart_doris_fe(){
  local node=${1:?"undefined 'doris_fe'"};shift
  stop_doris_fe ${node}
  start_doris_fe ${node}
}

restart_all_doris_fe(){
  for node in $(eval "echo doris_fe{0..$((${doris_fe_num}-1))}") ;do
    restart_doris_fe ${node}
  done
}

#################################################################
## doris-be 

bootstrap_doris_be(){
  local name=$1;shift
  stop_node ${name}
  rm -fr ${basedir:?"undefined"}/${name}_data/*
  rm -fr ${basedir:?"undefined"}/${name}_logs/*
}

bootstrap_all_doris_be(){
  for node in $(eval "echo doris_be{0..$((${doris_be_num}-1))}") ;do
    bootstrap_doris_be ${node}
  done
}

stop_doris_be(){
  local name=$1;shift
  stop_node ${name}
}

stop_all_doris_be(){
  for node in $(eval "echo doris_be{0..$((${doris_be_num}-1))}") ;do
    stop_node ${node}
  done
}

start_doris_be(){
  local name=$1;shift
	ip=$(perl -aF/\\s+/ -ne "print \$F[0] if /\b$node\b/" hosts)
  flags="
  -v ${PWD}/${node}_data:${dorisDockerRoot}/be/storage
  -v ${PWD}/${node}_logs:${dorisDockerRoot}/be/log
  -v ${PWD}/doris_be_conf:${dorisDockerRoot}/be/conf
  --name $node
  --hostname $node
  --ip $ip
  "
  rm -fr ${PWD}/${node}_logs/*
  mkdir -p ${PWD}/${node}_logs
  docker run ${dockerFlags} ${flags} \
    apachedoris/doris-dev:build-env-1.2 \
    ${dorisDockerRoot}/be/bin/start_be.sh 
}

start_all_doris_be(){
  for node in $(eval "echo doris_be{0..$((${doris_be_num}-1))}") ;do
    start_doris_be ${node}
  done
}

restart_doris_be(){
  local node=$1;shift
  stop_node ${node}
  start_doris_be ${node}
}

restart_all_doris_be(){
  for node in $(eval "echo doris_be{0..$((${doris_be_num}-1))}") ;do
    restart_doris_be ${node}
  done
}
