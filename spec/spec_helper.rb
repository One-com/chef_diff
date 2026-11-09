# frozen_string_literal: true

# vim: syntax=ruby:expandtab:shiftwidth=2:softtabstop=2:tabstop=2

# Copyright 2014-present One.com
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'simplecov'
SimpleCov.start do
  add_filter '/spec/'
  enable_coverage :branch
end

Dir[File.expand_path('support/**/*.rb', __dir__)].sort.each { |f| require f }

# Specs build throwaway repositories with real git. Run from a git hook, an
# inherited GIT_DIR would aim those commands at the project's own repository.
# With TMPDIR inside a checkout, git would find that checkout above a temp
# directory that a spec means to be outside any repository.
ENV.delete_if { |name, _value| name.start_with?('GIT_') }
ENV['GIT_CEILING_DIRECTORIES'] = Dir.tmpdir
