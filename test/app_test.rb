# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/airbnb_payous/app"

class AppTest < Minitest::Test
  include Rack::Test::Methods

  class FakeProcessor
    attr_reader :calls

    def initialize
      @calls = []
    end

    def call(payload)
      @calls << payload
      nil
    end
  end

  def setup
    @processor = FakeProcessor.new
    @rack_app = AirbnbPayous::App.new(processor: @processor)
  end

  def app
    @rack_app
  end

  def test_returns_health_response
    get "/up"

    assert_equal 200, last_response.status
    assert_includes last_response.body, "ok"
  end

  def test_processes_post_payloads
    post "/", JSON.generate({ data: { bucket: "bucket", name: "file.csv" } }), { "CONTENT_TYPE" => "application/json" }

    assert_equal 200, last_response.status
    assert_equal [{ "data" => { "bucket" => "bucket", "name" => "file.csv" } }], @processor.calls
  end

  def test_returns_400_for_malformed_json
    post "/", "{bad", { "CONTENT_TYPE" => "application/json" }

    assert_equal 400, last_response.status
    assert_includes last_response.body, "invalid_json"
  end

  def test_returns_404_for_unknown_routes
    get "/missing"

    assert_equal 404, last_response.status
  end
end
