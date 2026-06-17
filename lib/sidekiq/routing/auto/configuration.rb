# frozen_string_literal: true

module Sidekiq
  module Routing::Auto
    class << self
      def configuration
        @_configuration ||= Configuration.new
      end

      def setup
        yield configuration if block_given?
      end

      def enabled?
        configuration.enabled
      end

      def logger
        configuration.logger
      end

      def default_enabled?
        ENV["SIDEKIQ_ROUTING_AUTO_REROUTE_ENABLED"] == "true"
      end
    end

    class Configuration
      attr_accessor :enabled,
        :logger,
        :sla_thresholds,
        :capacity_threshold_percent,
        :noisy_neighbor_threshold_percent,
        :batch_reroute_limit,
        :duration_tracking_window,
        :excluded_job_classes

      def initialize
        # Off unless explicitly opted in via SIDEKIQ_ROUTING_AUTO_REROUTE_ENABLED.
        # (In the Rails-engine ancestor this was wired by an initializer; the
        # standalone gem makes it the built-in default so auto stays safe-by-default.)
        @enabled = Sidekiq::Routing::Auto.default_enabled?
        @logger = if defined?(::Rails) && ::Rails.respond_to?(:logger) && ::Rails.logger
          ::Rails.logger
        else
          Logger.new($stdout)
        end
        @sla_thresholds = {
          "within_5_seconds" => 5,
          "within_1_minute" => 60,
          "within_5_minutes" => 300,
          "within_1_hour" => 3600
        }
        @capacity_threshold_percent = 80
        @noisy_neighbor_threshold_percent = 50
        @batch_reroute_limit = 50
        @duration_tracking_window = 3600
        # The internal reroute job must never reroute itself.
        @excluded_job_classes = ["Sidekiq::Routing::Auto::RerouteJob"]
      end
    end
  end
end
