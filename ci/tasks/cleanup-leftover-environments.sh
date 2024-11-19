#!/usr/bin/env bash

set -eux -o pipefail

GOBIN=/usr/local/bin/ go install github.com/genevieve/leftovers/cmd/leftovers@latest

leftovers -n -i azure -f azurecpi
