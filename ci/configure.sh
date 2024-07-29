#!/usr/bin/env bash

set -eu

FLY="${FLY_CLI:-fly}"

${FLY} -t "${CONCOURSE_TARGET:-bosh-ecosystem}" set-pipeline -p "bosh-azure-cpi" \
    -c ci/pipeline.yml
