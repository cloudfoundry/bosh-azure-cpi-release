#!/usr/bin/env bash

set -e

source /etc/profile.d/chruby.sh
chruby ${RUBY_VERSION}

semver=`cat version-semver/number`

mkdir out

cd bosh-cpi-release

echo "running unit tests"
pushd src/bosh_azure_cpi
  bundle install
  bundle exec rspec spec/unit/*
popd

echo "using bosh CLI version..."
bosh version

cpi_release_name="bosh-azure-cpi"

echo "building CPI release..."
bosh create release --name $cpi_release_name --version $semver --with-tarball

mv dev_releases/$cpi_release_name/$cpi_release_name-$semver.tgz ../out/
