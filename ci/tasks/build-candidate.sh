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
    # AZURE_STORAGE_ACCOUNT and AZURE_STORAGE_ACCESS_KEY are specified fake values as a workaround
    # to make sure Azure::Storage::Client is mocked successfully in unit tests.
    # After https://github.com/Azure/azure-storage-ruby/issues/87 is resolved, they can be removed.
    # echo "bar" | base64 => YmFyCg==
    AZURE_STORAGE_ACCOUNT="foo" AZURE_STORAGE_ACCESS_KEY="YmFyCg==" bundle exec rspec spec/unit/*
  popd > /dev/null

  cpi_release_name="bosh-azure-cpi"

  echo "building CPI release..."
  bosh2 create-release --name $cpi_release_name --version $semver --tarball ../candidate/$cpi_release_name-$semver.tgz
popd > /dev/null
