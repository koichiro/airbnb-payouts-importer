# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module AirbnbPayous
  class SlackNotifier
    def initialize(webhook_url: ENV["SLACK_WEBHOOK_URL"], logger: Logger.new($stdout))
      @webhook_url = webhook_url
      @logger = logger
    end

    def enabled?
      !(@webhook_url.nil? || @webhook_url.empty?)
    end

    def notify_success(file_name:, mode:, inserted_count:, updated_count:)
      return unless enabled?

      mode_text = mode == :create_table ? "フルインポート（新規作成）" : "マージインポート（更新）"
      
      payload = {
        attachments: [
          {
            fallback: "Airbnb Payouts Import Successful: #{file_name}",
            color: "#36a64f",
            title: "✅ Airbnb Payouts データ登録完了",
            fields: [
              { title: "ファイル名", value: file_name, short: false },
              { title: "インポートモード", value: mode_text, short: true },
              { title: "新規挿入件数", value: "#{inserted_count} 件", short: true },
              { title: "更新件数", value: "#{updated_count} 件", short: true }
            ],
            ts: Time.now.to_i
          }
        ]
      }

      send_notification(payload)
    end

    def notify_failure(file_name:, error_message:)
      return unless enabled?

      payload = {
        attachments: [
          {
            fallback: "Airbnb Payouts Import Failed: #{file_name}",
            color: "#ff0000",
            title: "❌ Airbnb Payouts データ登録失敗",
            text: "ファイルの処理中にエラーが発生しました。",
            fields: [
              { title: "ファイル名", value: file_name, short: false },
              { title: "エラー内容", value: error_message, short: false }
            ],
            ts: Time.now.to_i
          }
        ]
      }

      send_notification(payload)
    end

    private

    def send_notification(payload)
      uri = URI.parse(@webhook_url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == "https")

      request = Net::HTTP::Post.new(uri.path, { "Content-Type" => "application/json" })
      request.body = JSON.generate(payload)

      response = http.request(request)

      unless response.is_a?(Net::HTTPSuccess)
        @logger.error("Failed to send Slack notification: #{response.code} #{response.body}")
      end
    rescue StandardError => e
      @logger.error("Error sending Slack notification: #{e.message}")
    end
  end
end
