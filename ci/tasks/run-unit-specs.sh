#!/usr/bin/env bash
set -eu -o pipefail

RUBY_VERSION=$(cat bosh-cpi-src/src/bosh_azure_cpi/.ruby-version)
source /etc/profile.d/chruby.sh
chruby "${RUBY_VERSION}"

pushd bosh-cpi-src/src/bosh_azure_cpi

  bundle install

  bundle exec rake rubocop

  bundle exec rake spec:unit

popd
