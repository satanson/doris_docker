#!/bin/bash
set -e -o pipefail
basedir=$(cd $(dirname $(readlink -f ${BASH_SOURCE:-$0}));pwd)
cd ${basedir}
M2_REPO=$(readlink -f ${HOME}/.m2)
docker run -it --rm --name doris_build -u root -w /root/doris --net host  \
  -v ${PWD}:/root/doris \
  -v ${M2_REPO}:/root/.m2 \
  -v ${M2_REPO}/settings.xml:/usr/share/maven/conf/settings.xml \
  apachedoris/doris-dev:build-env-1.2 \
  /bin/bash
