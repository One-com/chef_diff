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
require 'chef_diff/changes/change'
require 'chef_diff/changes/role'
require 'chef_diff/changes/role_local'
require 'chef_diff/changes/node'
# Paths that name no object in 'dir', for flat and nested kinds alike.
rejected_paths = [
  'dir/abcjson',
  "dir/x.json\nfoo",
  "foo\ndir/x.json",
  'dir/.json',
  'dir/a/.json',
  'otherdir/x.json',
  'xdir/x.json',
  'dir2/x.json',
  'dir/x.json.bak',
  'dir/x.rb'
]

describe ChefDiff::Changes do
  include_context 'with a silent logger'

  # A concrete flat change (Role): @path is nil, so full_name == @name.
  def flat_role(status: :modified, path: 'roles/my_role.json')
    ChefDiff::Changes::Role.find([{ status: status, path: path }], 'roles', logger).first
  end

  # A concrete nested change (Node): @path is non-empty, so full_name is prefixed.
  def nested_node(status: :modified, path: 'nodes/dc1/server01.json')
    ChefDiff::Changes::Node.find([{ status: status, path: path }], 'nodes', logger).first
  end

  # ---------------------------------------------------------------------------
  # Change (base class) — exercised through concrete subclasses
  # ---------------------------------------------------------------------------
  describe ChefDiff::Changes::Change, '#full_name' do
    context 'when path is nil (flat structure)' do
      it 'returns only the name' do
        expect(flat_role.full_name).to eq('my_role')
      end
    end

    context 'when path is a subdirectory (nested structure)' do
      it 'prepends the path to the name' do
        expect(nested_node.full_name).to eq('dc1/server01')
      end
    end
  end

  describe ChefDiff::Changes::Change, '#to_s' do
    it 'returns the full name' do
      # A nested Node, so @path is non-empty and to_s != @name alone
      expect(nested_node.to_s).to eq('dc1/server01')
    end
  end

  describe ChefDiff::Changes::Change, '#logger=' do
    after { described_class.class_variable_set(:@@logger, logger) }

    it 'sets the shared class-level @@logger' do
      custom = Logger.new(File::NULL)
      flat_role.logger = custom
      expect(described_class.class_variable_get(:@@logger)).to eq(custom)
    end
  end

  describe ChefDiff::Changes::Change, '#info' do
    it 'delegates to the class-level info method' do
      allow(described_class).to receive(:info)
      flat_role.info('hello')
      expect(described_class).to have_received(:info).with('hello')
    end
  end

  describe ChefDiff::Changes::Change, '#debug' do
    it 'delegates to the class-level debug method' do
      allow(described_class).to receive(:debug)
      flat_role.debug('details')
      expect(described_class).to have_received(:debug).with('details')
    end
  end

  describe ChefDiff::Changes::Change, '.info' do
    context 'without a logger' do
      before { described_class.class_variable_set(:@@logger, nil) }
      after { described_class.class_variable_set(:@@logger, logger) }

      it 'does not raise' do
        expect { described_class.info('msg') }.not_to raise_error
      end
    end
  end

  describe ChefDiff::Changes::Change, '.debug' do
    context 'without a logger' do
      before { described_class.class_variable_set(:@@logger, nil) }
      after { described_class.class_variable_set(:@@logger, logger) }

      it 'does not raise' do
        expect { described_class.debug('msg') }.not_to raise_error
      end
    end
  end

  # ---------------------------------------------------------------------------
  # ChangeSingleFile — initialization logic (status mapping)
  # ---------------------------------------------------------------------------
  describe ChefDiff::Changes::ChangeSingleFile, '.new' do
    it 'maps :deleted file status to :deleted' do
      expect(flat_role(status: :deleted, path: 'roles/gone.json').status).to eq(:deleted)
    end

    it 'maps :modified file status to :modified' do
      expect(flat_role(status: :modified, path: 'roles/changed.json').status).to eq(:modified)
    end

    it 'maps :created file status to :modified (full-upload scenario)' do
      expect(flat_role(status: :created, path: 'roles/new_role.json').status).to eq(:modified)
    end
  end

  # ---------------------------------------------------------------------------
  # ChangeSingleFileFlat — name_from_path
  # ---------------------------------------------------------------------------
  describe ChefDiff::Changes::ChangeSingleFileFlat, '.name_from_path' do
    subject { described_class.name_from_path(path, dir) }

    let(:dir) { 'dir' }

    {
      'dir/x.json' => [nil, 'x'],
      'dir/a/x.json' => [nil, 'a/x'],
      'dir/a/b/x.json' => [nil, 'a/b/x'],
      'dir/x.y.json' => [nil, 'x.y'],
      'dir/my rôle ü.json' => [nil, 'my rôle ü']
    }.each do |matching, parts|
      context "with #{matching}" do
        let(:path) { matching }

        it { is_expected.to eq(parts) }
      end
    end

    rejected_paths.each do |rejected|
      context "with #{rejected.inspect}" do
        let(:path) { rejected }

        it { is_expected.to be_nil }
      end
    end

    context 'with a nil dir' do
      let(:dir) { nil }
      let(:path) { '/x.json' }

      it { is_expected.to be_nil }
    end
  end

  # ---------------------------------------------------------------------------
  # ChangeSingleFileNested — name_from_path
  # ---------------------------------------------------------------------------
  describe ChefDiff::Changes::ChangeSingleFileNested, '.name_from_path' do
    subject { described_class.name_from_path(path, dir) }

    let(:dir) { 'dir' }

    {
      'dir/x.json' => ['', 'x'],
      'dir/a/x.json' => ['a/', 'x'],
      'dir/a/b/x.json' => ['a/b/', 'x'],
      'dir/x.y.json' => ['', 'x.y'],
      'dir/dc 1/sérvér ü.json' => ['dc 1/', 'sérvér ü']
    }.each do |matching, parts|
      context "with #{matching}" do
        let(:path) { matching }

        it { is_expected.to eq(parts) }
      end
    end

    rejected_paths.each do |rejected|
      context "with #{rejected.inspect}" do
        let(:path) { rejected }

        it { is_expected.to be_nil }
      end
    end

    {
      ['a.b', 'a.b/x.json'] => ['', 'x'],
      ['a.b', 'axb/x.json'] => nil,
      ['a+', 'a+/x.json'] => ['', 'x'],
      ['a+', 'aa/x.json'] => nil
    }.each do |(metachar_dir, metachar_path), parts|
      context "with dir #{metachar_dir} and #{metachar_path}" do
        let(:dir) { metachar_dir }
        let(:path) { metachar_path }

        it { is_expected.to eq(parts) }
      end
    end

    context 'with a nil dir' do
      let(:dir) { nil }
      let(:path) { '/x.json' }

      it { is_expected.to be_nil }
    end
  end

  describe ChefDiff::Changes::Change, '.find' do
    subject(:changes) { ChefDiff::Changes::Node.find(files, dir, logger) }

    # find stores logger in the shared @@logger; some contexts pass a live one.
    after { described_class.class_variable_set(:@@logger, nil) }

    let(:dir) { 'nodes' }
    let(:files) do
      %w[nodes/a.json cookbooks/cb/metadata.rb nodes/dc1/b.json roles/r.json nodes/c.json]
        .map { |path| { status: :modified, path: path } }
    end

    context 'with a path the pattern rejects' do
      let(:files) { [{ status: :modified, path: 'nodes/x.json.bak' }] }

      it { is_expected.to be_empty }
    end

    context 'with a nil dir' do
      let(:dir) { nil }

      it { is_expected.to be_empty }
    end

    context 'with several matching files' do
      # Not sorted, so a result in sort order would fail.
      let(:files) do
        %w[nodes/b.json nodes/a.json nodes/c.json].map { |path| { status: :modified, path: path } }
      end

      it 'keeps input order' do
        expect(changes.map(&:name)).to eq(%w[b a c])
      end
    end

    context 'with a logger at WARN' do
      let(:logger) { Logger.new(File::NULL, level: :warn) }

      before do
        allow(logger).to receive(:debug).and_call_original
        allow(logger).to receive(:info).and_call_original
      end

      it 'builds no debug message' do
        changes
        expect(logger).not_to have_received(:debug).with(instance_of(String))
      end

      it 'builds no info message' do
        changes
        expect(logger).not_to have_received(:info).with(instance_of(String))
      end
    end

    context 'with a logger at INFO' do
      let(:log) { StringIO.new }
      let(:logger) { Logger.new(log, level: :info) }

      it 'logs one summary line' do
        changes
        expect(log.string.lines).to contain_exactly(include('[ChefDiff::Changes::Node] 3 matched in nodes'))
      end
    end

    context 'with a logger at DEBUG' do
      let(:log) { StringIO.new }
      let(:logger) { Logger.new(log, level: :debug) }

      it 'logs each matching path' do
        changes
        expect(log.string).to include('nodes/a.json', 'nodes/dc1/b.json', 'nodes/c.json')
      end
    end
  end
end
