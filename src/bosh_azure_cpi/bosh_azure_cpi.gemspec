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

  s.add_dependency 'bosh_common'
  s.add_dependency 'bosh_cpi'
  s.add_dependency 'bosh-registry'
  s.add_dependency 'azure',         '~>0.7.3'
  s.add_dependency 'vhd',           '~>0.0.4'
  s.add_dependency 'httpclient',    '=2.4.0'
  s.add_dependency 'yajl-ruby',     '>=0.8.2'
end
