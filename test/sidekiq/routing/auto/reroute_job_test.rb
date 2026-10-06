# frozen_string_literal: true

require "test_helper"

# Regression: capacity is derived from the shared Redis "processes" set, which
# this gem does not own. A registrant whose heartbeat info omits "concurrency"
# used to make `sum` raise TypeError: nil can't be coerced into Integer.
module Sidekiq
  module Routing::Auto
    class RerouteJobTest < Minitest::Test
      def setup
        @job = RerouteJob.new
      end

      def test_calculate_capacity_sums_reported_concurrency
        with_process_set([{ "concurrency" => 5 }, { "concurrency" => 3 }]) do
          # 8 workers * weight_fraction * 60s
          assert_in_delta 8 * weight_fraction * 60, capacity_for("within_1_minute", 60), 0.001
        end
      end

      def test_calculate_capacity_ignores_process_without_reported_concurrency
        with_process_set([{ "concurrency" => 5 }, { "busy" => 1 }]) do
          assert_in_delta 5 * weight_fraction * 60, capacity_for("within_1_minute", 60), 0.001
        end
      end

      def test_calculate_capacity_falls_back_when_no_process_reports_concurrency
        with_process_set([{ "busy" => 1 }, { "busy" => 0 }]) do
          assert_in_delta 10 * weight_fraction * 60, capacity_for("within_1_minute", 60), 0.001
        end
      end

      def test_calculate_capacity_falls_back_when_process_set_is_empty
        with_process_set([]) do
          assert_in_delta 10 * weight_fraction * 60, capacity_for("within_1_minute", 60), 0.001
        end
      end

      def test_should_reroute_does_not_raise_when_concurrency_is_missing
        with_process_set([{ "busy" => 1 }]) do
          # The production fault surfaced here: should_reroute? -> calculate_capacity.
          @job.send(:should_reroute?, "within_1_minute")
        end
      end

      private

        def capacity_for(queue_name, sla_seconds)
          @job.send(:calculate_capacity, queue_name, sla_seconds)
        end

        def weight_fraction
          @job.send(:queue_weight_fraction, "within_1_minute")
        end

        # Sidekiq::Process quacks as a hash for [], so plain hashes stand in.
        def with_process_set(processes)
          ::Sidekiq::ProcessSet.stubs(:new).returns(processes)
          yield
        ensure
          ::Sidekiq::ProcessSet.unstub(:new)
        end
    end
  end
end
