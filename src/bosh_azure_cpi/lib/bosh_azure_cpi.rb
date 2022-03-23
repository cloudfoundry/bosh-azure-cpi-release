# frozen_string_literal: true

require 'cloud/azure'

require 'monkey_patches/uri_monkey_patch'
Bosh::AzureCloud::URIMonkeyPatch.apply_patch
