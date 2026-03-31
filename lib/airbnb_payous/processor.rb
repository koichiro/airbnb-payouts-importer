# frozen_string_literal: true

require "logger"

require_relative "bigquery_gateway"
require_relative "csv_transformer"

module AirbnbPayous
  class Processor
    def initialize(
      transformer: CsvTransformer.new,
      gateway: nil,
      logger: Logger.new($stdout)
    )
      @transformer = transformer
      @gateway = gateway || default_gateway
      @logger = logger
    end

    def call(event_payload)
      data = extract_event_data(event_payload)
      bucket_name = data.fetch("bucket")
      file_name = data.fetch("name")

      unless file_name.downcase.end_with?(".csv")
        @logger.info("Skipping non-CSV file: #{file_name}")
        return nil
      end

      csv_content = @gateway.download(bucket_name:, file_name:)
      rows = @transformer.call(csv_content)
      @gateway.load_and_merge!(rows:)

      nil
    rescue StandardError => e
      @logger.error("Failed to process Airbnb CSV: #{e.message}")
      raise e
    end

    private

    def extract_event_data(event_payload)
      if event_payload.key?("data") && event_payload["data"].is_a?(Hash)
        @logger.info("Executing from structured CloudEvent payload")
        event_payload["data"]
      else
        @logger.info("Executing from raw event payload")
        event_payload
      end
    end

    def default_gateway
      BigqueryGateway.new(
        project_id: ENV["GCP_PROJECT_ID"],
        dataset_id: ENV["BQ_DATASET_ID"],
        table_id: ENV["BQ_TABLE_ID"]
      )
    end
  end
end
