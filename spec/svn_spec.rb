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

# Commands are argv Arrays so refs and paths never reach a shell. Query
# methods stub Mixlib::ShellOut.new for their exact argv only, so any other
# argv fails the example; command methods assert the argv they ran.
describe ChefDiff::Repo::Svn do
  include_context 'with a silent logger'
  include ShellDouble

  # Svn#setup only sets @bin — no filesystem access — so no stub needed.
  let(:svn) { described_class.new(repo_path, logger) }
  let(:repo_path) { '/tmp/testrepo' }

  # The checkout as svn must see it: a trailing `@` so an `@` inside the path
  # is not read as a peg revision. Checkout's destination takes repo_path.
  def target
    "#{repo_path}@"
  end

  describe '#setup' do
    it 'sets @bin to svn' do
      expect(svn.instance_variable_get(:@bin)).to eq('svn')
    end
  end

  describe '#exists?' do
    context 'when the repo path is a directory' do
      it 'returns true' do
        allow(Dir).to receive(:exist?).with(repo_path).and_return(true)
        expect(svn.exists?).to be true
      end
    end

    context 'when the repo path is not a directory' do
      it 'returns false' do
        allow(Dir).to receive(:exist?).with(repo_path).and_return(false)
        expect(svn.exists?).to be false
      end
    end
  end

  describe '#head_rev' do
    subject { svn.head_rev }

    before do
      allow(Mixlib::ShellOut).to receive(:new).with(['svn', 'info', '--', target])
                                              .and_return(shell_double(svn_info))
    end

    context 'with a Last Changed Rev line' do
      let(:svn_info) { "Path: .\nRevision: 43\nLast Changed Rev: 42\n" }

      it { is_expected.to eq('42') }
    end

    context 'with no matching line' do
      let(:svn_info) { "Path: .\nURL: svn://example.com/repo\n" }

      it { is_expected.to be_nil }
    end
  end

  describe '#latest_revision' do
    subject { svn.latest_revision }

    before do
      allow(Mixlib::ShellOut).to receive(:new).with(['svn', 'info', '--', target])
                                              .and_return(shell_double(svn_info))
    end

    context 'with a Revision line' do
      let(:svn_info) { "Path: .\nRevision: 100\nLast Changed Rev: 42\n" }

      it { is_expected.to eq('100') }
    end

    context 'with no matching line' do
      let(:svn_info) { "Path: .\nURL: svn://example.com/repo\n" }

      it { is_expected.to be_nil }
    end
  end

  describe '#checkout' do
    before { allow(Mixlib::ShellOut).to receive(:new).and_return(shell_double('')) }

    it 'checks out the URL into the repo path' do
      svn.checkout('svn://example.com/repo')
      expect(Mixlib::ShellOut).to have_received(:new)
        .with(['svn', 'co', '--ignore-externals', '--', 'svn://example.com/repo', repo_path])
    end
  end

  # #changes runs `svn info -r` per ref to check it exists, then one
  # `svn diff --summarize`; each is stubbed by its argv.
  describe '#changes' do
    subject(:changes) { svn.changes(start_ref, end_ref) }

    let(:start_ref) { '100' }
    let(:end_ref) { '101' }
    let(:diff) { "D       #{repo_path}/roles/old.json\nM       #{repo_path}/roles/new.json\n" }

    # instance_of(String): svn cannot take an Integer argv element, so an
    # unconverted ref fails every example, not only the one that checks it.
    before do
      allow(Mixlib::ShellOut).to receive(:new).with(['svn', 'info', '-r', instance_of(String)], cwd: repo_path)
                                              .and_return(shell_double(''))
      allow(Mixlib::ShellOut).to receive(:new).with(['svn', 'diff', '-r', anything, '--summarize', '--', target])
                                              .and_return(shell_double(diff))
    end

    it 'maps D to :deleted and M to :modified' do
      expect(changes).to eq([{ status: :deleted, path: 'roles/old.json' },
                             { status: :modified, path: 'roles/new.json' }])
    end

    it 'checks that end_ref exists' do
      changes
      expect(Mixlib::ShellOut).to have_received(:new).with(%w[svn info -r 101], cwd: repo_path)
    end

    it 'diffs start_ref to end_ref' do
      changes
      expect(Mixlib::ShellOut).to have_received(:new)
        .with(['svn', 'diff', '-r', '100:101', '--summarize', '--', target])
    end

    context 'with an added file' do
      let(:diff) { "A       #{repo_path}/roles/new.json\n" }

      it { is_expected.to eq([{ status: :modified, path: 'roles/new.json' }]) }
    end

    context 'with a property-only change' do
      let(:diff) { " M      #{repo_path}/roles\n" }

      it { is_expected.to eq([{ status: :modified, path: 'roles' }]) }
    end

    context 'with a space and an @ in the repo path' do
      let(:repo_path) { '/tmp/test@prod repo' }

      it 'keeps the whole path' do
        expect(changes).to eq([{ status: :deleted, path: 'roles/old.json' },
                               { status: :modified, path: 'roles/new.json' }])
      end
    end

    context 'with an unparseable line' do
      let(:diff) { "UNPARSEABLE\n" }

      it 'raises' do
        expect { changes }.to raise_error(RuntimeError, /Could not parse/)
      end
    end

    context 'when the start ref is invalid' do
      before do
        allow(Mixlib::ShellOut).to receive(:new).with(%w[svn info -r 100], any_args).and_return(failing_shell_double)
      end

      it 'raises ReferenceError naming it' do
        expect { changes }.to raise_error(ChefDiff::Changeset::ReferenceError, 'unknown ref "100"')
      end
    end

    context 'when the end ref is invalid' do
      before do
        allow(Mixlib::ShellOut).to receive(:new).with(%w[svn info -r 101], any_args).and_return(failing_shell_double)
      end

      it 'raises ReferenceError naming it' do
        expect { changes }.to raise_error(ChefDiff::Changeset::ReferenceError, 'unknown ref "101"')
      end
    end

    context 'when svn cannot run' do
      before do
        allow(Mixlib::ShellOut).to receive(:new).with(%w[svn info -r 100], any_args).and_raise(Errno::ENOENT, 'svn')
      end

      it 'does not blame the ref' do
        expect { changes }.to raise_error(Errno::ENOENT)
      end
    end

    context 'without an end_ref' do
      let(:end_ref) { nil }

      it 'checks only start_ref' do
        changes
        expect(Mixlib::ShellOut).to have_received(:new).with(['svn', 'info', '-r', anything], any_args).once
      end

      it 'diffs start_ref against the working copy' do
        changes
        expect(Mixlib::ShellOut).to have_received(:new)
          .with(['svn', 'diff', '-r', '100', '--summarize', '--', target])
      end
    end

    context 'with shell metacharacters in a ref' do
      let(:start_ref) { '1; rm -rf ~' }

      it 'passes the raw ref as one argv element' do
        changes
        expect(Mixlib::ShellOut).to have_received(:new).with(['svn', 'info', '-r', '1; rm -rf ~'], any_args)
      end
    end

    context 'with Integer refs' do
      let(:start_ref) { 100 }
      let(:end_ref) { 101 }

      it 'checks each ref as a String' do
        changes
        expect(Mixlib::ShellOut).to have_received(:new).with(%w[svn info -r 100], cwd: repo_path)
      end

      it 'diffs start_ref to end_ref' do
        changes
        expect(Mixlib::ShellOut).to have_received(:new)
          .with(['svn', 'diff', '-r', '100:101', '--summarize', '--', target])
      end
    end

    context 'with an Integer start_ref and no end_ref' do
      let(:start_ref) { 100 }
      let(:end_ref) { nil }

      it 'diffs start_ref as a String against the working copy' do
        changes
        expect(Mixlib::ShellOut).to have_received(:new)
          .with(['svn', 'diff', '-r', '100', '--summarize', '--', target])
      end
    end
  end

  describe '#update' do
    before { allow(Mixlib::ShellOut).to receive(:new).and_return(shell_double('')) }

    it 'cleans up the checkout' do
      svn.update
      expect(Mixlib::ShellOut).to have_received(:new).with(['svn', 'cleanup', '--', target])
    end

    it 'reverts local changes' do
      svn.update
      expect(Mixlib::ShellOut).to have_received(:new).with(['svn', 'revert', '-R', '--', target])
    end

    it 'updates the checkout' do
      svn.update
      expect(Mixlib::ShellOut).to have_received(:new).with(['svn', 'update', '--', target])
    end
  end

  describe '#files' do
    it 'returns all files as :created entries' do
      listing = "roles/web.json\ncookbooks/base/metadata.rb\n"
      allow(Mixlib::ShellOut).to receive(:new).with(['svn', 'ls', '--depth', 'infinity', '--', target])
                                              .and_return(shell_double(listing))
      expect(svn.files).to eq([{ path: 'roles/web.json', status: :created },
                               { path: 'cookbooks/base/metadata.rb', status: :created }])
    end
  end

  # svn takes `~` literally, so every command gets the expanded path.
  context 'with a repo path under ~' do
    let(:repo_path) { '~/chef' }
    let(:home_path) { File.join(Dir.home, 'chef') }
    let(:diff) { "M       #{home_path}/roles/web.json\n" }

    before do
      allow(Mixlib::ShellOut).to receive(:new).and_return(shell_double(''))
      allow(Mixlib::ShellOut).to receive(:new).with(array_including('diff')).and_return(shell_double(diff))
    end

    it 'checks out into the expanded path' do
      svn.checkout('svn://example.com/repo')
      expect(Mixlib::ShellOut).to have_received(:new)
        .with(['svn', 'co', '--ignore-externals', '--', 'svn://example.com/repo', home_path])
    end

    it 'queries the expanded path' do
      svn.head_rev
      expect(Mixlib::ShellOut).to have_received(:new).with(['svn', 'info', '--', "#{home_path}@"])
    end

    it 'checks refs from the expanded path' do
      svn.changes('100', '101')
      expect(Mixlib::ShellOut).to have_received(:new).with(%w[svn info -r 100], cwd: home_path)
    end

    it 'returns changed paths relative to the checkout' do
      expect(svn.changes('100', '101')).to eq([{ status: :modified, path: 'roles/web.json' }])
    end

    context 'when the user is unknown' do
      let(:repo_path) { '~no-such-user-chef-diff/chef' }

      it 'uses the path as given' do
        svn.head_rev
        expect(Mixlib::ShellOut).to have_received(:new).with(['svn', 'info', '--', "#{repo_path}@"])
      end
    end
  end

  # No caller in lib/, so no public method reaches it; tested directly.
  describe '#first_revision (private)' do
    it 'returns 0' do
      expect(svn.send(:first_revision)).to eq(0)
    end
  end
end
