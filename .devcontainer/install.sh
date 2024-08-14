#!/bin/bash

set -e

direnv allow

(
  cd src/bosh_azure_cpi

  bundle config set --local path vendor/package
  bundle config set --local with "development:test"
  bundle install
)