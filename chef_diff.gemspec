# frozen_string_literal: true

Gem::Specification.new do |s|
  s.name = 'chef_diff'
  s.version = '0.4.0'
  s.platform = Gem::Platform::RUBY
  s.summary = 'Chef Diff'
  s.description = 'Library for calculation Chef differences between revisions'
  s.authors = ['Esben S. Nielsen']
  s.homepage = 'https://github.com/One-com/chef_diff'
  s.metadata = {
    'source_code_uri' => 'https://github.com/One-com/chef_diff',
    'bug_tracker_uri' => 'https://github.com/One-com/chef_diff/issues',
    'rubygems_mfa_required' => 'true'
  }
  s.extra_rdoc_files = ['README.md', 'LICENSE']
  s.files = %w[README.md LICENSE] + Dir.glob('lib/chef_diff/*.rb') +
            Dir.glob('lib/chef_diff/{changes,repo}/*.rb') + Dir.glob('bin/*')
  s.executables = 'chef-diff'
  s.license = 'Apache-2.0'
  s.required_ruby_version = '>= 2.7'
  s.add_dependency 'json'
  s.add_dependency 'mixlib-shellout'
  s.add_development_dependency 'rake'
  s.add_development_dependency 'rspec-core'
  s.add_development_dependency 'rspec-expectations'
  s.add_development_dependency 'rspec-mocks'
  s.add_development_dependency 'rubocop'
  s.add_development_dependency 'rubocop-rspec'
  s.add_development_dependency 'simplecov'
end
