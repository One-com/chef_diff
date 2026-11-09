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

# For a block that must raise and leave state alone, in one expectation.
RSpec::Matchers.define_negated_matcher :avoid_changing, :change

describe ChefDiff::Repo::Git do
  include_context 'with a silent logger'
  include ShellDouble

  # Shared setup: a Git instance for an existing checkout at 'foo', so setup
  # sets @repo and @bin without the path being on disk
  let(:git) do
    allow(File).to receive(:exist?).and_call_original
    allow(File).to receive(:exist?).with(File.expand_path('foo')).and_return(true)
    described_class.new('foo', logger)
  end

  # Paths git prints quoted or escaped without -z, or that a shell would
  # interpret.
  def odd_paths
    ['nodes/a b.json', "nodes/tab\there.json", "nodes/new\nline.json", 'nodes/café.json',
     'nodes/"quoted".json', 'nodes/back\\slash.json', 'nodes/$(touch${IFS}PWNED).json',
     'nodes/a;b|c`d`.json']
  end

  def entry(status, path)
    { status: status, path: path }
  end

  describe '#head_rev' do
    it 'strips the output' do
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

    it 'clones with an argv array' do
      allow(Mixlib::ShellOut).to receive(:new).and_return(shell_double(''))
      git.checkout('https://example.com/repo.git')
      expect(Mixlib::ShellOut).to have_received(:new)
        .with(['git', 'clone', '--depth', '1', '--', 'https://example.com/repo.git', 'foo'])
    end

    context 'when the clone fails' do
      it 'leaves @repo unset' do
        git.instance_variable_set(:@repo, nil)
        allow(Mixlib::ShellOut).to receive(:new).and_return(failing_shell_double)
        expect { git.checkout('https://example.com/repo.git') }
          .to raise_error(Mixlib::ShellOut::ShellCommandFailed)
          .and(avoid_changing { git.instance_variable_get(:@repo) })
      end
    end
  end

  # #changes runs three kinds of command: `cat-file -t` per ref to check it
  # exists, one `diff --name-status`, and one `ls-files -v` to drop
  # skip-worktree files. Each is stubbed by its argv, so a context changes
  # only the output it is about. git runs in repo_path with --relative, so
  # diff and ls-files paths are both already relative to it.
  describe '#changes' do
    subject(:changes) { git.changes('abc', end_ref) }

    let(:end_ref) { 'def' }
    let(:diff_output) { '' }
    let(:ls_files_output) { '' }
    let(:missing_ref) { instance_double(Mixlib::ShellOut, run_command: nil, exitstatus: 1) }

    # #changes turns any parse error into exit(1). Unless an example expects
    # that, it would end the whole rspec run with "0 failures"; fail just
    # the example instead.
    around do |example|
      example.run
    rescue SystemExit
      raise 'unexpected exit(1): #changes rescued an error while parsing the diff'
    end

    before do
      allow(Mixlib::ShellOut).to receive(:new)
        .with(array_including('cat-file'), any_args).and_return(shell_double(''))
      allow(Mixlib::ShellOut).to receive(:new)
        .with(array_including('diff'), any_args).and_return(shell_double(diff_output))
      allow(Mixlib::ShellOut).to receive(:new)
        .with(array_including('ls-files'), any_args).and_return(shell_double(ls_files_output))
    end

    context 'with empty output' do
      it { is_expected.to eq([]) }
    end

    {
      "A\0x\0" => [[:modified, 'x']],
      "M\0x\0" => [[:modified, 'x']],
      "M004\0x\0" => [[:modified, 'x']],
      "D\0x\0" => [[:deleted, 'x']],
      "T\0x\0" => [[:deleted, 'x'], [:modified, 'x']],
      "R\0x\0y\0" => [[:deleted, 'x'], [:modified, 'y']],
      "R100\0x\0y\0" => [[:deleted, 'x'], [:modified, 'y']],
      "C\0x\0y\0" => [[:modified, 'y']],
      "C050\0x\0y\0" => [[:modified, 'y']]
    }.each do |output, expected|
      context "with #{output.inspect}" do
        let(:diff_output) { output }

        it { is_expected.to eq(expected.map { |status, path| entry(status, path) }) }
      end
    end

    # Not sorted by path, so sorting the result would fail the example.
    context 'with several entries' do
      let(:diff_output) { "M\0f\0R050\0a\0b\0D\0c\0C\0d\0e\0" }

      it 'keeps the order of git output' do
        expect(changes).to eq([entry(:modified, 'f'), entry(:deleted, 'a'), entry(:modified, 'b'),
                               entry(:deleted, 'c'), entry(:modified, 'e')])
      end
    end

    context 'with odd characters in paths' do
      let(:diff_output) { odd_paths.map { |path| "M\0#{path}\0" }.join }

      it 'returns each path exactly' do
        expect(changes).to eq(odd_paths.map { |path| entry(:modified, path) })
      end

      it 'returns UTF-8 paths' do
        expect(changes.map { |change| change[:path].encoding }.uniq).to eq([Encoding::UTF_8])
      end
    end

    context 'with a path that is not valid UTF-8' do
      let(:diff_output) { "M\0\xFF.json\0M\0ok.json\0" }

      before { allow(logger).to receive(:warn) }

      it { is_expected.to eq([entry(:modified, 'ok.json')]) }

      it 'warns about it' do
        changes
        expect(logger).to have_received(:warn).with(/\\xFF\.json/)
      end
    end

    context 'with an unknown status' do
      let(:diff_output) { "X\0x\0" }

      before { allow(logger).to receive(:error) }

      it 'logs each token without NULs and exits', :aggregate_failures do
        expect { changes }.to raise_error(SystemExit)
        expect(logger).to have_received(:error).with('"X"')
        expect(logger).to have_received(:error).with('"x"')
      end
    end

    context 'with a truncated entry' do
      let(:diff_output) { "R100\0x\0" }

      it 'exits' do
        expect { changes }.to raise_error(SystemExit)
      end
    end

    context 'when start_ref does not exist' do
      before do
        allow(Mixlib::ShellOut).to receive(:new)
          .with(%w[git cat-file -t -- abc], any_args).and_return(missing_ref)
      end

      it 'raises ReferenceError naming it' do
        expect { changes }.to raise_error(ChefDiff::Changeset::ReferenceError, 'unknown ref "abc"')
      end
    end

    context 'when end_ref does not exist' do
      before do
        allow(Mixlib::ShellOut).to receive(:new)
          .with(%w[git cat-file -t -- def], any_args).and_return(missing_ref)
      end

      it 'raises ReferenceError naming it' do
        expect { changes }.to raise_error(ChefDiff::Changeset::ReferenceError, 'unknown ref "def"')
      end
    end

    context 'without an end_ref' do
      let(:end_ref) { nil }

      it 'checks only start_ref' do
        changes
        expect(Mixlib::ShellOut).to have_received(:new).with(array_including('cat-file'), any_args).once
      end

      it 'leaves it out of the diff argv' do
        changes
        expect(Mixlib::ShellOut).to have_received(:new)
          .with(%w[git diff --name-status --relative -z abc --], cwd: File.expand_path('foo'))
      end
    end

    context 'with HEAD as end_ref' do
      let(:end_ref) { 'HEAD' }

      it 'checks only start_ref' do
        changes
        expect(Mixlib::ShellOut).to have_received(:new).with(array_including('cat-file'), any_args).once
      end
    end

    context 'with an end_ref' do
      it 'passes it as its own diff argument' do
        changes
        expect(Mixlib::ShellOut).to have_received(:new)
          .with(%w[git diff --name-status --relative -z abc def --], cwd: File.expand_path('foo'))
      end
    end

    it 'lists files as an argv array' do
      changes
      expect(Mixlib::ShellOut).to have_received(:new)
        .with(%w[git ls-files -v -z], cwd: File.expand_path('foo'))
    end

    context 'with skip-worktree paths' do
      let(:ls_files_output) { "S web.json\0s db.json\0S a b.json\0H kept.json\0" }
      let(:diff_output) { ['web.json', 'db.json', 'a b.json', 'kept.json'].map { |p| "M\0#{p}\0" }.join }

      it { is_expected.to eq([entry(:modified, 'kept.json')]) }
    end

    context 'with 1000 changed paths' do
      let(:diff_output) { Array.new(1000) { |i| "M\0#{i}.json\0" }.join }

      it 'lists skip-worktree paths once' do
        changes
        expect(Mixlib::ShellOut).to have_received(:new).with(array_including('ls-files'), any_args).once
      end
    end
  end

  describe '#update' do
    context 'when git pull succeeds' do
      it 'returns its stdout' do
        allow(Mixlib::ShellOut).to receive(:new).and_return(shell_double("Already up to date.\n"))
        expect(git.update).to eq("Already up to date.\n")
      end

      it 'runs git pull --rebase in the checkout' do
        allow(Mixlib::ShellOut).to receive(:new).and_return(shell_double(''))
        git.update
        expect(Mixlib::ShellOut).to have_received(:new).with('git pull --rebase 2>&1', cwd: File.expand_path('foo'))
      end
    end

    context 'when git pull fails' do
      it 'raises ShellCommandFailed' do
        allow(Mixlib::ShellOut).to receive(:new).and_return(failing_shell_double)
        expect { git.update }.to raise_error(Mixlib::ShellOut::ShellCommandFailed)
      end
    end
  end

  describe '#files' do
    subject(:files) { git.files }

    let(:ls_files_output) { '' }

    before { allow(Mixlib::ShellOut).to receive(:new).and_return(shell_double(ls_files_output)) }

    context 'with empty output' do
      it { is_expected.to eq([]) }
    end

    context 'with tracked files' do
      let(:ls_files_output) { "H roles/web.json\0H cookbooks/base/metadata.rb\0" }

      it 'returns them as :created entries' do
        expect(files).to eq([{ path: 'roles/web.json', status: :created },
                             { path: 'cookbooks/base/metadata.rb', status: :created }])
      end

      it 'lists them with an argv array' do
        files
        expect(Mixlib::ShellOut).to have_received(:new)
          .with(%w[git ls-files -v -z], cwd: File.expand_path('foo'))
      end
    end

    context 'with skip-worktree entries' do
      let(:ls_files_output) { "S skip.json\0s skip too.json\0H kept one.json\0C other.json\0" }

      it 'keeps only the others' do
        expect(files.map { |file| file[:path] }).to eq(['kept one.json', 'other.json'])
      end
    end

    context 'with odd characters in paths' do
      let(:ls_files_output) { odd_paths.map { |path| "H #{path}\0" }.join }

      it 'returns each path exactly' do
        expect(files.map { |file| file[:path] }).to eq(odd_paths)
      end
    end

    context 'with unmerged paths' do
      let(:ls_files_output) { "M a.json\0M a.json\0M a.json\0H ok.json\0M b.json\0M b.json\0" }

      it 'lists each once, in first-seen order' do
        expect(files.map { |file| file[:path] }).to eq(['a.json', 'ok.json', 'b.json'])
      end
    end

    context 'with a path that is not valid UTF-8' do
      let(:ls_files_output) { "H \xFF.json\0H ok.json\0" }

      before { allow(logger).to receive(:warn) }

      it { is_expected.to eq([{ path: 'ok.json', status: :created }]) }

      it 'warns about it' do
        files
        expect(logger).to have_received(:warn).with(/\\xFF\.json/)
      end
    end

    context 'when git ls-files fails' do
      it 're-raises the error' do
        cmd = shell_double("error output\n")
        allow(cmd).to receive(:error!).and_raise(RuntimeError, 'command failed')
        allow(Mixlib::ShellOut).to receive(:new).and_return(cmd)
        expect { git.files }.to raise_error(RuntimeError, 'command failed')
      end
    end
  end

  describe '#status' do
    context 'when git status succeeds' do
      it 'returns its stdout' do
        allow(Mixlib::ShellOut).to receive(:new).and_return(shell_double(" M roles/web.json\n"))
        expect(git.status).to eq(" M roles/web.json\n")
      end
    end

    context 'when git status fails' do
      it 'raises ShellCommandFailed' do
        allow(Mixlib::ShellOut).to receive(:new).and_return(failing_shell_double)
        expect { git.status }.to raise_error(Mixlib::ShellOut::ShellCommandFailed)
      end
    end
  end

  # #setup has no output of its own; its effect is covered through #exists?.
  describe '#exists?' do
    it 'runs git rev-parse in the checkout' do
      cmd = instance_double(Mixlib::ShellOut, run_command: nil, exitstatus: 0)
      allow(Mixlib::ShellOut).to receive(:new).and_return(cmd)
      git.exists?
      expect(Mixlib::ShellOut).to have_received(:new).with(%w[git rev-parse --git-dir], cwd: File.expand_path('foo'))
    end

    context 'when the repo path does not exist' do
      it 'returns false' do
        allow(File).to receive(:exist?).and_return(false)
        expect(described_class.new('nonexistent', logger).exists?).to be false
      end
    end

    context 'when git rev-parse succeeds' do
      it 'returns true' do
        cmd = instance_double(Mixlib::ShellOut, run_command: nil, exitstatus: 0)
        allow(Mixlib::ShellOut).to receive(:new).and_return(cmd)
        expect(git.exists?).to be true
      end
    end

    context 'when git rev-parse fails' do
      it 'returns false' do
        cmd = instance_double(Mixlib::ShellOut, run_command: nil, exitstatus: 1)
        allow(Mixlib::ShellOut).to receive(:new).and_return(cmd)
        expect(git.exists?).to be false
      end
    end
  end
end
