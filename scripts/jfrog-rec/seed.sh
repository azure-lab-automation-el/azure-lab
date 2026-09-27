#!/usr/bin/env bash
# Demo data only, on a throwaway runner-local OSS container: one sample repo with one file (user approved 08:40).
set -uo pipefail
A="admin:password"; U=http://localhost:8082/artifactory; R=demo-generic-local
code() { curl -s -o /tmp/seed.out -w '%{http_code}' -u $A "$@"; }
c=$(code -X PUT "$U/api/repositories/$R" -H 'Content-Type: application/json' -d '{"key":"'$R'","rclass":"local","packageType":"generic"}'); echo "create REST=$c $(head -c 200 /tmp/seed.out)"
if [ "$c" != 200 ]; then
  printf 'localRepositories:\n  %s:\n    type: generic\n    repoLayout: simple-default\n' $R > /tmp/repo.yml
  c=$(code -X PATCH "$U/api/system/configuration" -H 'Content-Type: application/yaml' --data-binary @/tmp/repo.yml); echo "create YAML=$c $(head -c 200 /tmp/seed.out)"
fi
echo "hello from the JFrog lesson demo" > hello-1.0.0.txt
c=$(code -T hello-1.0.0.txt "$U/$R/app/1.0.0/hello-1.0.0.txt"); echo "upload=$c"
c=$(code "$U/api/storage/$R/app/1.0.0/hello-1.0.0.txt"); echo "verify=$c"
[ "$c" = 200 ] && echo SEED_OK || { echo SEED_FAILED; exit 1; }
