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

# rubocop:disable ClassVars
module ChefDiff
  module Changes
    # Changeset aware node
    class Node < ChangeSingleFileNested

      def self.name_from_path(path, node_dir)
        self.name_from_path_type(path, node_dir, 'node')
      end

      def self.find(list, node_dir, logger)
        self.find_class(list, node_dir, logger, ChefDiff::Changes::Node)
      end

    end
  end
end
