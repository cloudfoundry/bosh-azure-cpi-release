#!/usr/bin/env bash

# Oportunistically configure bosh for use
configure_bosh_cli() {
  local bosh_input="$(realpath bosh-cli/*bosh-cli-* 2>/dev/null || true)"
  if [[ -n "${bosh_input}" ]]; then
    export bosh_cli="/usr/local/bin/bosh"
    cp "${bosh_input}" "${bosh_cli}"
    chmod +x "${bosh_cli}"
  fi
}
configure_bosh_cli
