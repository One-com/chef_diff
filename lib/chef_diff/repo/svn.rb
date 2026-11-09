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

require 'chef_diff/repo'
require 'chef_diff/changeset'
require 'mixlib/shellout'

module ChefDiff
  # Local checkout wrapper
  class Repo
    # SVN implementation
    #
    # Every command in this class is an argv Array, never a shell string:
    # refs, URLs and @repo_path come from users and config, and a shell
    # would run `1; rm -rf ~` or split a path with a space. `--` ends
    # option parsing so a URL or path starting with `-` stays positional.
    # Commands that act on the checkout get it as #target, never as
    # @repo_path itself; the checkout's own path on disk is #local_path.
    class Svn < ChefDiff::Repo
      def setup
        @bin = 'svn'
      end

      def exists?
        # this should be better
        Dir.exist?(@repo_path)
      end

      # Revision that last changed the checkout, as a String; nil when
      # `svn info` prints no such line.
      def head_rev
        info_number(info, 'Last Changed Rev')
      end

      # Revision the checkout is at, as a String; nil when `svn info`
      # prints no such line.
      def latest_revision
        info_number(info, 'Revision')
      end

      def checkout(url)
        s = Mixlib::ShellOut.new(
          [@bin, 'co', '--ignore-externals', '--', url, local_path]
        ).run_command
        s.error!
      end

      # Return files changed between two revisions. Without end_ref, svn
      # diffs start_ref against the working copy, as Git#changes does. Refs
      # may be Strings or Integers: svn revisions are numbers.
      def changes(start_ref, end_ref)
        check_refs(start_ref, end_ref)
        range = end_ref ? "#{start_ref}:#{end_ref}" : start_ref.to_s
        s = Mixlib::ShellOut.new(
          [@bin, 'diff', '-r', range, '--summarize', '--', target]
        )
        s.run_command.error!
        @logger.info("Diff between #{start_ref} and #{end_ref}")
        summary_entries(s.stdout)
      end

      def update
        cleanup
        revert
        up
      end

      # Return all files
      def files
        s = Mixlib::ShellOut.new([@bin, 'ls', '--depth', 'infinity', '--', target])
        s.run_command
        s.error!
        s.stdout.split("\n").map do |x|
          { path: x, status: :created }
        end
      end

      private

      # @repo_path with a leading `~` or `~user` expanded. Repo paths such as
      # `~/chef` mean what a shell makes of them, but svn and the cwd of a
      # command take `~` literally. An unknown user or a HOME that is not
      # absolute leaves the path as given.
      def local_path
        return @repo_path unless @repo_path.start_with?('~')

        File.expand_path(@repo_path)
      rescue ArgumentError
        @repo_path
      end

      # #local_path as an svn target. svn reads the text after the last `@` of
      # a target as a peg revision, so `/srv/chef@prod` would mean
      # `/srv/chef` at revision `prod`; a trailing `@` is an empty peg that
      # svn strips. Not for `checkout`'s destination, which svn takes
      # literally: there the `@` would end up in the directory name.
      def target
        "#{local_path}@"
      end

      # Runs `svn <args> -- <target>`; raises when it fails.
      def run(args)
        Mixlib::ShellOut.new([@bin] + args + ['--', target]).run_command.error!
      end

      def info
        s = Mixlib::ShellOut.new([@bin, 'info', '--', target]).run_command
        s.error!
        s.stdout
      end

      # The digits of the `<label>: <digits>` line in `svn info` output, or
      # nil when there is none.
      def info_number(output, label)
        output[/^#{label}: (\d+)$/, 1]
      end

      # `svn diff --summarize` output as { status:, path: } entries, with
      # paths relative to the checkout. Each line has two status columns:
      # content (A, D, M, or blank) and properties (M or blank), so a
      # property-only change such as svn:mergeinfo after a merge starts with
      # a space and counts as :modified. The path is the rest of the line,
      # not one \S+ token: svn prints the full path, which may hold spaces.
      def summary_entries(summary)
        summary.lines.map do |line|
          m = line.match(/^([ ADM])[ M]\s+(.+)$/)
          raise "Could not parse line: #{line}" unless m

          {
            status: m[1] == 'D' ? :deleted : :modified,
            path: m[2].sub("#{local_path}/", '')
          }
        end
      end

      def revert
        run(%w[revert -R])
      end

      def up
        run(%w[update])
      end

      def cleanup
        run(%w[cleanup])
      end

      def first_revision
        0
      end

      # Raises Changeset::ReferenceError unless every ref exists; end_ref
      # may be nil.
      def check_refs(start_ref, end_ref)
        [start_ref, end_ref].compact.each do |ref|
          Mixlib::ShellOut.new([@bin, 'info', '-r', ref.to_s], cwd: local_path).run_command.error!
        rescue Mixlib::ShellOut::ShellCommandFailed
          raise Changeset::ReferenceError, "unknown ref #{ref.inspect}"
        end
      end
    end
  end
end
