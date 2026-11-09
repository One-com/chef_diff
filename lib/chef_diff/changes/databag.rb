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

module ChefDiff
  module Changes
    # Changeset aware databag
    class Databag < Change
      attr_accessor :item

      # dir/<databag>/<item>.json, exactly one level below dir.
      def self.path_regexp(dir)
        dir && %r{\A#{Regexp.escape(dir)}/([^/]+)/([^/]+)\.json\z}
      end

      # [databag, item], so name_from_path returns that pair too.
      def self.parts_from_match(match)
        match && [match[1], match[2]]
      end

      # parts is [databag, item] when the caller has already matched the path.
      def initialize(file, databag_dir, parts = nil)
        super()
        @status = self.class.change_status(file[:status])
        @name, @item = parts || self.class.name_from_path(file[:path], databag_dir)
        debug { "[#{self.class}] #{file[:path]} is #{@name} item #{@item}" }
      end
    end
  end
end
