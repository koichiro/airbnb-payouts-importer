# frozen_string_literal: true

module AirbnbPayous
  module Schema
    COLUMN_MAP = {
      "日付" => "event_date",
      "入金予定日" => "payout_scheduled_date",
      "種別" => "type",
      "確認コード" => "confirmation_code",
      "予約日" => "booking_date",
      "開始日" => "start_date",
      "終了日" => "end_date",
      "泊数" => "number_of_nights",
      "ゲスト" => "guest",
      "リスティング" => "listing_name",
      "詳細" => "details",
      "参照コード" => "reference_code",
      "通貨" => "currency",
      "金額" => "amount",
      "支払い済み" => "paid",
      "サービス料" => "service_fee",
      "スピード送金の手数料" => "express_transfer_fee",
      "清掃料金" => "cleaning_fee",
      "ペット料金" => "pet_fee",
      "総収入" => "total_income",
      "宿泊税" => "accommodation_tax",
      "Airbnb remitted tax" => "airbnb_remitted_tax",
      "Airbnbが納税する自動設定された税金" => "airbnb_remitted_tax",
      "ホスティング収入年度" => "hosting_revenue_fiscal_year"
    }.freeze

    DATE_COLUMNS = %w[
      event_date
      payout_scheduled_date
      booking_date
      start_date
      end_date
    ].freeze

    NUMERIC_COLUMNS = %w[
      amount
      paid
      service_fee
      express_transfer_fee
      cleaning_fee
      pet_fee
      total_income
      accommodation_tax
      airbnb_remitted_tax
    ].freeze

    INTEGER_COLUMNS = %w[
      number_of_nights
      hosting_revenue_fiscal_year
    ].freeze

    JOB_SCHEMA = [
      ["event_date", :date, :nullable],
      ["payout_scheduled_date", :date, :nullable],
      ["type", :string, :nullable],
      ["confirmation_code", :string, :nullable],
      ["booking_date", :date, :nullable],
      ["start_date", :date, :nullable],
      ["end_date", :date, :nullable],
      ["number_of_nights", :integer, :nullable],
      ["guest", :string, :nullable],
      ["listing_name", :string, :nullable],
      ["details", :string, :nullable],
      ["reference_code", :string, :nullable],
      ["currency", :string, :nullable],
      ["amount", :numeric, :nullable],
      ["paid", :numeric, :nullable],
      ["service_fee", :numeric, :nullable],
      ["express_transfer_fee", :numeric, :nullable],
      ["cleaning_fee", :numeric, :nullable],
      ["pet_fee", :numeric, :nullable],
      ["total_income", :numeric, :nullable],
      ["accommodation_tax", :numeric, :nullable],
      ["airbnb_remitted_tax", :numeric, :nullable],
      ["hosting_revenue_fiscal_year", :integer, :nullable],
      ["row_id", :string, :required]
    ].freeze

    module_function

    def default_value(type)
      case type
      when :integer
        nil
      when :numeric
        nil
      else
        nil
      end
    end
  end
end
