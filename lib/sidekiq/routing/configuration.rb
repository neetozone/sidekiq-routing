# frozen_string_literal: true

module Sidekiq
  module Routing
    class Configuration
      attr_accessor :enabled,
        :logger,
        :parked_queue,
        :process_parked_fallback_queue,
        :cache_ttl_seconds,
        :batch_limit,
        :batch_size,
        :breakdown_sample_size

      def initialize
        @enabled = true
        @logger = default_logger
        @parked_queue = PARKED_QUEUE_DEFAULT
        # Where process_parked sends a parked job that has no stamped original queue.
        @process_parked_fallback_queue = "default"
        # Hot-path snapshot freshness. 0 disables caching (read Redis every call).
        @cache_ttl_seconds = 5
        # Recovery defaults: nil limit = move everything; batch_size bounds each pass.
        @batch_limit = nil
        @batch_size = 100
        # Max jobs parked_breakdown scans (the parking queue can hold millions).
        @breakdown_sample_size = 1_000
      end

      private

        def default_logger
          if defined?(::Rails) && ::Rails.respond_to?(:logger) && ::Rails.logger
            ::Rails.logger
          else
            ::Sidekiq.logger
          end
        end
    end
  end
end
