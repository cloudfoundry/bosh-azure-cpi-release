# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'bosh_azure_cpi/cloud/azure/version'

version = Bosh::AzureCloud::VERSION

Gem::Specification.new do |spec|
  spec.name          = 'bosh_azure_cpi'
  spec.version       = version
  spec.authors       = ['Nicholas Terry']
  spec.email         = ['nick.i.terry@gmail.com']
  spec.summary       = %q{Foo}
  spec.description   = %q{Foo}
  spec.homepage      = 'https://github.com/nterry/bosh_azure_cpi'
  spec.license       = 'Apache 2.0'

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ['lib']

  spec.add_dependency 'azure', '~> 0.6.4'

  spec.add_dependency 'bosh_common',   "~>#{version}"
  spec.add_dependency 'bosh_cpi',      "~>#{version}"
  spec.add_dependency 'bosh-registry', "~>#{version}"
  spec.add_dependency 'psych'
  spec.add_dependency 'logger'
  spec.add_dependency 'httpclient'
  spec.add_dependency 'membrane'


  spec.add_development_dependency 'bundler', '~> 1.6'
  spec.add_development_dependency 'rake'
end
