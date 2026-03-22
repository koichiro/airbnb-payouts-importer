# frozen_string_literal: true

require "json"
require "rack"

require_relative "processor"

module AirbnbPayous
  class App
    def initialize(processor: Processor.new, logger: Logger.new($stdout))
      @processor = processor
      @logger = logger
    end

    def call(env)
      request = Rack::Request.new(env)

      return json_response(200, message: "ok") if request.get? && request.path == "/up"
      return json_response(404, error: "not_found") unless request.post? && request.path == "/"

      payload = parse_payload(request)
      @processor.call(payload)

      json_response(200, message: "processed")
    rescue JSON::ParserError => e
      @logger.error("Failed to parse request body: #{e.message}")
      json_response(400, error: "invalid_json")
    rescue StandardError => e
      @logger.error("Request failed: #{e.message}")
      raise e
    end

    private

    def parse_payload(request)
      body = request.body.read
      return {} if body.nil? || body.strip.empty?

      parsed = JSON.parse(body)
      parsed.is_a?(Hash) ? parsed : {}
    end

    def json_response(status, body)
      [
        status,
        { "content-type" => "application/json" },
        [JSON.generate(body)]
      ]
    end
  end
end
