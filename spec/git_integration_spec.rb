# frozen_string_literal: true

# vim: syntax=ruby:expandtab:shiftwidth=2:softtabstop=2:tabstop=2

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

require 'spec_helper'
require 'fileutils'
require 'tmpdir'
require 'chef_diff/repo/git'

# Runs the real git binary against a throwaway repository, so the paths
# below go through git's own quoting and the process spawning for real.
describe ChefDiff::Repo::Git do
  subject(:git) { described_class.new(repo_path, logger) }

  include_context 'with a silent logger'

  let(:work_tree) { Dir.mktmpdir }
  let(:repo_path) { work_tree }
  # In git's (byte) sort order.
  let(:odd_paths) { ['nodes/$(touch${IFS}PWNED).json', 'nodes/a b.json', 'nodes/café.json'] }

  # CI runners have no global git identity, and git refuses to commit or
  # even start a merge without one, so every committing call passes it.
  def git_command(args)
    identity = ['-c', 'user.name=spec', '-c', 'user.email=spec@example.com', '-c', 'commit.gpgsign=false']
    Mixlib::ShellOut.new(['git'] + identity + args, cwd: work_tree)
  end

  def run_git(args)
    git_command(args).run_command.error!
  end

  # Files a `touch PWNED` would leave if a name reached a shell, which runs
  # in either the work tree or the spec process's directory.
  def pwned_files
    Dir.glob([File.join(work_tree, '**', 'PWNED'), 'PWNED'])
  end

  def commit_files(paths)
    paths.each do |path|
      FileUtils.mkdir_p(File.join(work_tree, File.dirname(path)))
      File.write(File.join(work_tree, path), "{}\n")
    end
    run_git(%w[add -A])
    run_git(%w[commit -q -m spec])
  end

  before do
    run_git(%w[init -q])
    commit_files(['README.md'])
    commit_files(odd_paths + ['roles/plain.json'])
  end

  after { FileUtils.remove_entry(work_tree) }

  describe '#changes' do
    # #changes turns any parse error into exit(1), which would end the whole
    # rspec run with "0 failures"; fail just the example instead.
    around do |example|
      example.run
    rescue SystemExit
      raise 'unexpected exit(1): #changes rescued an error while parsing the diff'
    end

    it 'returns the exact paths' do
      expect(git.changes('HEAD~1', 'HEAD').map { |change| change[:path] }).to eq(odd_paths + ['roles/plain.json'])
    end

    context 'with a skip-worktree file' do
      before { run_git(%w[update-index --skip-worktree roles/plain.json]) }

      it 'leaves it out' do
        expect(git.changes('HEAD~1', 'HEAD').map { |change| change[:path] }).not_to include('roles/plain.json')
      end
    end

    it 'runs no file name through a shell' do
      git.changes('HEAD~1', 'HEAD')
      git.files
      expect(pwned_files).to be_empty
    end

    context 'with shell syntax in a ref name' do
      # A valid branch name: git allows $, ( and ), and ${IFS} stands in
      # for the space it forbids.
      let(:ref) { 'a$(touch${IFS}PWNED)' }

      before { run_git(['branch', ref, 'HEAD~1']) }

      it 'runs no ref through a shell' do
        git.changes(ref, 'HEAD')
        expect(pwned_files).to be_empty
      end
    end

    context 'with a renamed file' do
      before do
        run_git(['mv', 'nodes/a b.json', 'nodes/c d.json'])
        run_git(%w[commit -q -m rename])
      end

      it 'deletes the source, modifies the target' do
        expect(git.changes('HEAD~1', 'HEAD')).to eq([
                                                      { status: :deleted, path: 'nodes/a b.json' },
                                                      { status: :modified, path: 'nodes/c d.json' }
                                                    ])
      end
    end

    context 'with repo_path a subdirectory' do
      let(:repo_path) { File.join(work_tree, 'chef') }

      before { commit_files(['chef/nodes/sub.json', 'outside.json']) }

      it 'returns only its paths, relative to it' do
        expect(git.changes('HEAD~1', 'HEAD')).to eq([{ status: :modified, path: 'nodes/sub.json' }])
      end
    end
  end

  describe '#head_rev' do
    let(:head_sha) { Mixlib::ShellOut.new(%w[git rev-parse HEAD], cwd: work_tree).run_command.stdout.strip }

    it 'returns the bare commit SHA' do
      expect(git.head_rev).to eq(head_sha)
    end
  end

  describe '#status' do
    before { File.write(File.join(work_tree, 'roles/plain.json'), "[]\n") }

    it 'returns the porcelain output' do
      expect(git.status).to eq(" M roles/plain.json\n")
    end
  end

  describe '#files' do
    it 'returns the exact paths' do
      expect(git.files.map { |file| file[:path] }).to eq(['README.md'] + odd_paths + ['roles/plain.json'])
    end

    context 'with a skip-worktree file' do
      before { run_git(%w[update-index --skip-worktree roles/plain.json]) }

      it 'leaves it out' do
        expect(git.files.map { |file| file[:path] }).not_to include('roles/plain.json')
      end
    end

    context 'with a conflicted merge' do
      def commit_role(content)
        File.write(File.join(work_tree, 'roles/plain.json'), content)
        run_git(%w[commit -q -a -m spec])
      end

      before do
        run_git(%w[checkout -q -b theirs])
        commit_role("{\"theirs\":1}\n")
        run_git(%w[checkout -q -])
        commit_role("{\"ours\":1}\n")
        # No error!: the merge must stop on the conflict, exit 1. Any other
        # result would leave no conflict and the example would pass vacuously.
        merge = git_command(%w[merge theirs]).run_command
        raise "merge did not conflict: #{merge.format_for_exception}" unless merge.exitstatus == 1
      end

      it 'lists the conflicted file once' do
        expect(git.files.count { |file| file[:path] == 'roles/plain.json' }).to eq(1)
      end
    end
  end
end
