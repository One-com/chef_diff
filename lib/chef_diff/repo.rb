# frozen_string_literal: true

# vim: syntax=ruby:expandtab:shiftwidth=2:softtabstop=2:tabstop=2

# Copyright 2013-2014 Facebook
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

require 'mixlib/shellout'

module ChefDiff
  # Local checkout wrapper
  class Repo
    attr_reader :repo_path
    attr_writer :bin

    def initialize(repo_path, logger)
      @repo_path = repo_path
      @logger = logger
      @repo = nil
      @bin = nil
      setup
    end

    def self.get(type, repo_path, logger)
      case type
      when 'svn'
        require 'chef_diff/repo/svn'
        ChefDiff::Repo::Svn.new(repo_path, logger)
      when 'git'
        require 'chef_diff/repo/git'
        ChefDiff::Repo::Git.new(repo_path, logger)
      else
        raise "Do not know repo type #{type}"
      end
    end

    def exists?
      raise 'Not implemented'
    end

    def status
      raise 'Not implemented'
    end

    def setup
      raise 'Not implemented'
    end

    def head_rev
      raise 'Not implemented'
    end

    def head_msg
      raise 'Not implemented'
    end

    def head_msg=
      raise 'Not implemented'
    end

    def head_parents
      raise 'Not implemented'
    end

    def latest_revision
      raise 'Not implemented'
    end

    def create(_url)
      raise 'Not implemented'
    end

    # Return files changed between two revisions
    def changes(_start_ref, _end_ref)
      raise 'Not implemented'
    end

    def update
      raise 'Not implemented'
    end

    # Return all files
    def files
      raise 'Not implemented'
    end

    def head
      raise 'Not implemented'
    end

    def checkout
      raise 'Not implemented'
    end

    def last_author
      raise 'Not implemented'
    end

    def last_msg
      raise 'Not implemented'
    end

    def last_msg=
      raise 'Not implemented'
    end
  end
end
