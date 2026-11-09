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
require 'mixlib/shellout'
require 'rbconfig'
require 'tmpdir'

# Runs bin/chef-diff as a separate process, since its failure paths end in
# abort, against a real git repository with one commit. The script has no
# class to describe.
describe 'bin/chef-diff' do # rubocop:disable RSpec/DescribeClass
  subject do
    lib_dir = File.expand_path('../lib', __dir__)
    bin = File.expand_path('../bin/chef-diff', __dir__)
    command = [RbConfig.ruby, '-I', lib_dir, bin] + args + [repo_path]
    run = Mixlib::ShellOut.new(command).run_command
    { stdout: run.stdout, stderr: run.stderr, exitstatus: run.exitstatus }
  end

  let(:args) { ['-s', start_ref] }
  let(:work_tree) { Dir.mktmpdir }
  let(:repo_path) { work_tree }
  let(:start_ref) { 'HEAD' }
  let(:cannot_open) { "chef-diff: cannot open #{repo_path} as a git repository\n" }

  # Runs git in the work tree with a fixed identity, so commits work
  # without the runner's git config.
  def git(*argv)
    identity = ['-c', 'user.name=spec', '-c', 'user.email=spec@example.com', '-c', 'commit.gpgsign=false']
    Mixlib::ShellOut.new(['git'] + identity + argv, cwd: work_tree).run_command.error!
  end

  before do
    git('init', '-q')
    git('commit', '-q', '--allow-empty', '-m', 'init')
  end

  after { FileUtils.remove_entry(work_tree) }

  # A second commit adds a role, so there is a change since the start ref
  # to list.
  context 'with a known start ref' do
    let(:start_ref) { 'HEAD~1' }

    before do
      FileUtils.mkdir(File.join(work_tree, 'roles'))
      File.write(File.join(work_tree, 'roles/web.json'), "{}\n")
      git('add', 'roles')
      git('commit', '-q', '-m', 'role')
    end

    it { is_expected.to eq(stdout: "\n------\nRoles changed:\n------\n\nweb\n\n", stderr: '', exitstatus: 0) }
  end

  context 'with an unknown start ref' do
    let(:start_ref) { 'nope' }

    it { is_expected.to eq(stdout: '', stderr: "chef-diff: unknown ref \"nope\"\n", exitstatus: 1) }
  end

  # What a deploy job passes as -s "$PREV_SHA" when the variable is unset.
  context 'with an empty start ref' do
    let(:start_ref) { '' }

    it { is_expected.to eq(stdout: '', stderr: "chef-diff: unknown ref \"\"\n", exitstatus: 1) }
  end

  context 'with an unknown option' do
    let(:args) { %w[-x] }

    it { is_expected.to eq(stdout: '', stderr: "chef-diff: invalid option: -x\n", exitstatus: 1) }
  end

  context 'with a path that does not exist' do
    let(:repo_path) { File.join(work_tree, 'missing') }

    it { is_expected.to eq(stdout: '', stderr: cannot_open, exitstatus: 1) }
  end

  context 'with a directory outside any repository' do
    let(:repo_path) { Dir.mktmpdir }

    after { FileUtils.remove_entry(repo_path) }

    it { is_expected.to eq(stdout: '', stderr: cannot_open, exitstatus: 1) }
  end

  # A real repository git refuses to read: an unknown format version here,
  # or "dubious ownership" in the wild. Saying it is not a repo would send
  # the user looking for the wrong fix.
  context 'with a repository git refuses to open' do
    before { git('config', 'core.repositoryformatversion', '99') }

    it { is_expected.to eq(stdout: '', stderr: cannot_open, exitstatus: 1) }
  end
end
