# frozen_string_literal: true

module Sidekiq
  module Routing::Auto
    class Router
      QUEUE_HIERARCHY = %w[
        within_5_seconds
        within_1_minute
        within_5_minutes
        within_1_hour
      ].freeze

      def self.next_queue_for(current_queue)
        index = QUEUE_HIERARCHY.index(current_queue)
        return nil unless index

        QUEUE_HIERARCHY[index + 1]
      end

      def self.sla_queues
        QUEUE_HIERARCHY
      end
    end
  end
end
