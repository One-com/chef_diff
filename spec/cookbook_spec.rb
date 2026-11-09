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
require 'chef_diff/changes/change'
require 'chef_diff/changes/cookbook'
require 'chef_diff/changeset'
describe ChefDiff::Changes::Cookbook do
  include_context 'with a silent logger'
  let(:cookbook_dirs) do
    ['cookbooks/one', 'cookbooks/two']
  end

  fixtures = [
    {
      name: 'no files',
      files: [],
      result: []
    },
    {
      name: 'a modified recipe and metadata.rb',
      files: [
        {
          status: :modified,
          path: 'cookbooks/two/cb_one/recipes/test.rb'
        },
        {
          status: :modified,
          path: 'cookbooks/two/cb_one/metadata.rb'
        }
      ],
      result: [
        ['cb_one', :modified]
      ]
    },
    {
      name: 'modified and deleted recipes',
      files: [
        {
          status: :modified,
          path: 'cookbooks/one/cb_one/recipes/test.rb'
        },
        {
          status: :deleted,
          path: 'cookbooks/one/cb_one/recipes/test2.rb'
        },
        {
          status: :modified,
          path: 'cookbooks/one/cb_one/recipes/test3.rb'
        }
      ],
      result: [
        ['cb_one', :modified]
      ]
    },
    {
      name: 'a deleted metadata.rb',
      files: [
        {
          status: :modified,
          path: 'cookbooks/one/cb_one/recipes/test.rb'
        },
        {
          status: :deleted,
          path: 'cookbooks/one/cb_one/metadata.rb'
        }
      ],
      result: [
        ['cb_one', :deleted]
      ]
    },
    {
      name: 'a deleted nested fixture cookbook',
      files: [
        {
          status: :deleted,
          path: 'cookbooks/one/cb_one/test/fixtures/cookbooks/fake/metadata.rb'
        },
        {
          status: :deleted,
          path: 'cookbooks/one/cb_one/test/fixtures/cookbooks/fake/recipes/default.rb'
        },
        {
          status: :modified,
          path: 'cookbooks/one/cb_one/README.md'
        }
      ],
      result: [
        ['cb_one', :modified]
      ]
    },
    {
      name: 'a type change of metadata.rb',
      files: [
        {
          status: :deleted,
          path: 'cookbooks/one/cb_one/metadata.rb'
        },
        {
          status: :modified,
          path: 'cookbooks/one/cb_one/metadata.rb'
        }
      ],
      result: [
        ['cb_one', :modified]
      ]
    },
    {
      name: 'a deleted file ending in metadata.rb',
      files: [
        {
          status: :deleted,
          path: 'cookbooks/one/cb_one/files/default/old_metadata.rb'
        }
      ],
      result: [
        ['cb_one', :modified]
      ]
    },
    {
      name: 'the cookbook moved to another dir',
      files: [
        {
          status: :deleted,
          path: 'cookbooks/one/cb_one/recipes/test.rb'
        },
        {
          status: :deleted,
          path: 'cookbooks/one/cb_one/metadata.rb'
        },
        {
          status: :modified,
          path: 'cookbooks/two/cb_one/recipes/test.rb'
        },
        {
          status: :modified,
          path: 'cookbooks/two/cb_one/recipes/test2.rb'
        },
        {
          status: :modified,
          path: 'cookbooks/two/cb_one/metadata.rb'
        }
      ],
      result: [
        ['cb_one', :deleted],
        ['cb_one', :modified]
      ]
    },
    {
      name: 'only metadata.rb modified',
      files: [
        {
          status: :modified,
          path: 'cookbooks/two/cb_one/metadata.rb'
        }
      ],
      result: [
        ['cb_one', :modified]
      ]
    },
    {
      name: 'only the README modified',
      files: [
        {
          status: :modified,
          path: 'cookbooks/two/cb_one/README.md'
        }
      ],
      result: [
        ['cb_one', :modified]
      ]
    },
    {
      name: 'only a recipe modified',
      files: [
        {
          status: :modified,
          path: 'cookbooks/two/cb_one/recipe/default.rb'
        }
      ],
      result: [
        ['cb_one', :modified]
      ]
    },
    {
      name: 'only files outside any cookbook',
      files: [
        {
          status: :modified,
          path: 'cookbooks/two/OWNERS'
        },
        {
          status: :modified,
          path: 'cookbooks/OWNERS'
        },
        {
          status: :modified,
          path: 'OWNERS'
        }
      ],
      result: []
    }
  ]

  describe '.new' do
    subject(:cookbook) { described_class.new(files, cookbook_dirs) }

    # One file from cb_two, then many from cb_one, so a random pick would
    # rarely land on the first. The first file is neither the smallest path
    # nor the metadata.rb, so picking either of those names the wrong one.
    context 'without parts and files from two cookbooks' do
      let(:files) do
        (['cookbooks/one/cb_two/recipes/default.rb', 'cookbooks/one/cb_one/metadata.rb'] +
          Array.new(20) { |i| "cookbooks/one/cb_one/recipes/#{i}.rb" })
          .map { |path| { status: :modified, path: path } }
      end

      it 'takes the name from the first file' do
        expect(cookbook.name).to eq('cb_two')
      end
    end
  end

  describe '.name_from_path' do
    subject { described_class.name_from_path(path, dirs) }

    let(:dirs) { cookbook_dirs }

    {
      'cookbooks/one/cb/recipes/a.rb' => { cookbook_dir: 'cookbooks/one', name: 'cb' },
      'cookbooks/two/cb/metadata.rb' => { cookbook_dir: 'cookbooks/two', name: 'cb' },
      'cookbooks/one/OWNERS' => nil,
      'cookbooks/three/cb/metadata.rb' => nil,
      "foo\ncookbooks/one/cb/metadata.rb" => nil,
      'xcookbooks/one/cb/metadata.rb' => nil
    }.each do |example_path, parts|
      context "with #{example_path.inspect}" do
        let(:path) { example_path }

        it { is_expected.to eq(parts) }
      end
    end

    context 'with overlapping dirs' do
      let(:dirs) { %w[cookbooks/site cookbooks] }
      let(:path) { 'cookbooks/site/cb/metadata.rb' }

      it { is_expected.to eq(cookbook_dir: 'cookbooks/site', name: 'cb') }
    end

    context 'with a dir containing a regexp metacharacter' do
      let(:dirs) { ['cook.books'] }
      let(:path) { 'cookxbooks/cb/metadata.rb' }

      it { is_expected.to be_nil }
    end

    context 'without dirs' do
      let(:dirs) { [] }
      let(:path) { 'cookbooks/one/cb/metadata.rb' }

      it { is_expected.to be_nil }
    end
  end

  describe '.find' do
    # find stores logger in the shared @@logger; this one is live.
    after { ChefDiff::Changes::Change.class_variable_set(:@@logger, nil) }

    fixtures.each do |fixture|
      context "with #{fixture[:name]}" do
        it 'returns name and status of each cookbook' do
          changes = described_class.find(fixture[:files], cookbook_dirs, logger)
          expect(changes.map { |change| [change.full_name, change.status] }).to eq(fixture[:result])
        end
      end
    end

    context 'with a logger at INFO' do
      let(:log) { StringIO.new }
      let(:logger) { Logger.new(log, level: :info) }
      let(:files) do
        %w[cookbooks/one/a/metadata.rb cookbooks/one/a/recipes/x.rb cookbooks/two/b/metadata.rb]
          .map { |path| { status: :modified, path: path } }
      end

      it 'logs one summary line' do
        described_class.find(files, cookbook_dirs, logger)
        expect(log.string.lines)
          .to contain_exactly(include('[ChefDiff::Changes::Cookbook] 2 matched in cookbooks/one, cookbooks/two'))
      end
    end

    context 'without cookbook dirs' do
      subject { described_class.find([{ status: :modified, path: 'cookbooks/one/a/metadata.rb' }], nil, logger) }

      it { is_expected.to eq([]) }
    end
  end
end
