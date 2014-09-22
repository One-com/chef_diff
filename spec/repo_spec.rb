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

require 'chef_diff/repo'
require 'chef_diff/repo/git'
require 'chef_diff/repo/svn'

describe 'ChefDiff::Repo' do

  let (:class_interface) { ChefDiff::Repo.public_methods.sort }
  let (:instance_interface) { ChefDiff::Repo.instance_methods.sort }

  # Misc Repos should not expose anything more than parent class,
  # which default to 'Not implemented'
  [ChefDiff::Repo::Git, ChefDiff::Repo::Svn].each do |klass|
    it "#{klass} should conform to ChefDiff::Repo class interface" do
      klass.public_methods.sort.should eq(class_interface)
    end
    it "#{klass} should conform to ChefDiff::Repo instance interface" do
      klass.instance_methods.sort.should eq(instance_interface)
    end
  end
end
