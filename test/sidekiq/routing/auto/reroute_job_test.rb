# frozen_string_literal: true

require "test_helper"

module Sidekiq
  module Routing::Auto
    class RerouteJobTest < Minitest::Test
      # A stand-in for Sidekiq::ProcessSet that yields plain hashes, the way
      # Sidekiq::Process responds to #[].
      class FakeProcessSet
        include Enumerable

        def initialize(processes) = @processes = processes
        def each(&block) = @processes.each(&block)
      end

      def test_calculate_capacity_handles_processes_without_a_concurrency_value
        # Regression (neeto-planner-web#13483): Sidekiq 8 removed "concurrency"
        # from the heartbeat's `info` JSON and writes it as a separate Redis
        # hash field. Sidekiq 7's ProcessSet#each reads only `info`, so during a
        # rolling 7 -> 8 upgrade a 7.x worker sees a nil concurrency for every
        # 8.x process and the sum raised
        # "TypeError: nil can't be coerced into Integer".
        stub_process_set([{ "concurrency" => 10 }, {}])

        capacity = calculate_capacity("within_1_minute", 60)

        assert_operator capacity, :>, 0,
          "capacity must still be computed when a process reports no concurrency"
      end

      def test_calculate_capacity_sums_reported_concurrency
        stub_process_set([{ "concurrency" => 10 }, { "concurrency" => 5 }])

        # Guards the arithmetic: 15 threads must beat 10 threads, and both must
        # scale with the SLA window.
        assert_operator calculate_capacity("within_1_minute", 60), :>,
          calculate_capacity_with([{ "concurrency" => 10 }], "within_1_minute", 60)
      end

      def test_calculate_capacity_falls_back_when_no_process_reports_concurrency
        # All processes missing concurrency must behave like "no data" and hit
        # the existing default of 10 threads, not produce a zero capacity.
        stub_process_set([{}, {}])
        missing = calculate_capacity("within_1_minute", 60)

        stub_process_set([{ "concurrency" => 10 }])
        default = calculate_capacity("within_1_minute", 60)

        assert_equal default, missing
      end

      private

        def stub_process_set(processes)
          ::Sidekiq::ProcessSet.stubs(:new).returns(FakeProcessSet.new(processes))
        end

        def calculate_capacity(queue_name, sla_seconds)
          RerouteJob.new.send(:calculate_capacity, queue_name, sla_seconds)
        end

        def calculate_capacity_with(processes, queue_name, sla_seconds)
          stub_process_set(processes)
          calculate_capacity(queue_name, sla_seconds)
        end
    end
  end
end
