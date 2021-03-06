#    Copyright 2020 Couchbase, Inc.
#
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.

require_relative "test_helper"

require "couchbase/datastructures/couchbase_set"

module Couchbase
  module Datastructures
    class CouchbaseSetTest < BaseTest
      def setup
        options = Cluster::ClusterOptions.new
        options.authenticate(TEST_USERNAME, TEST_PASSWORD)
        @cluster = Cluster.connect(TEST_CONNECTION_STRING, options)
        @bucket = @cluster.bucket(TEST_BUCKET)
        @collection = @bucket.default_collection
      end

      def teardown
        @cluster.disconnect
      end

      def uniq_id(name)
        "#{name}_#{Time.now.to_f}"
      end

      def test_new_set_empty
        doc_id = uniq_id(:foo)
        set = CouchbaseSet.new(doc_id, @collection)
        assert_equal 0, set.size
        assert set.empty?
      end

      def test_new_set_yields_no_elements
        doc_id = uniq_id(:foo)
        set = CouchbaseSet.new(doc_id, @collection)
        actual = []
        set.each do |element|
          actual << element
        end
        assert_equal [], actual
      end

      def test_add_does_not_create_duplicates
        doc_id = uniq_id(:foo)
        set = CouchbaseSet.new(doc_id, @collection)

        set.add("foo")
        set.add("foo")

        actual = []
        set.each do |element|
          actual << element
        end
        assert_equal %w[foo], actual
      end

      def test_has_methods_to_check_inclusivity
        doc_id = uniq_id(:foo)
        set = CouchbaseSet.new(doc_id, @collection)

        set.add("foo").add("bar")

        refute set.empty?
        assert_equal 2, set.size

        assert set.include?("foo")
        assert set.include?("bar")
        refute set.include?("baz")
      end

      def test_removes_the_item
        doc_id = uniq_id(:foo)
        set = CouchbaseSet.new(doc_id, @collection)

        set.add("foo").add("bar")
        assert_equal 2, set.size

        set.delete("bar")
        assert_equal 1, set.size

        assert set.include?("foo")
        refute set.include?("bar")
      end
    end
  end
end
