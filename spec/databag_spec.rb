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
require 'chef_diff/changes/databag'
describe ChefDiff::Changes::Databag do
  include_context 'with a silent logger'
  let(:databags_dir) do
    'databags'
  end

  fixtures = [
    {
      name: 'no files',
      files: [],
      result: []
    },
    {
      name: 'a deleted item',
      files: [
        {
          status: :deleted,
          path: 'databags/test/databag1.json'
        },
        {
          status: :deleted,
          path: 'databags/test1/test2/databag2.json'
        },
        {
          status: :modified,
          path: 'cookbooks/two/cb_one/metadata.rb'
        }
      ],
      result: [
        ['test', 'databag1', :deleted]
      ]
    },
    {
      name: 'items of two databags',
      files: [
        {
          status: :modified,
          path: 'databags/one/databag1.json'
        },
        {
          status: :deleted,
          path: 'databags/test/databag2.rb' # wrong extension
        },
        {
          status: :deleted,
          path: 'databags/two/databag3.json'
        }
      ],
      result: [
        ['one', 'databag1', :modified], ['two', 'databag3', :deleted]
      ]
    }
  ]

  # full_name is the databag alone, so the item is checked separately.
  describe '.find' do
    fixtures.each do |fixture|
      context "with #{fixture[:name]}" do
        it 'returns databag, item and status' do
          changes = described_class.find(fixture[:files], databags_dir, logger)
          expect(changes.map { |change| [change.full_name, change.item, change.status] }).to eq(fixture[:result])
        end
      end
    end
  end

  context 'with a :created file' do
    subject { described_class.find([{ status: :created, path: 'databags/one/item.json' }], databags_dir, logger) }

    it { is_expected.to contain_exactly(have_attributes(status: :modified)) }
  end

  describe '.name_from_path' do
    subject { described_class.name_from_path(path, dir) }

    let(:dir) { 'databags' }

    {
      'databags/b/i.json' => %w[b i],
      'databags/b/i.y.json' => %w[b i.y],
      'databags/b/i.json.bak' => nil,
      'databags/b/abcjson' => nil,
      'databags/b/.json' => nil,
      'databags/i.json' => nil,
      'databags/b/c/i.json' => nil,
      "foo\ndatabags/b/i.json" => nil,
      'xdatabags/b/i.json' => nil
    }.each do |example_path, parts|
      context "with #{example_path.inspect}" do
        let(:path) { example_path }

        it { is_expected.to eq(parts) }
      end
    end

    context 'with a dir containing a regexp metacharacter' do
      let(:dir) { 'data.bags' }
      let(:path) { 'dataxbags/b/i.json' }

      it { is_expected.to be_nil }
    end

    context 'with a nil dir' do
      let(:dir) { nil }
      let(:path) { '/b/i.json' }

      it { is_expected.to be_nil }
    end
  end
end
