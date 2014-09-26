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

# rubocop:disable ClassVars
module ChefDiff
  module Changes
    # Changeset aware user
    class User < Change
      def self.name_from_path(path, user_dir)
        re = "^#{user_dir}/(([^/]+/)*)(.+)\.json"
        debug("[user] Matching #{path} against #{re}")
        m = path.match(re)
        if m
          info("Name is #{m[1]}#{m[3]}")
          return m[1], m[3]
        end
        nil
      end

      def initialize(file, user_dir)
        @status = file[:status] == :deleted ? :deleted : :modified
        @path, @name = self.class.name_from_path(file[:path], user_dir)
      end

      # Given a list of changed files
      # create a list of user objects
      def self.find(list, user_dir, logger)
        @@logger = logger
        return [] if list.nil? || list.empty?
        list.
          select { |x| self.name_from_path(x[:path], user_dir) }.
          map do |x|
            ChefDiff::Changes::User.new(x, user_dir)
          end
      end
    end
  end
end
