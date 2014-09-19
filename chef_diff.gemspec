Gem::Specification.new do |s|
  s.name = 'chef_diff'
  s.version = '0.0.1'
  s.homepage = 'https://github.com/facebook/between-meals'
  s.platform = Gem::Platform::RUBY
  s.extra_rdoc_files = ['README.md', 'LICENSE']
  s.summary = 'Between Meals'
  s.description = 'Library for calculation Chef differences between revisions'
  s.authors = ['Phil Dibowitz', 'Marcin Sawicki']
  s.files = %w{README.md LICENSE} + Dir.glob('lib/chef_diff/*.rb') +
    Dir.glob('lib/chef_diff/{changes,repo}/*.rb')
  s.license = 'Apache'
  %w{
    colorize
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
