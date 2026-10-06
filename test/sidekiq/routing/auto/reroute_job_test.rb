# frozen_string_literal: true

require "test_helper"

module Sidekiq
  module Routing::Auto
    class RerouteJobTest < Minitest::Test
      # No queues are configured in the test harness, so queue_weight_fraction
      # is 1.0 and capacity reduces to total_concurrency * sla_seconds.
      SLA_SECONDS = 60

      def setup
        @job = RerouteJob.new
      end

      # A Sidekiq 8 process writes "concurrency" as its own Redis hash field
      # rather than inside the "info" JSON, so a reader running Sidekiq 7's
      # ProcessSet#each sees no "concurrency" key for it at all. During a
      # rolling 7 -> 8 upgrade both kinds of process are registered at once.
      def test_calculate_capacity_tolerates_a_process_without_concurrency
        stub_process_set([{ "concurrency" => 10 }, {}])

        assert_in_delta 10 * SLA_SECONDS, calculate_capacity, 0.001
      end

      def test_calculate_capacity_sums_concurrency_across_processes
        stub_process_set([{ "concurrency" => 10 }, { "concurrency" => 15 }])

        assert_in_delta 25 * SLA_SECONDS, calculate_capacity, 0.001
      end

      def test_calculate_capacity_falls_back_when_no_process_reports_concurrency
        stub_process_set([{}])

        assert_in_delta 10 * SLA_SECONDS, calculate_capacity, 0.001
      end

      def test_calculate_capacity_falls_back_when_no_processes_are_registered
        stub_process_set([])

        assert_in_delta 10 * SLA_SECONDS, calculate_capacity, 0.001
      end

      private

        def calculate_capacity
          @job.send(:calculate_capacity, "within_1_minute", SLA_SECONDS)
        end

        def stub_process_set(processes)
          set = Sidekiq::ProcessSet.new(false)
          set.stubs(:each).multiple_yields(*processes.map { |process| [process] })
          Sidekiq::ProcessSet.stubs(:new).returns(set)
        end
    end
  end
end
