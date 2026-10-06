# frozen_string_literal: true

require "test_helper"

module Sidekiq
  module Routing::Auto
    class RerouteJobTest < Minitest::Test
      # Sidekiq::ProcessSet#each yields Sidekiq::Process objects built from the
      # process's own `info` JSON blob. On Sidekiq 7.x that blob is merged in
      # as-is, so "concurrency" is whatever the reporting process wrote — it is
      # not coerced and can come back nil. (Sidekiq 8 added a `.to_i` in #each;
      # this gem supports sidekiq >= 7.0, so it cannot rely on that.)
      class FakeProcessSet
        include Enumerable

        def initialize(processes) = @processes = processes
        def each(&block) = @processes.each(&block)
      end

      def test_calculate_capacity_tolerates_a_process_reporting_nil_concurrency
        stub_process_set([{ "concurrency" => 5 }, { "concurrency" => nil }])

        capacity = calculate_capacity("within_1_minute", 60)

        assert_operator capacity, :>, 0,
          "a process with nil concurrency must not blow up capacity calculation"
      end

      def test_calculate_capacity_sums_reported_concurrency
        stub_process_set([{ "concurrency" => 5 }, { "concurrency" => 5 }])

        # 10 total concurrency * weight_fraction * 60s SLA.
        expected = 10 * weight_fraction("within_1_minute") * 60
        assert_in_delta expected, calculate_capacity("within_1_minute", 60), 0.001
      end

      def test_calculate_capacity_falls_back_when_no_process_reports_concurrency
        stub_process_set([{ "concurrency" => nil }])

        # Falls back to the hardcoded concurrency of 10 when the sum is zero.
        expected = 10 * weight_fraction("within_1_minute") * 60
        assert_in_delta expected, calculate_capacity("within_1_minute", 60), 0.001
      end

      def test_calculate_capacity_falls_back_when_no_processes_are_running
        stub_process_set([])

        expected = 10 * weight_fraction("within_1_minute") * 60
        assert_in_delta expected, calculate_capacity("within_1_minute", 60), 0.001
      end

      private

        def stub_process_set(processes)
          Sidekiq::ProcessSet.stubs(:new).returns(FakeProcessSet.new(processes))
        end

        def calculate_capacity(queue_name, sla_seconds)
          RerouteJob.new.send(:calculate_capacity, queue_name, sla_seconds)
        end

        def weight_fraction(queue_name)
          RerouteJob.new.send(:queue_weight_fraction, queue_name)
        end
    end
  end
end
