# frozen_string_literal: true

require "logger"
require "stringio"

require_relative "test_helper"
require_relative "../lib/airbnb_payous/processor"

class ProcessorTest < Minitest::Test
  FakeTransformer = Struct.new(:rows, :received_csv) do
    def call(csv)
      self.received_csv = csv
      rows
    end
  end

  class FakeGateway
    attr_reader :download_calls, :load_calls

    def initialize(csv: "csv", error: nil)
      @csv = csv
      @error = error
      @download_calls = []
      @load_calls = []
    end

    def download(bucket_name:, file_name:)
      raise @error if @error

      @download_calls << { bucket_name:, file_name: }
      @csv
    end

    def load_and_merge!(rows:)
      @load_calls << { rows: rows }
    end
  end

  def setup
    @rows = [{ "event_date" => Date.new(2026, 3, 12), "row_id" => "abc" }]
    @transformer = FakeTransformer.new(@rows)
    @gateway = FakeGateway.new
    @log_output = StringIO.new
    @logger = Logger.new(@log_output)
    @processor = AirbnbPayous::Processor.new(
      transformer: @transformer,
      gateway: @gateway,
      logger: @logger
    )
  end

  def test_downloads_transforms_and_loads_csv_from_raw_payload
    assert_nil @processor.call({ "bucket" => "bucket", "name" => "file.csv" })

    assert_equal [{ bucket_name: "bucket", file_name: "file.csv" }], @gateway.download_calls
    assert_equal "csv", @transformer.received_csv
    assert_equal [{ rows: @rows }], @gateway.load_calls
  end

  def test_extracts_cloudevent_data_payloads
    @processor.call({ "data" => { "bucket" => "bucket", "name" => "file.csv" } })

    assert_includes @log_output.string, "Executing from structured CloudEvent payload"
    assert_equal [{ bucket_name: "bucket", file_name: "file.csv" }], @gateway.download_calls
  end

  def test_skips_non_csv_files
    assert_nil @processor.call({ "bucket" => "bucket", "name" => "file.txt" })
    assert_empty @gateway.download_calls
    assert_empty @gateway.load_calls
  end

  def test_reraises_failures_after_logging
    processor = AirbnbPayous::Processor.new(
      transformer: @transformer,
      gateway: FakeGateway.new(error: RuntimeError.new("boom")),
      logger: @logger
    )

    error = assert_raises(RuntimeError) do
      processor.call({ "bucket" => "bucket", "name" => "file.csv" })
    end

    assert_equal "boom", error.message
    assert_includes @log_output.string, "Failed to process Airbnb CSV: boom"
  end
end
