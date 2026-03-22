# frozen_string_literal: true

require "json"
require "logger"

require_relative "lib/airbnb_payous/app"

run AirbnbPayous::App.new if defined?(run)
