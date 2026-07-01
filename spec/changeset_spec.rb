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
describe ChefDiff::Changeset do
  include_context 'silent logger'
  let(:repo) { double('repo') }
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
    let(:changed_files) do
      [
        { status: :modified, path: 'roles/web.json' },
        { status: :modified, path: 'environments/production.json' },
        { status: :modified, path: 'cookbooks/my_cb/recipes/default.rb' }
      ]
    end

    before do
      allow(repo).to receive(:changes).with('abc123', 'def456')
                                      .and_return(changed_files)
    end

    subject { described_class.new(logger, repo, 'abc123', 'def456', locations) }

    it 'calls repo.changes with the supplied refs' do
      expect(repo).to receive(:changes).with('abc123', 'def456')
                                       .and_return(changed_files)
      described_class.new(logger, repo, 'abc123', 'def456', locations)
    end

    it 'does not call repo.files' do
      expect(repo).not_to receive(:files)
      subject
    end

    it 'returns changed roles' do
      result = subject.roles
      expect(result.length).to eq(1)
      expect(result.first.name).to eq('web')
      expect(result.first.status).to eq(:modified)
    end

    it 'returns changed environments' do
      result = subject.environments
      expect(result.length).to eq(1)
      expect(result.first.name).to eq('production')
    end

    it 'returns changed cookbooks' do
      result = subject.cookbooks
      expect(result.length).to eq(1)
      expect(result.first.name).to eq('my_cb')
      expect(result.first.status).to eq(:modified)
    end

    it 'returns empty arrays for change types with no matching files' do
      expect(subject.users).to eq([])
      expect(subject.nodes).to eq([])
      expect(subject.clients).to eq([])
      expect(subject.databags).to eq([])
      expect(subject.roles_local).to eq([])
    end
  end

  context 'when start_ref is nil (full repo scan)' do
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

    before { allow(repo).to receive(:files).and_return(all_files) }

    subject { described_class.new(logger, repo, nil, nil, locations) }

    it 'calls repo.files' do
      expect(repo).to receive(:files).and_return(all_files)
      described_class.new(logger, repo, nil, nil, locations)
    end

    it 'does not call repo.changes' do
      expect(repo).not_to receive(:changes)
      subject
    end

    it 'returns all roles' do
      result = subject.roles
      expect(result.length).to eq(1)
      expect(result.first.name).to eq('base')
    end

    it 'returns all nodes' do
      result = subject.nodes
      expect(result.length).to eq(1)
      expect(result.first.name).to eq('web01')
    end

    it 'returns all databags' do
      result = subject.databags
      expect(result.length).to eq(1)
      expect(result.first.name).to eq('secrets')
    end

    it 'returns all users' do
      result = subject.users
      expect(result.length).to eq(1)
      expect(result.first.name).to eq('admin')
    end

    it 'returns all clients' do
      result = subject.clients
      expect(result.length).to eq(1)
      expect(result.first.name).to eq('node1')
    end

    it 'returns all environments' do
      result = subject.environments
      expect(result.length).to eq(1)
      expect(result.first.name).to eq('staging')
    end

    it 'returns all roles_local' do
      result = subject.roles_local
      expect(result.length).to eq(1)
      expect(result.first.full_name).to eq('env1/web')
    end

    it 'returns all cookbooks' do
      result = subject.cookbooks
      expect(result.length).to eq(1)
      expect(result.first.name).to eq('base_cb')
    end
  end

  describe 'all accessor methods return [] for an empty file list' do
    before { allow(repo).to receive(:changes).and_return([]) }

    subject { described_class.new(logger, repo, 'a', 'b', locations) }

    %i[cookbooks roles roles_local nodes clients environments databags users].each do |meth|
      it "##{meth} returns []" do
        expect(subject.send(meth)).to eq([])
      end
    end
  end
end
