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

# @@logger is shared across the whole Change hierarchy; class instance variables are not inherited by subclasses.
# rubocop:disable-next Style/ClassVars
module ChefDiff
  module Changes
    # Changeset aware cookbook
    class Cookbook < Change
      attr_accessor :cookbook_dir

      # <dir>/<cookbook>/<anything> for any dir in cookbook_dirs. Where dirs
      # overlap, the first in cookbook_dirs wins: the alternation tries them
      # in order. A file directly in a dir (cookbooks/OWNERS) names nothing.
      def self.path_regexp(cookbook_dirs)
        %r{\A(#{Regexp.union(cookbook_dirs).source})/([^/]+)/}
      end

      # { cookbook_dir:, name: }, so name_from_path returns that hash too.
      def self.parts_from_match(match)
        match && { cookbook_dir: match[1], name: match[2] }
      end

      # parts is name_from_path's result when the caller has already matched
      # the files; all files of one cookbook give the same parts. Without
      # parts, the first file names the cookbook.
      # Length reflects field count plus a single status classification; not accidental complexity.
      # rubocop:disable-next Metrics/MethodLength
      def initialize(files, cookbook_dirs, parts = nil)
        super()
        @files = files
        exploded_path = parts || self.class.name_from_path(files.first[:path], cookbook_dirs)
        @cookbook_dir, @name = exploded_path.values_at(:cookbook_dir, :name)

        # The cookbook is marked for deletion only when its own top level
        # metadata.rb is deleted. A nested one, like a fixture cookbook under
        # test/fixtures/cookbooks/, is an ordinary file of this cookbook.
        # A git type change (T) shows up as a delete plus a modify of the same
        # path, and the file is still there, so a modify of metadata.rb wins.
        # Otherwise the cookbook was modified and will be re-uploaded.
        metadata = "#{@cookbook_dir}/#{@name}/metadata.rb"
        statuses = files.select { |x| x[:path] == metadata }.map { |x| x[:status] }
        @status = if statuses.include?(:deleted) && !statuses.include?(:modified)
                    :deleted
                  else
                    :modified
                  end
      end

      # Given a list of changed files, returns one Cookbook per cookbook they
      # touch, in order of first appearance. Logs one summary line at INFO.
      # Files are grouped by cookbook dir and name, so the same cookbook in
      # two dirs is two changes. Files outside any cookbook (OWNERS in a
      # cookbook dir) fall in the nil group and are dropped. The pattern is
      # compiled once per call; see Change.find for why.
      def self.find(list, cookbook_dirs, logger)
        @@logger = logger
        return [] if cookbook_dirs.nil? || list.nil? || list.empty?

        re = path_regexp(cookbook_dirs)
        changes = list
                  .group_by { |file| parts_from_match(re.match(file[:path])) }
                  .filter_map { |parts, files| new(files, cookbook_dirs, parts) if parts }
        info { "[#{self}] #{changes.size} matched in #{cookbook_dirs.join(', ')}" }
        changes
      end
    end
  end
end
