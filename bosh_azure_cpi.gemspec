# coding: utf-8
require File.expand_path('../lib/cloud/azure/version', __FILE__)

version = Bosh::AzureCloud::VERSION

Gem::Specification.new do |spec|
  spec.name          = 'bosh_azure_cpi'
  spec.version       = version
  spec.platform      = Gem::Platform::RUBY
  spec.authors       = ['Nicholas Terry', 'Abel Hu']
  spec.email         = ['nick.i.terry@gmail.com', 'abelch@microsoft.com']
  spec.summary       = 'BOSH Azure CPI'
  spec.description   = "BOSH Azure CPI\n#{`git rev-parse HEAD`[0, 6]}"
  spec.homepage      = 'https://github.com/nterry/bosh_azure_cpi'
  spec.license       = 'Apache 2.0'
  spec.required_ruby_version = Gem::Requirement.new('>= 1.9.3')

  spec.files         = `git ls-files -- bin/* lib/*`.split("\n") + %w(README.md)
  spec.require_path  = 'lib'
  spec.bindir        = 'bin'
  spec.executables   = %w(azure_cpi bosh_azure_console)

  spec.add_dependency 'azure', '~> 0.6.5'

  spec.add_dependency 'bosh_common',      "~>#{version}"
  spec.add_dependency 'bosh_cpi',         "~>#{version}"
  spec.add_dependency 'bosh-registry',    "~>#{version}"
  spec.add_dependency 'nokogiri',         "~> 1.5"
  spec.add_dependency 'vhd',              "~> 0.0.4"
  spec.add_dependency 'psych'
  spec.add_dependency 'httpclient'
end
