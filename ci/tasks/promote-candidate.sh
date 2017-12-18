#!/usr/bin/env bash

set -e -x

: ${S3_ACCESS_KEY_ID:?}
: ${S3_SECRET_ACCESS_KEY:?}

source bosh-cpi-src/ci/utils.sh
source /etc/profile.d/chruby.sh
chruby ${RUBY_VERSION}

# Version info
semver_version=`cat release-version-semver/number`
echo $semver_version > promoted/semver_version

cp -r bosh-cpi-src promoted/repo

dev_release=$(realpath bosh-cpi-release/*.tgz)

pushd promoted/repo > /dev/null
  echo creating config/private.yml with blobstore secrets
  cat > config/private.yml << EOF
---
blobstore:
  provider: s3
  options:
    access_key_id: ${S3_ACCESS_KEY_ID}
    secret_access_key: ${S3_SECRET_ACCESS_KEY}
EOF

  echo "finalizing CPI release..."
  bosh2 finalize-release ${dev_release} --version ${semver_version}

  rm config/private.yml

  git diff | cat
  git add .

  git config --global user.email cf-bosh-eng@pivotal.io
  git config --global user.name CI
  git commit -m "New final release v${semver_version}"
popd > /dev/null
