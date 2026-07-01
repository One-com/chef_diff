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

require 'spec_helper'
require 'chef_diff/repo/git'
require 'chef_diff/repo'
describe ChefDiff::Repo::Git do
  include_context 'silent logger'

  # Shared setup: a Git instance with @repo and @bin set, no real FS access
  let(:git) do
    allow_any_instance_of(described_class).to receive(:setup) do |instance|
      instance.instance_variable_set(:@repo, 'foo')
      instance.instance_variable_set(:@bin, 'git')
    end
    described_class.new('foo', logger)
  end

  # Helper: a ShellOut double that runs successfully and returns given stdout
  def shell_double(stdout_text)
    d = double('cmd')
    allow(d).to receive(:run_command).and_return(d)
    allow(d).to receive(:error!)
    allow(d).to receive(:stdout).and_return(stdout_text)
    d
  end

  fixtures = [
    {
      name: 'empty filelists',
      changes: '',
      result: []
    },
    {
      name: 'handle renames',
      changes: 'R050 foo/bar/baz foo/bang/bong',
      result: [
        { status: :deleted, path: 'bar/baz' },
        { status: :modified, path: 'bang/bong' }
      ]
    },
    {
      name: 'handle type changes',
      changes: 'T foo/bar/baz',
      result: [
        { status: :deleted, path: 'bar/baz' },
        { status: :modified, path: 'bar/baz' }
      ]
    },
    {
      name: 'handle additions',
      changes: 'A foo/bar/baz',
      result: [
        { status: :modified, path: 'bar/baz' }
      ]
    },
    {
      name: 'handle deletes',
      changes: 'D foo/bar/baz',
      result: [
        { status: :deleted, path: 'bar/baz' }
      ]
    },
    {
      name: 'handle modifications',
      changes: 'M004 foo/bar/baz',
      result: [
        { status: :modified, path: 'bar/baz' }
      ]
    },
    {
      name: 'handle misc',
      changes: <<~CHANGES,
        R050 foo/bar/baz foo/bang/bong
        D foo/bar/baz
        C foo/bar/baz foo/bang/bong
      CHANGES
      result: [
        { status: :deleted, path: 'bar/baz' },
        { status: :modified, path: 'bang/bong' },
        { status: :deleted, path: 'bar/baz' },
        { status: :modified, path: 'bang/bong' }
      ]
    }
  ]

  describe '#parse_status (private)' do
    fixtures.each do |fixture|
      it "handles #{fixture[:name]}" do
        expect(git.send(:parse_status, fixture[:changes])).to eq(fixture[:result])
      end
    end

    it 'raises on an unrecognised status letter' do
      expect { git.send(:parse_status, "X foo/bar/baz\n") }.to raise_error(RuntimeError)
    end
  end

  describe '#head_rev' do
    it 'returns the stripped HEAD commit SHA' do
      allow(Mixlib::ShellOut).to receive(:new).and_return(shell_double("  abc123  \n"))
      expect(git.head_rev).to eq('abc123')
    end
  end

  describe '#checkout' do
    it 'sets @repo to the repo path after cloning' do
      # Reset @repo to nil first so the assignment inside checkout is detectable
      git.instance_variable_set(:@repo, nil)
      allow(Mixlib::ShellOut).to receive(:new).and_return(shell_double(''))
      git.checkout('https://example.com/repo.git')
      expect(git.instance_variable_get(:@repo)).to eq('foo')
    end
  end

  describe '#changes' do
    before do
      allow(git).to receive(:check_refs)
      allow(git).to receive(:skip_marked?).and_return(false)
    end

    it 'returns parsed changed files' do
      allow(Mixlib::ShellOut).to receive(:new)
        .and_return(shell_double("M\tfoo/roles/web.json\n"))
      result = git.changes('abc', 'def')
      expect(result).to eq([{ status: :modified, path: 'roles/web.json' }])
    end

    it 'excludes files flagged as skip-marked' do
      allow(Mixlib::ShellOut).to receive(:new)
        .and_return(shell_double("M\tfoo/roles/web.json\n"))
      allow(git).to receive(:skip_marked?).and_return(true)
      expect(git.changes('abc', 'def')).to be_empty
    end

    it 'exits when parse_status raises an unexpected error' do
      # An unrecognised status letter causes parse_status to raise,
      # which is caught inside changes and converted to exit(1)
      allow(Mixlib::ShellOut).to receive(:new)
        .and_return(shell_double("X\tfoo/bad_line\n"))
      expect { git.changes('abc', 'def') }.to raise_error(SystemExit)
    end
  end

  describe '#update' do
    it 'returns stdout when git pull succeeds' do
      cmd = double('cmd', run_command: nil, exitstatus: 0,
                          stdout: "Already up to date.\n")
      allow(Mixlib::ShellOut).to receive(:new).and_return(cmd)
      expect(git.update).to eq("Already up to date.\n")
    end

    it 'logs and fails when git pull returns a non-zero exit' do
      cmd = double('cmd', run_command: nil, exitstatus: 1,
                          stdout: "conflict\n")
      allow(Mixlib::ShellOut).to receive(:new).and_return(cmd)
      expect { git.update }.to raise_error(RuntimeError)
    end
  end

  describe '#files' do
    it 'returns all tracked files as :created entries' do
      allow(Mixlib::ShellOut).to receive(:new)
        .and_return(shell_double("H roles/web.json\nH cookbooks/base/metadata.rb\n"))
      expect(git.files).to eq([
                                { path: 'roles/web.json', status: :created },
                                { path: 'cookbooks/base/metadata.rb', status: :created }
                              ])
    end

    it 'skips skip-worktree (S) entries' do
      allow(Mixlib::ShellOut).to receive(:new)
        .and_return(shell_double("S skipped/file.rb\nH kept/file.rb\n"))
      expect(git.files.map { |f| f[:path] }).to eq(['kept/file.rb'])
    end
  end

  describe '#status' do
    it 'returns porcelain stdout when git status succeeds' do
      cmd = double('cmd', run_command: nil, exitstatus: 0,
                          stdout: " M roles/web.json\n")
      allow(Mixlib::ShellOut).to receive(:new).and_return(cmd)
      expect(git.status).to eq(" M roles/web.json\n")
    end

    it 'logs and fails when git status returns a non-zero exit' do
      cmd = double('cmd', run_command: nil, exitstatus: 1, stdout: "error\n")
      allow(Mixlib::ShellOut).to receive(:new).and_return(cmd)
      expect { git.status }.to raise_error(RuntimeError)
    end
  end

  describe '#check_refs (private)' do
    it 'raises ReferenceError when start_ref does not exist' do
      allow(git).to receive(:ref_exists?).and_return(false)
      expect { git.send(:check_refs, 'bad', nil) }
        .to raise_error(ChefDiff::Changeset::ReferenceError)
    end

    it 'raises ReferenceError when end_ref does not exist' do
      allow(git).to receive(:ref_exists?).and_return(true, false)
      expect { git.send(:check_refs, 'abc', 'bad_end') }
        .to raise_error(ChefDiff::Changeset::ReferenceError)
    end

    it 'does not raise when both refs exist' do
      allow(git).to receive(:ref_exists?).and_return(true)
      expect { git.send(:check_refs, 'abc', 'def') }.not_to raise_error
    end

    it 'does not raise when end_ref is nil' do
      allow(git).to receive(:ref_exists?).with('abc').and_return(true)
      expect { git.send(:check_refs, 'abc', nil) }.not_to raise_error
    end

    it 'does not raise when end_ref is HEAD' do
      allow(git).to receive(:ref_exists?).with('abc').and_return(true)
      expect { git.send(:check_refs, 'abc', 'HEAD') }.not_to raise_error
    end
  end

  describe '#ref_exists? (private)' do
    it 'returns true when the git command exits 0' do
      cmd = double('cmd', run_command: nil, exitstatus: 0)
      allow(Mixlib::ShellOut).to receive(:new).and_return(cmd)
      expect(git.send(:ref_exists?, 'abc123')).to be true
    end

    it 'returns false when the git command exits non-zero' do
      cmd = double('cmd', run_command: nil, exitstatus: 1)
      allow(Mixlib::ShellOut).to receive(:new).and_return(cmd)
      expect(git.send(:ref_exists?, 'bad_ref')).to be false
    end
  end

  describe '#skip_marked? (private)' do
    it 'returns a truthy match when the file is skip-worktree flagged' do
      allow(Mixlib::ShellOut).to receive(:new)
        .and_return(shell_double("S roles/web.json\n"))
      expect(git.send(:skip_marked?, 'roles/web.json')).to be_truthy
    end

    it 'returns nil when the file is not skip-worktree flagged' do
      allow(Mixlib::ShellOut).to receive(:new)
        .and_return(shell_double("H roles/web.json\n"))
      expect(git.send(:skip_marked?, 'roles/web.json')).to be_nil
    end
  end

  describe '#exec_cmd (private)' do
    it 'returns stdout on success' do
      cmd = shell_double("output\n")
      expect(git.send(:exec_cmd, cmd, 'should not fail')).to eq("output\n")
    end

    it 'logs and re-raises when the command fails' do
      cmd = shell_double("error output\n")
      allow(cmd).to receive(:error!).and_raise(RuntimeError, 'command failed')
      expect { git.send(:exec_cmd, cmd, 'Failure message') }.to raise_error(RuntimeError)
    end
  end

  describe '#setup' do
    it 'sets @repo to the path and @bin to git when the path exists' do
      allow(File).to receive(:exist?).and_return(true)
      g = described_class.new('foo', logger)
      expect(g.instance_variable_get(:@repo)).to eq('foo')
      expect(g.instance_variable_get(:@bin)).to eq('git')
    end

    it 'sets @repo to nil when the path does not exist' do
      allow(File).to receive(:exist?).and_return(false)
      g = described_class.new('nonexistent', logger)
      expect(g.instance_variable_get(:@repo)).to be_nil
      expect(g.instance_variable_get(:@bin)).to eq('git')
    end
  end

  describe '#exists?' do
    it 'returns false when the repo path was not found during setup' do
      allow_any_instance_of(described_class).to receive(:setup).and_return(true)
      git = described_class.new('nonexistent', logger)
      # setup was stubbed so @repo remains nil
      expect(git.exists?).to be false
    end

    it 'returns true when the repo path exists and git status succeeds' do
      cmd = double('cmd', run_command: nil, exitstatus: 0)
      allow(Mixlib::ShellOut).to receive(:new).and_return(cmd)
      expect(git.exists?).to be true
    end

    it 'returns false when the repo path exists but git status fails' do
      cmd = double('cmd', run_command: nil, exitstatus: 1)
      allow(Mixlib::ShellOut).to receive(:new).and_return(cmd)
      expect(git.exists?).to be false
    end
  end
end
