#!/usr/bin/env bash

set -e

source bosh-cpi-src/ci/utils.sh
source /etc/profile.d/chruby.sh
chruby ${RUBY_VERSION}

semver=`cat version-semver/number`

pushd bosh-cpi-src > /dev/null
  echo "running unit tests"
  pushd src/bosh_azure_cpi > /dev/null
    bundle install
    bundle exec rspec spec/unit/*
  popd > /dev/null

  cpi_release_name="bosh-azure-cpi"

  echo "building CPI release..."
  bosh2 create-release --name $cpi_release_name --version $semver --tarball ../candidate/$cpi_release_name-$semver.tgz
popd > /dev/null
