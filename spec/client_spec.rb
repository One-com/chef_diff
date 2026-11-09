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
require 'chef_diff/changes/change'
require 'chef_diff/changes/client'
describe ChefDiff::Changes::Client do
  include_context 'with a silent logger'
  let(:clients_dir) do
    'clients'
  end

  fixtures = [
    {
      name: 'no files',
      files: [],
      result: []
    },
    {
      name: 'a deleted client',
      files: [
        {
          status: :deleted,
          path: 'clients/test.json'
        },
        {
          status: :modified,
          path: 'cookbooks/two/cb_one/metadata.rb'
        }
      ],
      result: [
        ['test', :deleted]
      ]
    },
    {
      name: 'a deleted nested client',
      files: [
        {
          status: :deleted,
          path: 'clients/cluster/test.json'
        },
        {
          status: :modified,
          path: 'cookbooks/two/cb_one/metadata.rb'
        }
      ],
      result: [
        ['cluster/test', :deleted]
      ]
    },
    {
      name: 'a deleted deep nested client',
      files: [
        {
          status: :deleted,
          path: 'clients/cluster/subsys/test.json'
        },
        {
          status: :modified,
          path: 'cookbooks/two/cb_one/metadata.rb'
        }
      ],
      result: [
        ['cluster/subsys/test', :deleted]
      ]
    },
    {
      name: 'a modified client',
      files: [
        {
          status: :modified,
          path: 'cookbooks/one/cb_one/recipes/test.rb'
        },
        {
          status: :modified,
          path: 'clients/test.json'
        },
        {
          status: :modified,
          path: 'cookbooks/one/cb_one/recipes/test3.rb'
        }
      ],
      result: [
        ['test', :modified]
      ]
    },
    {
      name: 'a modified nested client',
      files: [
        {
          status: :modified,
          path: 'cookbooks/one/cb_one/recipes/test.rb'
        },
        {
          status: :modified,
          path: 'clients/cluster/test.json'
        },
        {
          status: :modified,
          path: 'cookbooks/one/cb_one/recipes/test3.rb'
        }
      ],
      result: [
        ['cluster/test', :modified]
      ]
    },
    {
      name: 'a modified deep nested client',
      files: [
        {
          status: :modified,
          path: 'cookbooks/one/cb_one/recipes/test.rb'
        },
        {
          status: :modified,
          path: 'clients/cluster/subsys/test.json'
        },
        {
          status: :modified,
          path: 'cookbooks/one/cb_one/recipes/test3.rb'
        }
      ],
      result: [
        ['cluster/subsys/test', :modified]
      ]
    }
  ]

  describe '.find' do
    fixtures.each do |fixture|
      context "with #{fixture[:name]}" do
        it 'returns full name and status of its files' do
          changes = described_class.find(fixture[:files], clients_dir, logger)
          expect(changes.map { |change| [change.full_name, change.status] }).to eq(fixture[:result])
        end
      end
    end
  end
end
