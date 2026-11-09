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

require 'set'
require 'chef_diff/repo'
require 'mixlib/shellout'
require 'chef_diff/changeset'

module ChefDiff
  # Local checkout wrapper
  class Repo
    # Git provider
    #
    # File paths come from `git diff` and `git ls-files`, run with an argv
    # array (no shell, so a file name can't inject commands) and with -z.
    # With -z git separates fields with NUL and never quotes or escapes a
    # path, so every path token is exactly the file name's bytes, whatever
    # spaces, quotes or non-ASCII characters it holds.
    #
    # One cohesive backend for all git CLI operations; splitting to satisfy the line count would not aid readers.
    # rubocop:disable-next Metrics/ClassLength
    class Git < ChefDiff::Repo
      # How each `git diff --name-status` status letter maps to entries, as
      # [status, index into the entry's paths] pairs. A type change (T) is
      # a delete plus a re-upload; a rename (R) also deletes its source,
      # while a copy (C) leaves it in place. Anything else (U, X) is an
      # error.
      DIFF_STATUSES = {
        'A' => [[:modified, 0]],
        'M' => [[:modified, 0]],
        'D' => [[:deleted, 0]],
        'T' => [[:deleted, 0], [:modified, 0]],
        'R' => [[:deleted, 0], [:modified, 1]],
        'C' => [[:modified, 1]]
      }.freeze

      # Status letters followed by two paths, source then destination.
      TWO_PATH_STATUSES = %w[R C].freeze

      # `ls-files -v` tags of skip-worktree paths; lowercase means the
      # assume-unchanged bit is set too.
      SKIP_WORKTREE_TAGS = %w[S s].freeze

      def setup
        @repo = (@repo_path if File.exist?(File.expand_path(@repo_path)))
        @bin = 'git'
      end

      def exists?
        return false unless @repo

        # rev-parse only looks for .git; `git status` would scan the whole
        # work tree just to answer yes or no.
        cmd = Mixlib::ShellOut.new([@bin, 'rev-parse', '--git-dir'], cwd: File.expand_path(@repo_path))
        cmd.run_command
        cmd.exitstatus.zero?
      end

      def head_rev
        cmd = Mixlib::ShellOut.new([@bin, 'log', '-n', '1', '--pretty=format:%H'], cwd: File.expand_path(@repo_path))
        cmd.run_command.error!
        cmd.stdout.strip
      end

      def checkout(url)
        s = Mixlib::ShellOut.new(
          [@bin, 'clone', '--depth', '1', '--', url, @repo_path]
        ).run_command
        s.error!
        @repo = @repo_path
      end

      # Files changed between two revisions, as { status:, path: } hashes in
      # git's order, with paths relative to the repo directory. A nil
      # end_ref diffs start_ref against the working tree. Changes outside
      # the repo directory, skip-worktree paths and paths that aren't valid
      # UTF-8 are left out. Exits the process if git's output can't be
      # parsed.
      def changes(start_ref, end_ref)
        check_refs(start_ref, end_ref)
        entries = utf8_entries(parse_diff(diff_name_status(start_ref, end_ref)))
        skipped = skip_worktree_paths
        entries.reject { |entry| skipped.include?(entry[:path]) }
      end

      def update
        cmd = Mixlib::ShellOut.new("#{@bin} pull --rebase 2>&1", cwd: File.expand_path(@repo_path))
        cmd.run_command.error!
        cmd.stdout
      end

      # All tracked files under the repo directory, as { path:, status:
      # :created } hashes, minus skip-worktree paths and paths that aren't
      # valid UTF-8.
      def files
        # uniq: ls-files lists an unmerged path once per merge stage.
        paths = ls_files.filter_map { |tag, path| path unless SKIP_WORKTREE_TAGS.include?(tag) }.uniq
        utf8_entries(paths.map { |path| { path: path, status: :created } })
      end

      def status
        cmd = Mixlib::ShellOut.new("#{@bin} status --porcelain 2>&1", cwd: File.expand_path(@repo_path))
        cmd.run_command.error!
        cmd.stdout
      end

      private

      # inspect quotes the ref, so an empty one still shows in the message.
      def check_refs(start_ref, end_ref)
        raise Changeset::ReferenceError, "unknown ref #{start_ref.inspect}" unless ref_exists?(start_ref)

        return if end_ref.nil? || end_ref == 'HEAD'
        raise Changeset::ReferenceError, "unknown ref #{end_ref.inspect}" unless ref_exists?(end_ref)
      end

      # Raw `git diff --name-status -z` output. --relative makes git print
      # paths relative to the repo directory, however @repo_path is spelt,
      # and drop changes outside it, matching what `ls-files` lists from
      # there. The trailing `--` keeps git from reading a ref as a path.
      def diff_name_status(start_ref, end_ref)
        args = [@bin, 'diff', '--name-status', '--relative', '-z', start_ref]
        args.push(end_ref) if end_ref
        args.push('--')
        cmd = Mixlib::ShellOut.new(args, cwd: File.expand_path(@repo_path))
        cmd.run_command.error!
        cmd.stdout
      end

      # Parses diff output into entries. On output it doesn't understand,
      # logs every token and exits.
      def parse_diff(stdout)
        tokens = nul_tokens(stdout)
        parse_name_status(tokens)
      rescue StandardError => e
        # We've seen some weird non-reproducible failures here
        @logger.error('Something went wrong. Please report this output.')
        @logger.error(e)
        tokens.each { |token| @logger.error(token.inspect) }
        exit(1)
      end

      # Turns `git diff --name-status -z` tokens into { status:, path: }
      # entries. An entry is a status token (a letter, maybe followed by a
      # score as in R100) and then one path token, or two for R and C.
      # Raises on an unknown status or an entry cut short.
      def parse_name_status(tokens)
        queue = tokens.dup
        entries = []
        until queue.empty?
          status = queue.shift
          count = TWO_PATH_STATUSES.include?(status[0]) ? 2 : 1
          raise "Truncated git diff entry: #{status.inspect}" if queue.size < count

          entries.concat(name_status_entries(status, queue.shift(count)))
        end
        entries
      end

      def name_status_entries(status, paths)
        actions = DIFF_STATUSES.fetch(status[0]) do
          raise "Unknown git diff status: #{status.inspect}"
        end
        actions.map { |change, index| { status: change, path: paths[index] } }
      end

      # Tracked paths under the repo directory, relative to it, as
      # [tag, path] pairs, where tag is the `ls-files -v` status letter.
      def ls_files
        cmd = Mixlib::ShellOut.new(
          [@bin, 'ls-files', '-v', '-z'], cwd: File.expand_path(@repo_path)
        )
        cmd.run_command.error!
        nul_tokens(cmd.stdout).map { |token| [token[0], token[2..]] }
      end

      def skip_worktree_paths
        ls_files.filter_map { |tag, path| path if SKIP_WORKTREE_TAGS.include?(tag) }.to_set
      end

      # Splits -z output on NUL. It splits as binary, because a file name
      # that isn't valid UTF-8 would make a UTF-8 split raise, then tags
      # each token UTF-8 for the regexes in Changes::*.
      def nul_tokens(output)
        output.b.split("\0").map { |token| token.force_encoding(Encoding::UTF_8) }
      end

      # Drops, with a warning, entries whose path isn't valid UTF-8: no Chef
      # object name can hold such bytes, and the Changes::* regexes would
      # raise on them.
      def utf8_entries(entries)
        valid, invalid = entries.partition { |entry| entry[:path].valid_encoding? }
        invalid.each { |entry| @logger.warn("Skipping path that is not valid UTF-8: #{entry[:path].inspect}") }
        valid
      end

      def ref_exists?(ref)
        # argv, not a string: ref names may hold $(...) or `;`. `--` stops a
        # ref that starts with a dash from being read as an option.
        cmd = Mixlib::ShellOut.new(
          [@bin, 'cat-file', '-t', '--', ref], cwd: File.expand_path(@repo_path)
        )
        cmd.run_command
        cmd.exitstatus.zero?
      end
    end
  end
end
