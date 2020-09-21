#!/bin/bash
set -e -o pipefail
basedir=$(cd $(dirname $(readlink -f ${BASH_SOURCE:-$0}));pwd)
cd ${basedir}
M2_REPO=$(readlink -f ${HOME}/.m2)

CMD="/bin/bash"
if [ $# -ge 1 ];then
  CMD="/bin/bash -c $(echo $@)"
fi
BeCMakeListsTxt=$(readlink -f ${PWD}/../be_CMakeLists.txt)
docker run -it --privileged --rm --name doris_build -u grakra -w ${PWD} --net host  \
  -v ${PWD}:${PWD} \
  -v ${BeCMakeListsTxt}:${PWD}/be/CMakeLists.txt \
  -v ${M2_REPO}:/${USER}/.m2 \
  -v ${M2_REPO}/settings.xml:/usr/share/maven/conf/settings.xml \
  apachedoris/doris-dev-grakra:build-env-1.2 \
  ${CMD}
