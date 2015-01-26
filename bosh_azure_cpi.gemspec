# coding: utf-8
require File.expand_path('../lib/cloud/azure/version', __FILE__)

version = Bosh::AzureCloud::VERSION

Gem::Specification.new do |spec|
  spec.name          = 'bosh_azure_cpi'
  spec.version       = version
  spec.authors       = ['Nicholas Terry', 'Abel Hu']
  spec.email         = ['nick.i.terry@gmail.com', 'abelch@microsoft.com']
  spec.summary       = %q{Foo}
  spec.description   = %q{Foo}
  spec.homepage      = 'https://github.com/nterry/bosh_azure_cpi'
  spec.license       = 'Apache 2.0'

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ['lib']

  spec.add_dependency 'azure', '~> 0.6.5'

  spec.add_dependency 'bosh_common',      "~>#{version}"
  spec.add_dependency 'bosh_cpi',         "~>#{version}"
  spec.add_dependency 'bosh-registry',    "~>#{version}"
  spec.add_dependency 'nokogiri',         "~> 1.5"
  spec.add_dependency 'vhd',              "~> 0.0.4"
  spec.add_dependency 'psych'
  spec.add_dependency 'httpclient'
  spec.add_dependency 'membrane'


  spec.add_development_dependency 'bundler', '~> 1.6'
  spec.add_development_dependency 'rake'
end
