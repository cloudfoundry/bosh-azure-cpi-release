# coding: utf-8
Gem::Specification.new do |s|
  s.name          = 'bosh_azure_cpi'
  s.version       = '2.0.0'
  s.platform      = Gem::Platform::RUBY
  s.authors       = ['Nicholas Terry', 'Abel Hu']
  s.email         = ['nick.i.terry@gmail.com', 'abelch@microsoft.com']
  s.summary       = 'BOSH Azure CPI'
  s.description   = 'BOSH Azure CPI'
  s.homepage      = 'https://github.com/cloudfoundry/bosh'
  s.license       = 'Apache 2.0'
  s.required_ruby_version = Gem::Requirement.new('>= 1.9.3')

  s.files         = Dir['README.md', 'lib/**/*', 'scripts/**/*'].select{ |f| File.file? f }
  s.require_path  = 'lib'
  s.bindir        = 'bin'
  s.executables   = %w(azure_cpi bosh_azure_console)

  # NOTE: the version lock-down for BOSH gems should be removed once the
  # Bosh::Cpi::RegistryClient change has propagated to "master".
  s.add_dependency 'bosh_common',   '1.3215.3.0'
  s.add_dependency 'bosh_cpi',      '1.3215.3.1'
  s.add_dependency 'azure',         '~>0.7.4'
  s.add_dependency 'vhd',           '~>0.0.4'
  s.add_dependency 'httpclient',    '=2.4.0'
end
