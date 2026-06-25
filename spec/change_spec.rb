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
describe ChefDiff::Changes do
  include_context 'silent logger'

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
  describe ChefDiff::Changes::Change do
    describe '#full_name' do
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

    describe '#to_s' do
      it 'delegates to full_name, including path prefix for nested objects' do
        # Use a nested Node so @path is non-empty — ensures to_s != @name alone
        node = nested_node
        expect(node.to_s).to eq('dc1/server01')
        expect(node.to_s).to eq(node.full_name)
      end
    end

    describe '#logger=' do
      after { described_class.class_variable_set(:@@logger, logger) }

      it 'sets the shared class-level @@logger' do
        custom = Logger.new(File::NULL)
        flat_role.logger = custom
        expect(described_class.class_variable_get(:@@logger)).to eq(custom)
      end
    end

    describe '#info (instance delegator)' do
      it 'delegates to the class-level info method' do
        role = flat_role # build before stubbing — find calls info during construction
        expect(described_class).to receive(:info).with('hello')
        role.info('hello')
      end
    end

    describe '#debug (instance delegator)' do
      it 'delegates to the class-level debug method' do
        role = flat_role # build before stubbing — find calls debug during construction
        expect(described_class).to receive(:debug).with('details')
        role.debug('details')
      end
    end

    describe 'nil-logger no-op branches' do
      before do
        @saved = described_class.class_variable_get(:@@logger)
        described_class.class_variable_set(:@@logger, nil)
      end
      after do
        described_class.class_variable_set(:@@logger, @saved)
      end

      it 'self.info is silent when @@logger is nil' do
        expect { described_class.info('msg') }.not_to raise_error
      end

      it 'self.debug is silent when @@logger is nil' do
        expect { described_class.debug('msg') }.not_to raise_error
      end
    end
  end

  # ---------------------------------------------------------------------------
  # ChangeSingleFile — initialization logic (status mapping)
  # ---------------------------------------------------------------------------
  describe ChefDiff::Changes::ChangeSingleFile do
    describe '#initialize status mapping' do
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
  end

  # ---------------------------------------------------------------------------
  # ChangeSingleFileFlat — name_from_path_type
  # ---------------------------------------------------------------------------
  describe ChefDiff::Changes::ChangeSingleFileFlat do
    describe '.name_from_path_type' do
      it 'matches a JSON file directly inside the given directory' do
        result = described_class.name_from_path_type(
          'roles/my_role.json', 'roles', 'role'
        )
        expect(result).to eq([nil, 'my_role'])
      end

      it 'includes subdirectory components in the name (flat regex captures full path)' do
        result = described_class.name_from_path_type(
          'roles/sub/my_role.json', 'roles', 'role'
        )
        expect(result).to eq([nil, 'sub/my_role'])
      end

      it 'returns nil for files outside the given directory' do
        result = described_class.name_from_path_type(
          'cookbooks/cb/recipes/default.rb', 'roles', 'role'
        )
        expect(result).to be_nil
      end

      it 'returns nil for non-JSON files' do
        result = described_class.name_from_path_type(
          'roles/my_role.rb', 'roles', 'role'
        )
        expect(result).to be_nil
      end
    end
  end

  # ---------------------------------------------------------------------------
  # ChangeSingleFileNested — name_from_path_type
  # ---------------------------------------------------------------------------
  describe ChefDiff::Changes::ChangeSingleFileNested do
    describe '.name_from_path_type' do
      it 'matches a file directly inside the given directory (no subdir)' do
        result = described_class.name_from_path_type(
          'nodes/server01.json', 'nodes', 'node'
        )
        expect(result).to eq(['', 'server01'])
      end

      it 'matches a file one directory level deep' do
        result = described_class.name_from_path_type(
          'nodes/dc1/server01.json', 'nodes', 'node'
        )
        expect(result).to eq(['dc1/', 'server01'])
      end

      it 'matches a file two directory levels deep' do
        result = described_class.name_from_path_type(
          'nodes/dc1/rack1/server01.json', 'nodes', 'node'
        )
        expect(result).to eq(['dc1/rack1/', 'server01'])
      end

      it 'returns nil for files outside the given directory' do
        result = described_class.name_from_path_type(
          'cookbooks/cb/recipes/default.rb', 'nodes', 'node'
        )
        expect(result).to be_nil
      end

      it 'returns nil for non-JSON files' do
        result = described_class.name_from_path_type(
          'nodes/server01.rb', 'nodes', 'node'
        )
        expect(result).to be_nil
      end
    end
  end
end
