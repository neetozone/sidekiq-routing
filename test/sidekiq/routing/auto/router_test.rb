# frozen_string_literal: true

require "test_helper"

module Sidekiq
  module Routing::Auto
    class RouterTest < Minitest::Test
      def test_next_queue_for_returns_next_sla_queue
        assert_equal "within_1_minute", Router.next_queue_for("within_5_seconds")
        assert_equal "within_5_minutes", Router.next_queue_for("within_1_minute")
        assert_equal "within_1_hour", Router.next_queue_for("within_5_minutes")
      end

      def test_next_queue_for_returns_nil_for_last_or_unknown_queue
        assert_nil Router.next_queue_for("within_1_hour")
        assert_nil Router.next_queue_for("non_existent")
      end
    end
  end
end
