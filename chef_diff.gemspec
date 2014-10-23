Gem::Specification.new do |s|
  s.name = 'chef_diff'
  s.version = '0.1.2'
  s.platform = Gem::Platform::RUBY
  s.extra_rdoc_files = ['README.md', 'LICENSE']
  s.summary = 'Chef Diff'
  s.description = 'Library for calculation Chef differences between revisions'
  s.authors = ['Esben S. Nielsen']
  s.files = %w{README.md LICENSE} + Dir.glob('lib/chef_diff/*.rb') +
    Dir.glob('lib/chef_diff/{changes,repo}/*.rb') + Dir.glob('bin/*')
  s.executables = 'chef-diff'
  s.license = 'Apache'
  %w{
    json
    mixlib-shellout
    rugged
  }.each do |dep|
    s.add_dependency dep
  end
  %w{
    rspec-core
    rspec-expectations
    rspec-mocks
  }.each do |dep|
    s.add_development_dependency dep
  end
end
