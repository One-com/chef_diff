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
require 'chef_diff/changes/environment'
require 'logger'

describe ChefDiff::Changes::Environment do
  let(:logger) do
    Logger.new('/dev/null')
  end
  let(:environments_dir) do
    'environments'
  end

  fixtures = [
    {
      :name => 'empty filelists',
      :files => [],
      :result => [],
    },
    {
      :name => 'delete environment',
      :files => [
        {
          :status => :deleted,
          :path => 'environments/test.json'
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
      :name => 'delete nested environment',
      :files => [
        {
          :status => :deleted,
          :path => 'environments/cluster/test.json'
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
      :name => 'delete deep nested environment',
      :files => [
        {
          :status => :deleted,
          :path => 'environments/cluster/subsys/test.json'
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
      :name => 'add/modify a environment',
      :files => [
        {
          :status => :modified,
          :path => 'cookbooks/one/cb_one/recipes/test.rb'
        },
        {
          :status => :modified,
          :path => 'environments/test.json'
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
      :name => 'add/modify a nested environment',
      :files => [
        {
          :status => :modified,
          :path => 'cookbooks/one/cb_one/recipes/test.rb'
        },
        {
          :status => :modified,
          :path => 'environments/cluster/test.json'
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
      :name => 'add/modify a deep nested environment',
      :files => [
        {
          :status => :modified,
          :path => 'cookbooks/one/cb_one/recipes/test.rb'
        },
        {
          :status => :modified,
          :path => 'environments/cluster/subsys/test.json'
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
      ChefDiff::Changes::Environment.find(
        fixture[:files],
        environments_dir,
        logger
      ).map do |cb|
        [cb.full_name, cb.status]
      end.
      should eq(fixture[:result])
    end
  end

end
