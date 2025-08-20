#!/usr/bin/env bash
set -eu -o pipefail

FLY="${FLY_CLI:-fly}"

${FLY} --target "${CONCOURSE_TARGET:-bosh}" \
  set-pipeline \
  --pipeline "bosh-azure-cpi" \
  --config ci/pipeline.yml
