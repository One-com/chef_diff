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
require 'chef_diff/changeset'

module ChefDiff
  # Local checkout wrapper
  class Repo
    # Git provider
    # One cohesive backend for all git CLI operations; splitting to satisfy the line count would not aid readers.
    # rubocop:disable Metrics/ClassLength
    class Git < ChefDiff::Repo
      def setup
        @repo = (@repo_path if File.exist?(File.expand_path(@repo_path)))
        @bin = 'git'
      end

      def exists?
        return false unless @repo

        cmd = Mixlib::ShellOut.new(
          "#{@bin} status",
          cwd: File.expand_path(@repo_path)
        )
        cmd.run_command
        cmd.exitstatus.zero?
      end

      def head_rev
        cmd = Mixlib::ShellOut.new(
          "#{@bin} log -n 1 --pretty=format:'%H'",
          cwd: File.expand_path(@repo_path)
        )
        stdout = exec_cmd(cmd, 'Failed get git repo head ref')
        stdout.strip
      end

      def checkout(url)
        s = Mixlib::ShellOut.new(
          "#{@bin} clone --depth 1 #{url} #{@repo_path}"
        ).run_command
        s.error!
        @repo = @repo_path
      end

      # Return files changed between two revisions
      # Rescue block with per-line error logging pushes this over the default limit.
      # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
      def changes(start_ref, end_ref)
        check_refs(start_ref, end_ref)
        s = Mixlib::ShellOut.new(
          "#{@bin} diff --name-status #{start_ref} #{end_ref}",
          cwd: File.expand_path(@repo_path)
        )
        s.run_command.error!
        begin
          files_changed = parse_status(s.stdout).compact
          files_changed.reject { |x| skip_marked?(x[:path]) }
        rescue StandardError => e
          # We've seen some weird non-reproducible failures here
          @logger.error(
            'Something went wrong. Please report this output.'
          )
          @logger.error(e)
          s.stdout.lines.each do |line|
            @logger.error(line.strip)
          end
          exit(1)
        end
      end
      # rubocop:enable Metrics/MethodLength, Metrics/AbcSize

      def update
        cmd = Mixlib::ShellOut.new(
          "#{@bin} pull --rebase 2>&1", cwd: File.expand_path(@repo_path)
        )
        cmd.run_command
        if cmd.exitstatus != 0
          @logger.error('Something went wrong with git pull!')
          @logger.error(cmd.stdout)
          raise
        end
        cmd.stdout
      end

      # Return all files
      def files
        cmd = Mixlib::ShellOut.new(
          "#{@bin} ls-files -v .",
          cwd: File.expand_path(@repo_path)
        )
        stdout = exec_cmd(cmd, 'Failed get git repo files')
        item_list = stdout.split("\n")
        valid_items = item_list.reject { |x| x.start_with?('S') }
        valid_files = valid_items.map { |x| x.split.last }
        valid_files.map { |x| { path: x, status: :created } }
      end

      # Inline error-check with logging pushes this over the default limit.
      # rubocop:disable Metrics/MethodLength
      def status
        cmd = Mixlib::ShellOut.new(
          "#{@bin} status --porcelain 2>&1",
          cwd: File.expand_path(@repo_path)
        )
        cmd.run_command
        if cmd.exitstatus != 0
          @logger.error('Something went wrong with git status!')
          @logger.error(cmd.stdout)
          raise
        end
        cmd.stdout
      end
      # rubocop:enable Metrics/MethodLength

      private

      def check_refs(start_ref, end_ref)
        raise Changeset::ReferenceError unless ref_exists?(start_ref)

        return if end_ref.nil? || end_ref == 'HEAD'
        raise Changeset::ReferenceError unless ref_exists?(end_ref)
      end

      def skip_marked?(filepath)
        cmd = Mixlib::ShellOut.new(
          "#{@bin} ls-files -v #{filepath}",
          cwd: File.expand_path(@repo_path)
        )
        stdout = exec_cmd(cmd, 'Failed to check if file should be skipped.')
        /^S\s+(\S+)$/.match(stdout)
      end

      def ref_exists?(ref)
        cmd = Mixlib::ShellOut.new(
          "#{@bin} cat-file -t  #{ref}",
          cwd: File.expand_path(@repo_path)
        )
        cmd.run_command
        cmd.exitstatus.zero?
      end

      # Rescue block with per-line error logging pushes this over the default limit.
      # rubocop:disable Metrics/MethodLength
      def exec_cmd(cmd, fail_message)
        cmd.run_command.error!
        cmd.stdout
      rescue StandardError => e
        @logger.error(
          fail_message
        )
        @logger.error(e.to_s)
        cmd.stdout.lines.each do |line|
          @logger.error(line.strip)
        end
        raise
      end
      # rubocop:enable Metrics/MethodLength

      # Exhaustive case table for git diff-status codes; keeping all codes together reads more clearly than splitting.
      # rubocop:disable Metrics/MethodLength, Metrics/BlockLength, Metrics/CyclomaticComplexity, Style/MultilineBlockChain
      def parse_status(changes)
        # man git-diff-files
        # Possible status letters are:
        #
        # A: addition of a file
        # C: copy of a file into a new one
        # D: deletion of a file
        # M: modification of the contents or mode of a file
        # R: renaming of a file
        # T: change in the type of the file
        # U: file is unmerged (you must complete the merge before it can
        #    be committed)
        # X: "unknown" change type (most probably a bug, please report it)

        changes.lines.map do |line|
          case line
          when /^A\s+(\S+)$/, /^M(?:\d*)\s+(\S+)$/
            # A path           -> addition of a file
            # M<numbers> path  -> modification of a file
            {
              status: :modified,
              path: Regexp.last_match(1)
            }
          when /^C(?:\d*)\s+(\S+)\s+(\S+)/
            # C<numbers> path1 path2
            {
              status: :modified,
              path: Regexp.last_match(2)
            }
          when /^D\s+(\S+)$/
            # D path
            {
              status: :deleted,
              path: Regexp.last_match(1)
            }
          when /^R(?:\d*)\s+(\S+)\s+(\S+)/
            # R<numbers> path1 path2
            [
              {
                status: :deleted,
                path: Regexp.last_match(1)
              },
              {
                status: :modified,
                path: Regexp.last_match(2)
              }
            ]
          when /^T\s+(\S+)$/
            # T path
            [
              {
                status: :deleted,
                path: Regexp.last_match(1)
              },
              {
                status: :modified,
                path: Regexp.last_match(1)
              }
            ]
          else
            raise 'No match'
          end
        end.flatten.map do |x|
          {
            status: x[:status],
            path: x[:path].sub("#{@repo_path}/", '')
          }
        end
      end
      # rubocop:enable Metrics/MethodLength, Metrics/BlockLength, Metrics/CyclomaticComplexity, Style/MultilineBlockChain
    end
    # rubocop:enable Metrics/ClassLength
  end
end
