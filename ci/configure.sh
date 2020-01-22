#!/usr/bin/env bash

set -eu

if [[ $(lpass status -q; echo $?) != 0 ]]; then
  echo "Login with lpass first"
  exit 1
fi

fly -t cpi set-pipeline -p "bosh-azure-cpi" \
    -c ci/pipeline.yml \
    --load-vars-from <(lpass show -G --sync=now "azure-cpi-bats-concourse-secrets" --notes)
