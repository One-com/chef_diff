# Encoding: utf-8
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

      def self.info(msg)
        @@logger.info(msg) if @@logger
      end

      def self.debug(msg)
        @@logger.debug(msg) if @@logger
      end

      def info(msg)
        ChefDiff::Changes::Change.info(msg)
      end

      def debug(msg)
        ChefDiff::Changes::Change.debug(msg)
      end
    end

    # Common functionality for changes in single json file objects
    class ChangeSingleFile < Change
      def initialize(file, dir)
        @status = file[:status] == :deleted ? :deleted : :modified
        @path, @name = self.class.name_from_path(file[:path], dir)
      end

      # Given a list of changed files
      # create a list of Role objects
      def self.find_class(list, dir, logger, klass)
        @@logger = logger
        return [] if list.nil? || list.empty?
        list
          .select { |x| name_from_path(x[:path], dir) }
          .map do |x|
            klass.new(x, dir)
          end
      end
    end

    # Changes in flat chef dirs for single files
    class ChangeSingleFileFlat < ChangeSingleFile
      def self.name_from_path_type(path, dir, chef_type)
        re = "^#{dir}\/(.+)\.json$"
        debug("[#{chef_type}] Matching #{path} against #{re}")
        m = path.match(re)
        if m
          info("Name is #{m[1]}")
          return nil, m[1]
        end
        nil
      end
    end

    # Changes in chef dirs allowing sub dirs for single files
    class ChangeSingleFileNested < ChangeSingleFile
      def self.name_from_path_type(path, dir, chef_type)
        re = "^#{dir}/(([^/]+/)*)(.+)\.json$"
        debug("[[#{chef_type}] Matching #{path} against #{re}")
        m = path.match(re)
        if m
          info("Name is #{m[1]}#{m[3]}")
          return m[1], m[3]
        end
        nil
      end
    end
  end
end
