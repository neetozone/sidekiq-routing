# frozen_string_literal: true

require "test_helper"

module Sidekiq
  module Routing::Auto
    class RerouteJobTest < Minitest::Test
      def test_calculate_capacity_sums_reported_concurrency
        stub_process_set([{ "concurrency" => 5 }, { "concurrency" => 5 }])

        assert_in_delta 600.0, calculate_capacity("within_1_minute", 60), 0.001
      end

      def test_calculate_capacity_ignores_processes_without_concurrency
        stub_process_set([{ "concurrency" => 5 }, { "hostname" => "embedded" }])

        assert_in_delta 300.0, calculate_capacity("within_1_minute", 60), 0.001
      end

      def test_calculate_capacity_falls_back_when_no_process_reports_concurrency
        stub_process_set([{ "hostname" => "embedded" }])

        assert_in_delta 60.0, calculate_capacity("within_1_minute", 6), 0.001
      end

      def test_calculate_capacity_falls_back_when_no_processes_are_registered
        stub_process_set([])

        assert_in_delta 60.0, calculate_capacity("within_1_minute", 6), 0.001
      end

      private

        # The weight fraction depends on the host's configured queues; pin it to
        # 1.0 so these tests assert only on the concurrency sum.
        def calculate_capacity(queue_name, sla_seconds)
          job = RerouteJob.new
          job.stubs(:queue_weight_fraction).returns(1.0)
          job.send(:calculate_capacity, queue_name, sla_seconds)
        end

        def stub_process_set(processes)
          Sidekiq::ProcessSet.stubs(:new).returns(processes)
        end
    end
  end
end
