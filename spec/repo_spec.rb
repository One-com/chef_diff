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
  include_context 'silent logger'
  let(:class_interface) { described_class.public_methods.sort }
  let(:instance_interface) { described_class.instance_methods.sort }

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
    it 'raises for unknown repo types' do
      expect do
        described_class.get('unknown', '/tmp', logger)
      end.to raise_error(RuntimeError, 'Do not know repo type unknown')
    end

    it 'returns a Svn instance for svn type' do
      repo = described_class.get('svn', '/tmp', logger)
      expect(repo).to be_a(ChefDiff::Repo::Svn)
    end

    it 'returns a Git instance for git type' do
      allow_any_instance_of(ChefDiff::Repo::Git).to receive(:setup)
      repo = described_class.get('git', '/tmp', logger)
      expect(repo).to be_a(ChefDiff::Repo::Git)
    end
  end

  describe '#initialize rescue path' do
    it 'warns and exits when setup raises' do
      allow(logger).to receive(:warn)
      # Base Repo#setup raises 'Not implemented', triggering the rescue → exit(1)
      expect { described_class.new('/tmp', logger) }.to raise_error(SystemExit)
      expect(logger).to have_received(:warn).with(a_string_matching(/Unable to read repo/))
    end
  end

  describe 'stub methods all raise RuntimeError' do
    let(:repo) do
      allow_any_instance_of(ChefDiff::Repo).to receive(:setup)
      described_class.new('/tmp', logger)
    end

    %i[exists? status head_rev head_msg head_parents latest_revision
       files head checkout last_author last_msg].each do |meth|
      it "##{meth} raises 'Not implemented'" do
        expect { repo.send(meth) }.to raise_error(RuntimeError, 'Not implemented')
      end
    end

    it "#create raises 'Not implemented'" do
      expect { repo.send(:create, 'http://example.com/repo') }
        .to raise_error(RuntimeError, 'Not implemented')
    end

    it "#changes raises 'Not implemented'" do
      expect { repo.send(:changes, 'a', 'b') }
        .to raise_error(RuntimeError, 'Not implemented')
    end

    it "#head_msg= raises 'Not implemented'" do
      expect { repo.send(:head_msg=) }.to raise_error(RuntimeError, 'Not implemented')
    end

    it "#last_msg= raises 'Not implemented'" do
      expect { repo.send(:last_msg=) }.to raise_error(RuntimeError, 'Not implemented')
    end

    it "#setup raises 'Not implemented'" do
      # allocate bypasses initialize (and any any_instance stub applied via let)
      raw = described_class.allocate
      expect { raw.setup }.to raise_error(RuntimeError, 'Not implemented')
    end

    it "#update raises 'Not implemented'" do
      expect { repo.update }.to raise_error(RuntimeError, 'Not implemented')
    end
  end
end
