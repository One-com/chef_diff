# vim: syntax=ruby:expandtab:shiftwidth=2:softtabstop=2:tabstop=2

# Copyright 2013-present Facebook
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
require 'chef_diff/changes/node'
require 'logger'

describe ChefDiff::Changes::Node do
  let(:logger) do
    Logger.new('/dev/null')
  end
  let(:nodes_dir) do
    'nodes'
  end

  fixtures = [
    {
      :name => 'empty filelists',
      :files => [],
      :result => [],
    },
    {
      :name => 'delete node',
      :files => [
        {
          :status => :deleted,
          :path => 'nodes/test.json'
        },
        {
          :status => :modified,
          :path => 'cookbooks/two/cb_one/metadata.rb'
        },
      ],
      :result => [
        ['test', :deleted],
      ],
    },
    {
      :name => 'delete nested node',
      :files => [
        {
          :status => :deleted,
          :path => 'nodes/cluster/test.json'
        },
        {
          :status => :modified,
          :path => 'cookbooks/two/cb_one/metadata.rb'
        },
      ],
      :result => [
        ['cluster/test', :deleted],
      ],
    },
    {
      :name => 'delete deep nested node',
      :files => [
        {
          :status => :deleted,
          :path => 'nodes/cluster/subsys/test.json'
        },
        {
          :status => :modified,
          :path => 'cookbooks/two/cb_one/metadata.rb'
        },
      ],
      :result => [
        ['cluster/subsys/test', :deleted],
      ],
    },
    {
      :name => 'add/modify a node',
      :files => [
        {
          :status => :modified,
          :path => 'cookbooks/one/cb_one/recipes/test.rb'
        },
        {
          :status => :modified,
          :path => 'nodes/test.json'
        },
        {
          :status => :modified,
          :path => 'cookbooks/one/cb_one/recipes/test3.rb'
        },
      ],
      :result => [
        ['test', :modified],
      ],
    },
    {
      :name => 'add/modify a nested node',
      :files => [
        {
          :status => :modified,
          :path => 'cookbooks/one/cb_one/recipes/test.rb'
        },
        {
          :status => :modified,
          :path => 'nodes/cluster/test.json'
        },
        {
          :status => :modified,
          :path => 'cookbooks/one/cb_one/recipes/test3.rb'
        },
      ],
      :result => [
        ['cluster/test', :modified],
      ],
    },
    {
      :name => 'add/modify a deep nested node',
      :files => [
        {
          :status => :modified,
          :path => 'cookbooks/one/cb_one/recipes/test.rb'
        },
        {
          :status => :modified,
          :path => 'nodes/cluster/subsys/test.json'
        },
        {
          :status => :modified,
          :path => 'cookbooks/one/cb_one/recipes/test3.rb'
        },
      ],
      :result => [
        ['cluster/subsys/test', :modified],
      ],
    },
  ]

  fixtures.each do |fixture|
    it "should handle #{fixture[:name]}" do
      ChefDiff::Changes::Node.find(
        fixture[:files],
        nodes_dir,
        logger
      ).map do |cb|
        [cb.full_name, cb.status]
      end.
      should eq(fixture[:result])
    end
  end

end
