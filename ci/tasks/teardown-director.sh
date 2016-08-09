#!/usr/bin/env bash

set -e

: ${BOSH_INIT_LOG_LEVEL:?}

source /etc/profile.d/chruby.sh
chruby ${RUBY_VERSION}

# inputs
input_dir=$(realpath director-state/)

if [ ! -e "${input_dir}/director-state.json" ]; then
  echo "director-state.json does not exist, skipping..."
  exit 0
fi

if [ -d "${input_dir}/.bosh_init" ]; then
  # reuse compiled packages
  cp -r ${input_dir}/.bosh_init ${HOME}/
fi
bosh_init=$(realpath bosh-init/bosh-init-*)
chmod +x ${bosh_init}

echo "using bosh CLI version..."
bosh -v

echo "using bosh-init CLI version..."
${bosh_init} version

logfile=$(mktemp /tmp/bosh-init-log.XXXXXX)

pushd ${input_dir} > /dev/null
  # configuration
  source director.env
  : ${BOSH_DIRECTOR_IP:?}
  : ${BOSH_DIRECTOR_USERNAME:?}
  : ${BOSH_DIRECTOR_PASSWORD:?}

  # Don't exit on failure to target the BOSH director
  set +e
    # teardown deployments against BOSH Director
    time bosh -n target ${BOSH_DIRECTOR_IP}
    time bosh login ${BOSH_DIRECTOR_USERNAME} ${BOSH_DIRECTOR_PASSWORD}

    time bosh -n cleanup --all
  set -e

  echo "deleting existing BOSH Director VM..."
  BOSH_INIT_LOG_PATH="${logfile}" BOSH_INIT_LOG_LEVEL="${BOSH_INIT_LOG_LEVEL}" ${bosh_init} delete director.yml
popd > /dev/null