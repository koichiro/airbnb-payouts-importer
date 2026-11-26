# frozen_string_literal: true

require "bigdecimal"
require "logger"
require "stringio"

require_relative "test_helper"
require_relative "../lib/airbnb_payous/csv_transformer"

class CsvTransformerTest < Minitest::Test
  def setup
    @log_output = StringIO.new
    @logger = Logger.new(@log_output)
    @transformer = AirbnbPayous::CsvTransformer.new(logger: @logger)
  end

  def test_normalizes_mapped_headers_and_types
    csv = <<~CSV
      日付,種別,泊数,金額,Airbnb remitted tax
      03/12/2026,予約,2,150.50,12.34
    CSV

    rows = @transformer.call(csv)

    assert_equal 1, rows.length
    assert_equal Date.new(2026, 3, 12), rows.first["event_date"]
    assert_equal "予約", rows.first["type"]
    assert_equal 2, rows.first["number_of_nights"]
    assert_equal BigDecimal("150.50"), rows.first["amount"]
    assert_equal BigDecimal("12.34"), rows.first["airbnb_remitted_tax"]
    assert_nil rows.first["pet_fee"]
    assert_match(/\A\h{64}\z/, rows.first["row_id"])
  end

  def test_warns_and_preserves_unmapped_columns
    csv = <<~CSV
      日付,Unexpected Airbnb Column,金額
      03/12/2026,foo,100.00
    CSV

    rows = @transformer.call(csv)

    assert_equal "foo", rows.first["Unexpected Airbnb Column"]
    assert_includes @log_output.string, "Detected unmapped Airbnb CSV columns"
    assert_includes @log_output.string, "Unexpected Airbnb Column"
  end

  def test_normalizes_guest_counts_including_zero_and_blank_values
    csv = <<~CSV
      日付,大人,子ども,乳幼児,金額
      11/16/2026,2,1,0,100.00
      11/16/2026,,,,
    CSV

    rows = @transformer.call(csv)

    assert_equal [2, 1, 0], rows.first.values_at(*AirbnbPayous::Schema::GUEST_COUNT_COLUMNS)
    assert_equal [nil, nil, nil], rows.last.values_at(*AirbnbPayous::Schema::GUEST_COUNT_COLUMNS)
    assert_empty @transformer.unmapped_source_columns
    %w[大人 子ども 乳幼児].each { |header| refute rows.first.key?(header) }
    assert_equal rows, @transformer.call(csv)
  end

  def test_guest_count_changes_affect_row_id
    first = @transformer.call("日付,大人,子ども,乳幼児\n11/16/2026,2,0,0\n").first
    changed = @transformer.call("日付,大人,子ども,乳幼児\n11/16/2026,3,0,0\n").first

    refute_equal first["row_id"], changed["row_id"]
  end

  def test_guest_count_field_assignments_produce_distinct_row_ids
    adult_count = @transformer.call("日付,大人,子ども,乳幼児\n11/16/2026,2,,0\n").first
    child_count = @transformer.call("日付,大人,子ども,乳幼児\n11/16/2026,,2,0\n").first

    refute_equal adult_count["row_id"], child_count["row_id"]
  end

  def test_legacy_row_ids_are_preserved_when_guest_counts_are_missing_or_blank
    legacy_csv = "日付,種別,泊数,金額\n11/16/2026,予約,2,150.50\n"
    blank_counts_csv = "日付,種別,泊数,大人,子ども,乳幼児,金額\n11/16/2026,予約,2,,,,150.50\n"

    legacy = @transformer.call(legacy_csv).first
    blank_counts = @transformer.call(blank_counts_csv).first

    # Captured from the transformer before guest-count support was added.
    assert_equal "6331ab070fce744cf1dbb54f9eead9aef6aa5be78c9a731ef351854ab2dc9c40", legacy["row_id"]
    assert_equal legacy["row_id"], blank_counts["row_id"]
  end

  def test_normalizes_reservation_details_as_strings_without_logging_contact_values
    csv = <<~CSV
      日付,予約ステータス,連絡先,金額
      11/26/2026, 確定済み , +81 090-0000-0000 ,100.00
      11/26/2026, , ,
    CSV

    rows = @transformer.call(csv)

    assert_equal ["確定済み", "+81 090-0000-0000"], rows.first.values_at(*AirbnbPayous::Schema::RESERVATION_DETAIL_COLUMNS)
    assert_equal [nil, nil], rows.last.values_at(*AirbnbPayous::Schema::RESERVATION_DETAIL_COLUMNS)
    assert_empty @transformer.unmapped_source_columns
    %w[予約ステータス 連絡先].each { |header| refute rows.first.key?(header) }
    refute_includes @log_output.string, "+81 090-0000-0000"
    assert_equal rows, @transformer.call(csv)
  end

  def test_reservation_details_preserve_legacy_ids_when_missing_or_blank
    legacy_csv = "日付,種別,泊数,金額\n11/16/2026,予約,2,150.50\n"
    blank_details_csv = "日付,種別,予約ステータス,連絡先,泊数,金額\n11/16/2026,予約,,,2,150.50\n"

    legacy = @transformer.call(legacy_csv).first
    blank_details = @transformer.call(blank_details_csv).first

    assert_equal "6331ab070fce744cf1dbb54f9eead9aef6aa5be78c9a731ef351854ab2dc9c40", legacy["row_id"]
    assert_equal legacy["row_id"], blank_details["row_id"]
  end

  def test_reservation_detail_changes_and_field_identity_affect_row_id
    first = @transformer.call("日付,予約ステータス,連絡先\n11/26/2026,confirmed,contact-a\n").first
    status_changed = @transformer.call("日付,予約ステータス,連絡先\n11/26/2026,cancelled,contact-a\n").first
    contact_changed = @transformer.call("日付,予約ステータス,連絡先\n11/26/2026,confirmed,contact-b\n").first
    status_only = @transformer.call("日付,予約ステータス,連絡先\n11/26/2026,same,\n").first
    contact_only = @transformer.call("日付,予約ステータス,連絡先\n11/26/2026,,same\n").first

    refute_equal first["row_id"], status_changed["row_id"]
    refute_equal first["row_id"], contact_changed["row_id"]
    refute_equal status_only["row_id"], contact_only["row_id"]
  end

  def test_coerces_invalid_dates_and_numbers_to_nil
    csv = <<~CSV
      日付,泊数,金額
      invalid,abc,NaN
    CSV

    rows = @transformer.call(csv)

    assert_nil rows.first["event_date"]
    assert_nil rows.first["number_of_nights"]
    assert_nil rows.first["amount"]
    assert_includes @log_output.string, "column=amount, csv_row=2"
  end

  def test_normalizes_comma_grouped_numeric_values
    csv = <<~CSV
      日付,金額,サービス料
      06/04/2026,"-1,234.50","4,692"
    CSV

    rows = @transformer.call(csv)

    assert_equal BigDecimal("-1234.50"), rows.first["amount"]
    assert_equal BigDecimal(4692), rows.first["service_fee"]
  end

  def test_rejects_invalid_numeric_grouping_with_a_safe_warning
    csv = <<~CSV
      日付,サービス料
      06/04/2026,"12,34"
    CSV

    rows = @transformer.call(csv)

    assert_nil rows.first["service_fee"]
    assert_includes @log_output.string, "column=service_fee, csv_row=2"
    refute_includes @log_output.string, "12,34"
  end

  def test_equivalent_numeric_formats_produce_the_same_row_id
    ungrouped_csv = <<~CSV
      日付,種別,サービス料
      06/04/2026,予約,4692.00
    CSV
    grouped_csv = <<~CSV
      日付,種別,サービス料
      06/04/2026,予約,"4,692"
    CSV

    ungrouped_row = @transformer.call(ungrouped_csv).first
    grouped_row = @transformer.call(grouped_csv).first

    assert_equal ungrouped_row["service_fee"], grouped_row["service_fee"]
    assert_equal ungrouped_row["row_id"], grouped_row["row_id"]
  end

  def test_strips_bom_and_empty_values
    csv = "\xEF\xBB\xBF日付,詳細,金額\n03/12/2026, ,\n"

    rows = @transformer.call(csv)

    assert_equal Date.new(2026, 3, 12), rows.first["event_date"]
    assert_nil rows.first["details"]
    assert_nil rows.first["amount"]
  end

  def test_maps_new_japanese_tax_column
    csv = <<~CSV
      日付,Airbnbが納税する自動設定された税金,金額
      03/12/2026,12.34,100.00
    CSV

    rows = @transformer.call(csv)

    assert_equal BigDecimal("12.34"), rows.first["airbnb_remitted_tax"]
    assert_equal BigDecimal("100.00"), rows.first["amount"]
  end
end
