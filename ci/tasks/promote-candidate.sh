#!/usr/bin/env bash

set -e -x

source bosh-cpi-release/ci/tasks/utils.sh

cd bosh-cpi-release

source /etc/profile.d/chruby.sh
chruby 2.1.2

set +x
echo creating config/private.yml with blobstore secrets
cat > config/private.yml << EOF
---
blobstore:
  s3:
    access_key_id: $aws_access_key_id
    secret_access_key: $aws_secret_access_key
EOF
set -x

echo "using bosh CLI version..."
bosh version

echo "finalizing CPI release..."
bosh finalize release ../bosh-cpi-dev-artifacts/*.tgz

rm config/private.yml

version=`git diff releases/*/index.yml | grep -E "^\+.+version" | sed s/[^0-9]*//g`
git diff | cat
git add .

git config --global user.email cf-bosh-eng@pivotal.io
git config --global user.name CI
git commit -m "New final release v $version"
