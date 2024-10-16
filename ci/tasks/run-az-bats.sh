#!/usr/bin/env bash

set -e

: ${INFRASTRUCTURE:?}
: ${STEMCELL_NAME:?}
: ${BAT_INFRASTRUCTURE:?}
: ${BAT_RSPEC_FLAGS:?}
: ${AZURE_BATS_ZONE:?}

source pipelines/shared/utils.sh

metadata="$( cat environment/metadata )"
mkdir -p bats-config
bosh int bosh-cpi-src/ci/tasks/az-bats-spec.yml \
  -v "stemcell_name=${STEMCELL_NAME}" \
  -v "availability_zone=${AZURE_BATS_ZONE}"  \
  -v "ssh_private_key=$( creds_path /jumpbox_ssh/private_key )" \
  -v "ssh_public_key=$( creds_path /jumpbox_ssh/public_key )" \
  -l environment/metadata > bats-config/bats-config.yml

source director-state/director.env
export BAT_STEMCELL=$(realpath stemcell/*.tgz)
export BAT_DEPLOYMENT_SPEC=$(realpath bats-config/bats-config.yml)
export BAT_BOSH_CLI=$(which bosh)

pushd bats
  bundle install
  bundle exec rspec spec $BAT_RSPEC_FLAGS
popd
