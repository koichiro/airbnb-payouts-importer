# frozen_string_literal: true

require "json"
require "tempfile"

require "google/cloud/bigquery"
require "google/cloud/storage"

require_relative "schema"

module AirbnbPayous
  class BigqueryGateway
    attr_reader :project_id, :dataset_id, :table_id, :staging_table_id

    def initialize(project_id:, dataset_id:, table_id:, logger: Logger.new($stdout), bigquery: nil, storage: nil)
      @logger = logger
      @project_id = project_id
      @dataset_id = dataset_id
      @table_id = table_id
      @staging_table_id = "#{table_id}_staging"

      @logger.info("Initializing BigqueryGateway with project_id: #{@project_id.inspect}, dataset_id: #{@dataset_id.inspect}, table_id: #{@table_id.inspect}")

      if @project_id.nil? || @project_id.empty?
        raise ArgumentError, "project_id is required"
      end

      if @dataset_id.nil? || @dataset_id.empty?
        raise ArgumentError, "dataset_id is required"
      end

      if @table_id.nil? || @table_id.empty?
        raise ArgumentError, "table_id is required"
      end

      @bigquery = bigquery || Google::Cloud::Bigquery.new(project_id: @project_id)
      @storage = storage || Google::Cloud::Storage.new(project_id: @project_id)
    end

    def download(bucket_name:, file_name:)
      bucket = @storage.bucket(bucket_name)
      file = bucket.file(file_name)
      file.download.string
    end

    def load_and_merge!(rows:)
      dataset = @bigquery.dataset(dataset_id) || @bigquery.create_dataset(dataset_id)
      temp_file = build_tempfile(rows)

      load_job = dataset.load_job(
        staging_table_id,
        temp_file.path,
        format: "json",
        write: "truncate",
        autodetect: true
      ) do |job|
        job.schema do |schema|
          Schema::JOB_SCHEMA.each do |name, type, mode|
            schema_field_type = map_schema_type(type)
            schema.public_send(schema_field_type, name, mode: map_schema_mode(mode))
          end
        end
      end
      load_job.wait_until_done!
      raise load_job.error if load_job.failed?

      # Use job output rows, fallback to input rows count if zero (sometimes stats are delayed)
      total_rows_loaded = load_job.output_rows.to_i
      total_rows_loaded = rows.length if total_rows_loaded.zero?
      
      @logger.info("Load job finished. output_rows: #{load_job.output_rows}, rows.length: #{rows.length}. Using #{total_rows_loaded} as reference.")

      # Fetch a fresh table reference to avoid caching issues
      target_table = dataset.table(table_id)
      result = { inserted_count: 0, updated_count: 0 }

      if target_table.nil?
        @logger.info("Target table #{qualified_table_name(table_id)} does not exist. Path: :create_table")
        copy_job = @bigquery.copy_job qualified_table_name(staging_table_id), qualified_table_name(table_id), write: "truncate"
        @logger.info("Started copy_job (ID: #{copy_job.job_id}). Waiting for completion...")
        copy_job.wait_until_done!
        raise copy_job.error if copy_job.failed?
        @logger.info("Target table created successfully via copy_job.")
        
        result[:mode] = :create_table
        result[:inserted_count] = total_rows_loaded
      else
        @logger.info("Target table #{qualified_table_name(table_id)} exists. Path: :merge")
        merge_sql = build_merge_query(rows.first.keys)
        query_job = @bigquery.query_job(merge_sql)
        @logger.info("Started query_job (ID: #{query_job.job_id}). Waiting for completion...")
        query_job.wait_until_done!
        raise query_job.error if query_job.failed?

        # Capture DML stats with robust fallbacks
        if query_job.dml_stats
          result[:inserted_count] = query_job.dml_stats.inserted_row_count.to_i
          result[:updated_count] = query_job.dml_stats.updated_row_count.to_i
          @logger.info("DML Stats - Inserted: #{result[:inserted_count]}, Updated: #{result[:updated_count]}")
        elsif (affected = query_job.num_dml_affected_rows.to_i) >= 0
          # For our current MERGE query (which only has INSERT), all affected rows are inserts
          result[:inserted_count] = affected
          @logger.info("DML Stats not found, but num_dml_affected_rows is #{affected}. Assuming all are inserts.")
        else
          @logger.warn("No DML statistics available for query job #{query_job.job_id}.")
        end

        result[:mode] = :merge
      end
      
      @logger.info("Final result for notification: #{result.inspect}")
      result
    ensure
      temp_file&.close!
      delete_staging_table(dataset)
    end

    def qualified_table_name(table_name)
      "#{project_id}.#{dataset_id}.#{table_name}"
    end

    private

    def to_newline_delimited_json(rows)
      rows.map { |row| JSON.generate(serialize_row(row)) }.join("\n")
    end

    def build_tempfile(rows)
      file = Tempfile.new(["airbnb-payous", ".json"])
      file.binmode
      file.write(to_newline_delimited_json(rows))
      file.flush
      file
    end

    def serialize_row(row)
      row.transform_values do |value|
        case value
        when Date
          value.iso8601
        when BigDecimal
          value.to_s("F")
        else
          value
        end
      end
    end

    def map_schema_type(type)
      {
        date: :date,
        string: :string,
        integer: :integer,
        numeric: :numeric
      }.fetch(type)
    end

    def map_schema_mode(mode)
      mode == :required ? :required : :nullable
    end

    def build_merge_query(columns)
      columns_list = columns.map { |column| "`#{column}`" }.join(", ")
      source_columns_list = columns.map { |column| "S.`#{column}`" }.join(", ")

      <<~SQL
        MERGE `#{qualified_table_name(table_id)}` T
        USING `#{qualified_table_name(staging_table_id)}` S
        ON T.row_id = S.row_id
        WHEN NOT MATCHED THEN
          INSERT (#{columns_list}) VALUES (#{source_columns_list})
      SQL
    end

    def delete_staging_table(dataset)
      return if dataset.nil?

      staging_table = dataset.table(staging_table_id)
      staging_table&.delete
      @logger.info("Staging table cleaned up.")
    rescue StandardError => e
      @logger.warn("Failed to delete staging table #{qualified_table_name(staging_table_id)}: #{e.message}")
    end
  end
end
