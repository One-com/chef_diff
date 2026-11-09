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

# @@logger/@@path shared across the Change hierarchy; class instance variables are not inherited by subclasses.
# rubocop:disable-next Style/ClassVars
module ChefDiff
  # A set of classes that represent a given item's change (a cookbook
  # that's changed, a role that's changed or a databag item that's changed).
  #
  # You almost certainly don't want to use this directly, and instead want
  # ChefDiff::Changeset
  module Changes
    # Common functionality
    class Change
      @@logger = nil
      @@path = nil

      attr_accessor :path, :name, :status

      def to_s
        full_name
      end

      def full_name
        @path.to_s + @name
      end

      # People who use us through find() can just pass in logger,
      # for everyone else, here's a setter
      def logger=(log)
        @@logger = log
      end

      # Log helpers. Pass a block instead of a String where building the
      # message costs something: a ::Logger only calls it when the level is
      # on. The logger must therefore follow ::Logger's block convention.
      def self.info(msg = nil, &block)
        @@logger&.info(msg, &block)
      end

      def self.debug(msg = nil, &block)
        @@logger&.debug(msg, &block)
      end

      def info(msg = nil, &block)
        ChefDiff::Changes::Change.info(msg, &block)
      end

      def debug(msg = nil, &block)
        ChefDiff::Changes::Change.debug(msg, &block)
      end

      # Given a list of changed files, returns an object of this kind for
      # each one under dir, in list order. Logs one summary line at INFO.
      # Cookbook overrides this: one cookbook spans many files.
      #
      # Subclasses define their path shape with two class methods, also used
      # by name_from_path: path_regexp(dir) returns the anchored pattern for
      # dir (nil for a nil dir), and parts_from_match(match) turns its
      # MatchData into the constructor's parts (nil for no match).
      #
      # The pattern is compiled once per call, and the parts are handed to
      # new(file, dir, parts) so the constructor doesn't match again. On a
      # full repo listing (start_ref nil), per-path compiling and double
      # matching would dominate the run.
      def self.find(list, dir, logger)
        @@logger = logger
        re = path_regexp(dir)
        return [] if re.nil? || list.nil? || list.empty?

        changes = list.filter_map do |file|
          parts = parts_from_match(re.match(file[:path]))
          new(file, dir, parts) if parts
        end
        info { "[#{self}] #{changes.size} matched in #{dir}" }
        changes
      end

      # The status of a change built from one file: :deleted when the file
      # is gone, else :modified, so callers that select :modified also get
      # the :created entries of a full scan. Cookbook has its own rule: one
      # cookbook spans many files.
      def self.change_status(file_status)
        file_status == :deleted ? :deleted : :modified
      end

      # The parts for path, or nil when it doesn't name an object in dir.
      def self.name_from_path(path, dir)
        re = path_regexp(dir)
        debug { "[#{self}] Matching #{path} against #{re.inspect}" }
        parts_from_match(re&.match(path))
      end
    end

    # Common functionality for changes in single json file objects.
    class ChangeSingleFile < Change
      # parts is [subdir, name] when the caller has already matched the path.
      def initialize(file, dir, parts = nil)
        super()
        @status = self.class.change_status(file[:status])
        @path, @name = parts || self.class.name_from_path(file[:path], dir)
        # Not full_name: name is nil when file[:path] lies outside dir.
        debug { "[#{self.class}] #{file[:path]} is #{@path}#{@name}" }
      end
    end

    # Changes in flat chef dirs for single files
    class ChangeSingleFileFlat < ChangeSingleFile
      # dir/<name>.json, where name may contain slashes but not end in one,
      # so a bare ".json" in a subdir names nothing.
      def self.path_regexp(dir)
        dir && %r{\A#{Regexp.escape(dir)}/(.*[^/])\.json\z}
      end

      def self.parts_from_match(match)
        match && [nil, match[1]]
      end
    end

    # Changes in chef dirs allowing sub dirs for single files
    class ChangeSingleFileNested < ChangeSingleFile
      # dir/[<segment>/...]<name>.json, where name is the non-empty basename.
      def self.path_regexp(dir)
        dir && %r{\A#{Regexp.escape(dir)}/((?:[^/]+/)*)([^/]+)\.json\z}
      end

      def self.parts_from_match(match)
        match && [match[1], match[2]]
      end
    end
  end
end
