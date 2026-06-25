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
# rubocop:disable Style/ClassVars
module ChefDiff
  module Changes
    # Changeset aware cookbook
    class Cookbook < Change
      attr_accessor :cookbook_dir

      def self.meaningful_cookbook_file?(path, cookbook_dirs)
        cookbook_dirs.each do |dir|
          re = %r{^#{dir}/([^/]+)/.*}
          m = path.match(re)
          debug("[cookbook] #{path} meaningful? [#{re}]: #{m}")
          return true if m
        end
        false
      end

      # Multiple early returns across cookbook_dirs iterations resist clean extraction into a helper.
      # rubocop:disable Metrics/MethodLength
      def self.explode_path(path, cookbook_dirs)
        cookbook_dirs.each do |dir|
          re = %r{^#{dir}/([^/]+)/.*}
          debug("[cookbook] Matching #{path} against ^#{re}")
          m = path.match(re)
          next unless m

          info("Cookbook is #{m[1]}")
          return {
            cookbook_dir: dir,
            name: m[1]
          }
        end
        nil
      end
      # rubocop:enable Metrics/MethodLength

      # Length reflects field count plus a single status classification; not accidental complexity.
      # rubocop:disable Metrics/MethodLength
      def initialize(files, cookbook_dirs)
        super()
        @files = files
        exploded_path = self.class.explode_path(
          files.sample[:path],
          cookbook_dirs
        )
        @name = exploded_path[:name]
        @cookbook_dir = exploded_path[:cookbook_dir]

        # if metadata.rb is being deleted
        #   cookbook is marked for deletion
        # otherwise it was modified
        #   and will be re-uploaded
        @status = if files
                     .select { |x| x[:status] == :deleted }
                     .map { |x| x[:path].match(%(.*metadata.rb$)) }
                     .compact
                     .any?
                    :deleted
                  else
                    :modified
                  end
      end
      # rubocop:enable Metrics/MethodLength

      # Single group_by+map pipeline; nested conditions cannot be extracted without inverting data flow.
      # rubocop:disable Metrics/MethodLength, Metrics/CyclomaticComplexity
      def self.find(list, cookbook_dirs, logger)
        @@logger = logger
        return [] if list.nil? || list.empty?

        # Single group_by→map pipeline; an intermediate variable adds noise without clarity.
        # rubocop:disable Style/MultilineBlockChain
        list
          .group_by do |x|
          # Group by prefix of cookbok_dir + cookbook_name
          # so that we treat deletes and modifications across
          # two locations separately
          g = explode_path(x[:path], cookbook_dirs)
          "#{g[:cookbook_dir]}/#{g[:name]}" if g
        end
          .map do |_, change|
            # Confirm we're dealing with a cookbook
            # Changes to OWNERS or other stuff that might end up
            # in [core, other, secure] dirs are ignored
            is_cookbook = change.any? do |c|
              meaningful_cookbook_file?(c[:path], cookbook_dirs)
            end
            ChefDiff::Changes::Cookbook.new(change, cookbook_dirs) if is_cookbook
          end.compact
        # rubocop:enable Style/MultilineBlockChain
      end
      # rubocop:enable Metrics/MethodLength, Metrics/CyclomaticComplexity
    end
  end
end
# rubocop:enable Style/ClassVars
