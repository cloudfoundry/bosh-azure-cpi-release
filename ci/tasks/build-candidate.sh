#!/usr/bin/env bash

set -e

pushd bosh-cpi-src > /dev/null
  cpi_release_name="bosh-azure-cpi"

  echo "building CPI release..."
  bosh create-release --name $cpi_release_name --tarball ../cpi-release/$cpi_release_name-dev.tgz
popd > /dev/null
