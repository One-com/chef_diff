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
require 'chef_diff/repo'
require 'chef_diff/repo/git'
require 'chef_diff/repo/svn'
describe ChefDiff::Repo do
  include_context 'with a silent logger'
  let(:class_interface) { described_class.public_methods.sort }
  let(:instance_interface) { described_class.instance_methods.sort }
  # allocate skips initialize, whose base #setup raises; the abstract methods
  # need no state.
  let(:repo) { described_class.allocate }

  # Misc Repos should not expose anything more than parent class,
  # which default to 'Not implemented'
  [ChefDiff::Repo::Git, ChefDiff::Repo::Svn].each do |klass|
    it "#{klass} conforms to ChefDiff::Repo class interface" do
      expect(klass.public_methods.sort).to eq(class_interface)
    end

    it "#{klass} conforms to ChefDiff::Repo instance interface" do
      expect(klass.instance_methods.sort).to eq(instance_interface)
    end
  end

  describe '.get' do
    context 'with an unknown type' do
      it 'raises' do
        expect do
          described_class.get('unknown', '/tmp', logger)
        end.to raise_error(RuntimeError, 'Do not know repo type unknown')
      end
    end

    context 'with svn' do
      it 'returns a Svn instance' do
        expect(described_class.get('svn', '/tmp', logger)).to be_a(ChefDiff::Repo::Svn)
      end
    end

    context 'with git' do
      it 'returns a Git instance' do
        git = instance_double(ChefDiff::Repo::Git)
        allow(ChefDiff::Repo::Git).to receive(:new).with('/tmp', logger).and_return(git)
        expect(described_class.get('git', '/tmp', logger)).to be(git)
      end
    end
  end

  # The base class only defines the interface; every method must be overridden.
  %i[exists? status setup head_rev head_msg head_msg= head_parents latest_revision
     update files head checkout last_author last_msg last_msg=].each do |meth|
    describe "##{meth}" do
      it 'raises Not implemented' do
        expect { repo.public_send(meth) }.to raise_error(RuntimeError, 'Not implemented')
      end
    end
  end

  describe '#create' do
    it 'raises Not implemented' do
      expect { repo.create('http://example.com/repo') }.to raise_error(RuntimeError, 'Not implemented')
    end
  end

  describe '#changes' do
    it 'raises Not implemented' do
      expect { repo.changes('a', 'b') }.to raise_error(RuntimeError, 'Not implemented')
    end
  end
end
