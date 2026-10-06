# frozen_string_literal: true

require "test_helper"

# Regression: a process heartbeat without a "concurrency" key (older Sidekiq
# versions, Sidekiq Enterprise, or a partially-written heartbeat during a
# deploy) made calculate_capacity sum nil and raise
# "TypeError: nil can't be coerced into Integer".
module Sidekiq
  module Routing::Auto
    class RerouteJobTest < Minitest::Test
      # Stands in for Sidekiq::ProcessSet: yields the given info hashes the way
      # ProcessSet#each yields Sidekiq::Process objects.
      class FakeProcessSet
        include Enumerable

        def initialize(processes) = @processes = processes
        def each(&block) = @processes.each(&block)

        def total_concurrency = sum { |process| process["concurrency"].to_i }
      end

      def test_calculate_capacity_ignores_processes_without_concurrency
        with_process_set([{ "concurrency" => 5 }, {}]) do
          assert_equal 5 * weight_fraction * 60, calculate_capacity(60)
        end
      end

      def test_calculate_capacity_sums_concurrency_across_processes
        with_process_set([{ "concurrency" => 5 }, { "concurrency" => 3 }]) do
          assert_equal 8 * weight_fraction * 60, calculate_capacity(60)
        end
      end

      def test_calculate_capacity_falls_back_to_ten_when_no_process_reports_concurrency
        with_process_set([{}, {}]) do
          assert_equal 10 * weight_fraction * 60, calculate_capacity(60)
        end
      end

      private

        def calculate_capacity(sla_seconds)
          RerouteJob.new.send(:calculate_capacity, "within_1_minute", sla_seconds)
        end

        def weight_fraction
          RerouteJob.new.send(:queue_weight_fraction, "within_1_minute")
        end

        def with_process_set(processes)
          Sidekiq::ProcessSet.stubs(:new).returns(FakeProcessSet.new(processes))
          yield
        end
    end
  end
end
