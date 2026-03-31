# frozen_string_literal: true

require "logger"
require "stringio"
require "net/http"

require_relative "test_helper"
require_relative "../lib/airbnb_payous/slack_notifier"

class SlackNotifierTest < Minitest::Test
  def setup
    @log_output = StringIO.new
    @logger = Logger.new(@log_output)
    @webhook_url = "https://hooks.slack.com/services/T000/B000/XXX"
    @notifier = AirbnbPayous::SlackNotifier.new(webhook_url: @webhook_url, logger: @logger)
  end

  def test_enabled_returns_true_when_url_present
    assert @notifier.enabled?
  end

  def test_enabled_returns_false_when_url_missing
    notifier = AirbnbPayous::SlackNotifier.new(webhook_url: nil)
    refute notifier.enabled?

    notifier = AirbnbPayous::SlackNotifier.new(webhook_url: "")
    refute notifier.enabled?
  end

  def test_notify_success_sends_post_request
    # Stub Net::HTTP.new
    mock_http = Minitest::Mock.new
    mock_response = Net::HTTPSuccess.new(1.0, "200", "OK")
    
    mock_http.expect(:use_ssl=, true, [true])
    mock_http.expect(:request, mock_response) do |request|
      assert_equal "/services/T000/B000/XXX", request.path
      payload = JSON.parse(request.body)
      attachment = payload["attachments"].first
      
      assert_includes attachment["title"], "完了"
      assert_equal "#36a64f", attachment["color"]
      
      fields = attachment["fields"]
      assert_equal "test.csv", fields.find { |f| f["title"] == "ファイル名" }["value"]
      assert_includes fields.find { |f| f["title"] == "インポートモード" }["value"], "フルインポート"
      assert_equal "10 件", fields.find { |f| f["title"] == "新規挿入件数" }["value"]
      true
    end

    Net::HTTP.stub(:new, mock_http, ["hooks.slack.com", 443]) do
      @notifier.notify_success(
        file_name: "test.csv",
        mode: :create_table,
        inserted_count: 10,
        updated_count: 0
      )
    end

    mock_http.verify
  end

  def test_notify_failure_sends_post_request
    mock_http = Minitest::Mock.new
    mock_response = Net::HTTPSuccess.new(1.0, "200", "OK")
    
    mock_http.expect(:use_ssl=, true, [true])
    mock_http.expect(:request, mock_response) do |request|
      payload = JSON.parse(request.body)
      attachment = payload["attachments"].first
      
      assert_includes attachment["title"], "失敗"
      assert_equal "#ff0000", attachment["color"]
      assert_equal "Error message", attachment["fields"].find { |f| f["title"] == "エラー内容" }["value"]
      true
    end

    Net::HTTP.stub(:new, mock_http, ["hooks.slack.com", 443]) do
      @notifier.notify_failure(file_name: "fail.csv", error_message: "Error message")
    end

    mock_http.verify
  end

  def test_logs_error_on_http_failure
    mock_http = Minitest::Mock.new
    mock_response = Net::HTTPBadRequest.new(1.0, "400", "Bad Request")
    def mock_response.body; "Missing parameter"; end
    
    mock_http.expect(:use_ssl=, true, [true])
    mock_http.expect(:request, mock_response, [Net::HTTP::Post])

    Net::HTTP.stub(:new, mock_http, ["hooks.slack.com", 443]) do
      @notifier.notify_failure(file_name: "fail.csv", error_message: "Error")
    end

    assert_includes @log_output.string, "Failed to send Slack notification: 400"
  end
end
