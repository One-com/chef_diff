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
require 'chef_diff/changeset'
require 'chef_diff/repo'
describe ChefDiff::Changeset do
  include_context 'with a silent logger'
  let(:repo) { instance_double(ChefDiff::Repo) }
  let(:locations) do
    {
      cookbook_dirs: ['cookbooks'],
      role_dir: 'roles',
      role_local_dir: 'roles_local',
      node_dir: 'nodes',
      client_dir: 'clients',
      environment_dir: 'environments',
      databag_dir: 'databags',
      user_dir: 'users'
    }
  end

  context 'when start_ref is provided' do
    subject(:changeset) { described_class.new(logger, repo, 'abc123', 'def456', locations) }

    let(:changed_files) do
      [
        { status: :modified, path: 'roles/web.json' },
        { status: :modified, path: 'environments/production.json' },
        { status: :modified, path: 'cookbooks/my_cb/recipes/default.rb' }
      ]
    end

    before { allow(repo).to receive_messages(changes: changed_files, files: []) }

    it 'calls repo.changes with the supplied refs' do
      changeset
      expect(repo).to have_received(:changes).with('abc123', 'def456')
    end

    it 'does not call repo.files' do
      changeset
      expect(repo).not_to have_received(:files)
    end

    it 'returns changed roles' do
      expect(changeset.roles).to contain_exactly(have_attributes(name: 'web', status: :modified))
    end

    it 'returns changed environments' do
      expect(changeset.environments).to contain_exactly(have_attributes(name: 'production'))
    end

    it 'returns changed cookbooks' do
      expect(changeset.cookbooks).to contain_exactly(have_attributes(name: 'my_cb', status: :modified))
    end

    %i[users nodes clients databags roles_local].each do |meth|
      it "returns no #{meth}" do
        expect(changeset.public_send(meth)).to eq([])
      end
    end
  end

  context 'when start_ref is nil (full repo scan)' do
    subject(:changeset) { described_class.new(logger, repo, nil, nil, locations) }

    let(:all_files) do
      [
        { status: :created, path: 'roles/base.json' },
        { status: :created, path: 'nodes/web01.json' },
        { status: :created, path: 'databags/secrets/item1.json' },
        { status: :created, path: 'users/admin.json' },
        { status: :created, path: 'clients/node1.json' },
        { status: :created, path: 'environments/staging.json' },
        { status: :created, path: 'roles_local/env1/web.json' },
        { status: :created, path: 'cookbooks/base_cb/metadata.rb' }
      ]
    end

    before { allow(repo).to receive_messages(files: all_files, changes: []) }

    it 'calls repo.files' do
      changeset
      expect(repo).to have_received(:files)
    end

    it 'does not call repo.changes' do
      changeset
      expect(repo).not_to have_received(:changes)
    end

    {
      roles: { name: 'base' },
      nodes: { name: 'web01' },
      databags: { name: 'secrets' },
      users: { name: 'admin' },
      clients: { name: 'node1' },
      environments: { name: 'staging' },
      roles_local: { full_name: 'env1/web' },
      cookbooks: { name: 'base_cb' }
    }.each do |meth, attributes|
      it "returns all #{meth}" do
        expect(changeset.public_send(meth)).to contain_exactly(have_attributes(attributes))
      end
    end
  end

  context 'without cookbook_dirs in the locations' do
    subject(:changeset) { described_class.new(logger, repo, 'a', 'b', locations.merge(cookbook_dirs: nil)) }

    before { allow(repo).to receive(:changes).and_return([{ status: :modified, path: 'cookbooks/cb/metadata.rb' }]) }

    it '#cookbooks returns []' do
      expect(changeset.cookbooks).to eq([])
    end
  end

  context 'with an empty file list' do
    subject(:changeset) { described_class.new(logger, repo, 'a', 'b', locations) }

    before { allow(repo).to receive(:changes).and_return([]) }

    %i[cookbooks roles roles_local nodes clients environments databags users].each do |meth|
      it "##{meth} returns []" do
        expect(changeset.public_send(meth)).to eq([])
      end
    end
  end
end
