#!/bin/bash
set -e -o pipefail
cat <<'DONE' | curl --location-trusted -u test:test -H "label:table1_20170707_$now" -H "column_separator:," -T - http://${masterFe}/api/example_db/table1/_stream_load
1,1,jim,2
2,1,grace,2
3,2,tom,2
4,3,bush,3
5,3,helen,3
DONE
