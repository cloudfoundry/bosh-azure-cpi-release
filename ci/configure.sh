#!/usr/bin/env bash

set -eu

FLY="${FLY_CLI:-fly}"

${FLY} -t "${CONCOURSE_TARGET:-bosh-ecosystem}" set-pipeline -p "bosh-azure-cpi" \
    -c ci/pipeline.yml \
    -v ruby_version=$(cat src/bosh_azure_cpi/.ruby-version)
