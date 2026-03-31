# frozen_string_literal: true

require "bigdecimal"
require "date"
require "logger"
require "stringio"

require_relative "test_helper"
require_relative "../lib/airbnb_payous/bigquery_gateway"

class BigqueryGatewayTest < Minitest::Test
  class FakeStorage
    attr_reader :bucket_calls

    def initialize(content: "csv")
      @content = content
      @bucket_calls = []
    end

    def bucket(name)
      @bucket_calls << name
      FakeBucket.new(@content)
    end
  end

  class FakeBucket
    attr_reader :file_calls

    def initialize(content)
      @content = content
      @file_calls = []
    end

    def file(name)
      @file_calls << name
      FakeFile.new(@content)
    end
  end

  class FakeFile
    def initialize(content)
      @content = content
    end

    def download
      StringIO.new(@content)
    end
  end

  class FakeSchema
    attr_reader :fields

    def initialize
      @fields = []
    end

    def date(name, mode:) = @fields << [:date, name, mode]
    def string(name, mode:) = @fields << [:string, name, mode]
    def integer(name, mode:) = @fields << [:integer, name, mode]
    def numeric(name, mode:) = @fields << [:numeric, name, mode]
  end

  class FakeLoadJob
    attr_reader :waited

    def initialize(output_rows: 1)
      @waited = false
      @output_rows = output_rows
    end

    def wait_until_done!
      @waited = true
    end

    def failed?
      false
    end

    def output_rows
      @output_rows
    end

    def error; nil; end
  end

  class FakeCopyJob < FakeLoadJob
    def error; nil; end
  end

  class FakeQueryJob < FakeLoadJob
    attr_reader :sql

    def initialize(inserted: 1, updated: 0)
      super()
      @dml_stats = Struct.new(:inserted_row_count, :updated_row_count).new(inserted, updated)
    end

    def dml_stats
      @dml_stats
    end

    def error; nil; end
  end

  class FakeTable
    attr_reader :deleted

    def initialize(raises_on_delete: false)
      @raises_on_delete = raises_on_delete
      @deleted = false
    end

    def delete
      raise "cannot delete" if @raises_on_delete

      @deleted = true
    end
  end

  class FakeDataset
    attr_reader :load_job_calls, :table_requests, :loaded_json, :schema_fields

    def initialize(target_table:, staging_table:, output_rows: 1)
      @target_table = target_table
      @staging_table = staging_table
      @output_rows = output_rows
      @load_job_calls = []
      @table_requests = []
      @loaded_json = []
      @schema_fields = []
    end

    def load_job(table_id, path, **kwargs)
      @load_job_calls << [table_id, kwargs]
      @loaded_json << File.read(path)
      schema = FakeSchema.new
      updater = Object.new
      updater.define_singleton_method(:schema) do |&block|
        block.call(schema)
      end
      yield updater
      @schema_fields = schema.fields
      FakeLoadJob.new(output_rows: @output_rows)
    end

    def table(name)
      @table_requests << name
      return @target_table if name == "table"
      return @staging_table if name == "table_staging"

      nil
    end
  end

  class FakeBigquery
    attr_reader :dataset_calls, :create_dataset_calls, :copy_job_calls, :query_job_calls

    def initialize(dataset:, created_dataset: nil)
      @dataset = dataset
      @created_dataset = created_dataset || dataset
      @dataset_calls = []
      @create_dataset_calls = []
      @copy_job_calls = []
      @query_job_calls = []
    end

    def dataset(name)
      @dataset_calls << name
      @dataset
    end

    def create_dataset(name)
      @create_dataset_calls << name
      @created_dataset
    end

    def copy_job(source, destination, write:)
      @copy_job_calls << { source:, destination:, write: }
      FakeCopyJob.new
    end

    def query_job(sql)
      @query_job_calls << sql
      FakeQueryJob.new
    end
  end

  def setup
    @logger = Logger.new(StringIO.new)
    @staging_table = FakeTable.new
    @target_table = Object.new
    @dataset = FakeDataset.new(target_table: @target_table, staging_table: @staging_table)
    @bigquery = FakeBigquery.new(dataset: @dataset)
    @storage = FakeStorage.new(content: "csv")
    @gateway = AirbnbPayous::BigqueryGateway.new(
      project_id: "project",
      dataset_id: "dataset",
      table_id: "table",
      logger: @logger,
      bigquery: @bigquery,
      storage: @storage
    )
    @rows = [
      {
        "event_date" => Date.new(2026, 3, 12),
        "amount" => BigDecimal("150.50"),
        "row_id" => "abc123"
      }
    ]
  end

  def test_downloads_csv_bytes_from_cloud_storage
    assert_equal "csv", @gateway.download(bucket_name: "bucket", file_name: "file.csv")
    assert_equal ["bucket"], @storage.bucket_calls
  end

  def test_copies_the_staging_table_on_the_first_run
    dataset = FakeDataset.new(target_table: nil, staging_table: FakeTable.new)
    bigquery = FakeBigquery.new(dataset: dataset)
    gateway = AirbnbPayous::BigqueryGateway.new(
      project_id: "project",
      dataset_id: "dataset",
      table_id: "table",
      logger: @logger,
      bigquery: bigquery,
      storage: @storage
    )

    result = gateway.load_and_merge!(rows: @rows)

    assert_equal :create_table, result[:mode]
    assert_equal @rows.length, result[:inserted_count]
    assert_equal 0, result[:updated_count]

    assert_equal 1, bigquery.copy_job_calls.length
    assert_equal "project.dataset.table_staging", bigquery.copy_job_calls.first[:source]
    assert_equal "project.dataset.table", bigquery.copy_job_calls.first[:destination]
    assert_empty bigquery.query_job_calls
    assert dataset.table("table_staging").deleted
  end

  def test_merges_into_an_existing_target_table
    result = @gateway.load_and_merge!(rows: @rows)

    assert_equal :merge, result[:mode]
    assert_equal 1, result[:inserted_count]
    assert_equal 0, result[:updated_count]

    assert_equal 1, @bigquery.query_job_calls.length
    assert_includes @bigquery.query_job_calls.first, "MERGE `project.dataset.table`"
    assert_empty @bigquery.copy_job_calls
  end

  def test_serializes_dates_and_decimals_for_bigquery_load_jobs
    @gateway.load_and_merge!(rows: @rows)

    json = @dataset.loaded_json.last
    assert_includes json, "\"event_date\":\"2026-03-12\""
    assert_includes json, "\"amount\":\"150.5\""
    assert_includes json, "\"row_id\":\"abc123\""
  end

  def test_creates_dataset_when_it_does_not_already_exist
    created_dataset = FakeDataset.new(target_table: @target_table, staging_table: FakeTable.new)
    bigquery = FakeBigquery.new(dataset: nil, created_dataset: created_dataset)
    gateway = AirbnbPayous::BigqueryGateway.new(
      project_id: "project",
      dataset_id: "dataset",
      table_id: "table",
      logger: @logger,
      bigquery: bigquery,
      storage: @storage
    )

    gateway.load_and_merge!(rows: @rows)

    assert_equal ["dataset"], bigquery.create_dataset_calls
    assert_equal 1, bigquery.query_job_calls.length
  end

  def test_cleans_up_gracefully_when_staging_table_deletion_fails
    dataset = FakeDataset.new(target_table: @target_table, staging_table: FakeTable.new(raises_on_delete: true))
    bigquery = FakeBigquery.new(dataset: dataset)
    gateway = AirbnbPayous::BigqueryGateway.new(
      project_id: "project",
      dataset_id: "dataset",
      table_id: "table",
      logger: @logger,
      bigquery: bigquery,
      storage: @storage
    )

    gateway.load_and_merge!(rows: @rows)

    assert_equal 1, bigquery.query_job_calls.length
  end

  def test_returns_fully_qualified_table_names
    assert_equal "project.dataset.table", @gateway.qualified_table_name("table")
  end
end
