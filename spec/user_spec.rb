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
require 'chef_diff/changes/change'
require 'chef_diff/changes/user'
require 'logger'

describe ChefDiff::Changes::User do
  let(:logger) do
    Logger.new('/dev/null')
  end
  let(:users_dir) do
    'users'
  end

  fixtures = [
    {
      :name => 'empty filelists',
      :files => [],
      :result => [],
    },
    {
      :name => 'delete user',
      :files => [
        {
          :status => :deleted,
          :path => 'users/test.json'
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
      :name => 'delete nested user',
      :files => [
        {
          :status => :deleted,
          :path => 'users/cluster/test.json'
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
      :name => 'delete deep nested user',
      :files => [
        {
          :status => :deleted,
          :path => 'users/cluster/subsys/test.json'
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
      :name => 'add/modify a user',
      :files => [
        {
          :status => :modified,
          :path => 'cookbooks/one/cb_one/recipes/test.rb'
        },
        {
          :status => :modified,
          :path => 'users/test.json'
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
      :name => 'add/modify a nested user',
      :files => [
        {
          :status => :modified,
          :path => 'cookbooks/one/cb_one/recipes/test.rb'
        },
        {
          :status => :modified,
          :path => 'users/cluster/test.json'
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
      :name => 'add/modify a deep nested user',
      :files => [
        {
          :status => :modified,
          :path => 'cookbooks/one/cb_one/recipes/test.rb'
        },
        {
          :status => :modified,
          :path => 'users/cluster/subsys/test.json'
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
      ChefDiff::Changes::User.find(
        fixture[:files],
        users_dir,
        logger
      ).map do |cb|
        [cb.full_name, cb.status]
      end.
      should eq(fixture[:result])
    end
  end

end
