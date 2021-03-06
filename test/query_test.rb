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

module Couchbase
  class QueryTest < Minitest::Test
    def setup
      options = Cluster::ClusterOptions.new
      options.authenticate(TEST_USERNAME, TEST_PASSWORD)
      @cluster = Cluster.connect(TEST_CONNECTION_STRING, options)
      @bucket = @cluster.bucket(TEST_BUCKET)
      @collection = @bucket.default_collection
      options = Management::QueryIndexManager::CreatePrimaryIndexOptions.new
      options.ignore_if_exists = true
      options.timeout = 300_000 # give it up to 5 minutes
      @cluster.query_indexes.create_primary_index(@bucket.name, options)
    end

    def teardown
      @cluster.disconnect
    end

    def uniq_id(name)
      "#{name}_#{Time.now.to_f}"
    end

    def test_simple_query
      res = @cluster.query('SELECT "ruby rules" AS greeting')
      assert_equal "ruby rules", res.rows.first["greeting"]
    end

    def test_query_with_metrics
      options = Cluster::QueryOptions.new
      options.metrics = true
      res = @cluster.query('SELECT "ruby rules" AS greeting', options)
      assert_equal "ruby rules", res.rows.first["greeting"]

      metrics = res.meta_data.metrics
      refute metrics.error_count
      refute metrics.warning_count
      assert_equal 1, metrics.result_count
    end

    def test_query_with_all_options
      doc_id = uniq_id(:foo)
      @collection.insert(doc_id, {"foo" => "bar"})

      options = Cluster::QueryOptions.new
      options.adhoc = true
      options.client_context_id = "123"
      options.max_parallelism = 3
      options.metrics = true
      options.pipeline_batch = 1
      options.pipeline_cap = 1
      options.readonly = true
      options.scan_cap = 10
      options.scan_consistency = :request_plus
      options.scan_wait = 50

      res = @cluster.query("SELECT * FROM `#{@bucket.name}` WHERE META().id = \"#{doc_id}\"", options)

      assert_equal :success, res.meta_data.status
      assert_equal "123", res.meta_data.client_context_id
      assert res.meta_data.metrics
    end

    def test_readonly_violation
      options = Cluster::QueryOptions.new
      options.readonly = true

      assert_raises Error::InternalServerFailure do
        @cluster.query("INSERT INTO `#{@bucket.name}` (key, value) VALUES (\"foo\", \"bar\")", options)
      end
    end

    def test_select
      doc_id = uniq_id(:foo)
      @collection.insert(doc_id, {"foo" => "bar"})

      options = Cluster::QueryOptions.new
      options.scan_consistency = :request_plus

      res = @cluster.query("SELECT * FROM `#{@bucket.name}` AS doc WHERE META().id = \"#{doc_id}\"", options)

      assert res.meta_data.request_id
      assert res.meta_data.client_context_id
      assert_equal :success, res.meta_data.status
      refute res.meta_data.warnings
      assert res.meta_data.signature

      rows = res.rows
      assert_equal 1, rows.size
      assert_equal({"foo" => "bar"}, rows.first["doc"])
    end

    def test_select_with_profile
      options = Cluster::QueryOptions.new

      options.profile = :off
      res = @cluster.query('SELECT "ruby rules" AS greeting', options)
      refute res.meta_data.profile

      options.profile = :timings
      res = @cluster.query('SELECT "ruby rules" AS greeting', options)
      assert_kind_of Hash, res.meta_data.profile

      options.profile = :phases
      res = @cluster.query('SELECT "ruby rules" AS greeting', options)
      assert_kind_of Hash, res.meta_data.profile
    end

    def test_parsing_error_on_bad_query
      assert_raises(Error::ParsingFailure) do
        @cluster.query('BAD QUERY')
      end
    end

    def test_query_with_named_parameters
      doc_id = uniq_id(:foo)
      @collection.insert(doc_id, {"foo" => "bar"})

      options = Cluster::QueryOptions.new
      options.scan_consistency = :request_plus
      options.named_parameters("id" => doc_id)

      res = @cluster.query("SELECT `#{@bucket.name}`.* FROM `#{@bucket.name}` WHERE META().id = $id", options)
      assert_equal 1, res.rows.size
      assert_equal({"foo" => "bar"}, res.rows.first)
    end

    def test_query_with_positional_parameters
      doc_id = uniq_id(:foo)
      @collection.insert(doc_id, {"foo" => "bar"})

      options = Cluster::QueryOptions.new
      options.scan_consistency = :request_plus
      options.positional_parameters([doc_id])

      res = @cluster.query("SELECT `#{@bucket.name}`.* FROM `#{@bucket.name}` WHERE META().id = $1", options)
      assert_equal 1, res.rows.size
      assert_equal({"foo" => "bar"}, res.rows.first)
    end

    def test_consistent_with
      doc_id = uniq_id(:foo)
      res = @collection.insert(doc_id, {"foo" => "bar"})

      options = Cluster::QueryOptions.new
      options.consistent_with(MutationState.new(res.mutation_token))
      options.positional_parameters([doc_id])

      res = @cluster.query("SELECT `#{@bucket.name}`.* FROM `#{@bucket.name}` WHERE META().id = $1", options)
      assert_equal 1, res.rows.size
      assert_equal({"foo" => "bar"}, res.rows.first)
    end
  end
end
