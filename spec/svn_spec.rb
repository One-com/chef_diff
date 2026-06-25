# frozen_string_literal: true

# vim: syntax=ruby:expandtab:shiftwidth=2:softtabstop=2:tabstop=2

# Copyright 2026-present One.com
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
require 'chef_diff/repo/svn'
require 'chef_diff/repo'
describe ChefDiff::Repo::Svn do
  include_context 'silent logger'

  # Svn#setup only sets @bin — no filesystem access — so no stub needed.
  let(:svn) { ChefDiff::Repo::Svn.new('/tmp/testrepo', logger) }

  # Helper: a ShellOut double that succeeds and returns given stdout.
  def shell_double(stdout_text)
    d = double('cmd')
    allow(d).to receive(:run_command).and_return(d)
    allow(d).to receive(:error!)
    allow(d).to receive(:stdout).and_return(stdout_text)
    d
  end

  describe '#setup' do
    it 'sets @bin to svn' do
      expect(svn.instance_variable_get(:@bin)).to eq('svn')
    end
  end

  describe '#exists?' do
    it 'returns true when the repo path is a directory' do
      allow(Dir).to receive(:exist?).and_return(true)
      expect(svn.exists?).to be true
    end

    it 'returns false when the repo path is not a directory' do
      allow(Dir).to receive(:exist?).and_return(false)
      expect(svn.exists?).to be false
    end
  end

  describe '#head_rev' do
    it 'returns the last-changed revision number as a string' do
      svn_info = "Path: .\nURL: svn://example.com/repo\nLast Changed Rev: 42\n"
      allow(Mixlib::ShellOut).to receive(:new).and_return(shell_double(svn_info))
      expect(svn.head_rev).to eq('42')
    end
  end

  describe '#latest_revision' do
    it 'returns the repository revision number as a string' do
      # stdout is iterated with #each; pass an array so it works in Ruby 3.x
      # (String#each was removed in Ruby 1.9 — this also documents the source bug)
      lines = ["Path: .\n", "URL: svn://example.com/repo\n", "Revision: 100\n"]
      cmd = double('cmd')
      allow(cmd).to receive(:run_command).and_return(cmd)
      allow(cmd).to receive(:error!)
      allow(cmd).to receive(:stdout).and_return(lines)
      allow(Mixlib::ShellOut).to receive(:new).and_return(cmd)
      expect(svn.latest_revision).to eq('100')
    end
  end

  describe '#checkout' do
    it 'runs svn co and does not raise' do
      allow(Mixlib::ShellOut).to receive(:new).and_return(shell_double(''))
      expect { svn.checkout('svn://example.com/repo') }.not_to raise_error
    end
  end

  describe '#changes' do
    before { allow(svn).to receive(:check_refs) }

    it 'maps D lines to :deleted and other lines to :modified' do
      diff_output = "D       /tmp/testrepo/roles/old.json\n" \
                    "M       /tmp/testrepo/roles/new.json\n"
      allow(Mixlib::ShellOut).to receive(:new).and_return(shell_double(diff_output))
      result = svn.changes('100', '101')
      expect(result).to eq([
                             { status: :deleted, path: 'roles/old.json' },
                             { status: :modified, path: 'roles/new.json' }
                           ])
    end

    it 'raises when a line cannot be parsed' do
      allow(Mixlib::ShellOut).to receive(:new)
        .and_return(shell_double("UNPARSEABLE\n"))
      expect { svn.changes('100', '101') }.to raise_error(RuntimeError, /Could not parse/)
    end
  end

  describe '#update' do
    it 'calls cleanup, revert, and up (via the run helper)' do
      cmd = shell_double('')
      allow(Mixlib::ShellOut).to receive(:new).and_return(cmd)
      # update calls three private methods, each shelling out once
      expect(Mixlib::ShellOut).to receive(:new).exactly(3).times.and_return(cmd)
      svn.update
    end
  end

  describe '#files' do
    it 'returns all files as :created entries' do
      listing = "roles/web.json\ncookbooks/base/metadata.rb\n"
      allow(Mixlib::ShellOut).to receive(:new).and_return(shell_double(listing))
      expect(svn.files).to eq([
                                { path: 'roles/web.json', status: :created },
                                { path: 'cookbooks/base/metadata.rb', status: :created }
                              ])
    end
  end

  describe '#check_refs (private)' do
    it 'does not raise when both refs exist' do
      allow(Mixlib::ShellOut).to receive(:new).and_return(shell_double(''))
      expect { svn.send(:check_refs, '100', '101') }.not_to raise_error
    end

    it 'does not check end_ref when end_ref is nil' do
      allow(Mixlib::ShellOut).to receive(:new).and_return(shell_double(''))
      expect(Mixlib::ShellOut).to receive(:new).once.and_return(shell_double(''))
      svn.send(:check_refs, '100', nil)
    end

    it 'raises ReferenceError when a ref is invalid' do
      cmd = double('cmd')
      allow(cmd).to receive(:run_command).and_return(cmd)
      allow(cmd).to receive(:error!).and_raise(RuntimeError, 'invalid ref')
      allow(Mixlib::ShellOut).to receive(:new).and_return(cmd)
      expect { svn.send(:check_refs, 'bad', nil) }
        .to raise_error(ChefDiff::Changeset::ReferenceError)
    end
  end

  describe '#first_revision (private)' do
    it 'returns 0' do
      expect(svn.send(:first_revision)).to eq(0)
    end
  end
end
