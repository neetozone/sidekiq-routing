# frozen_string_literal: true

require "test_helper"

module Sidekiq
  module Routing::Auto
    class RerouteJobTest < Minitest::Test
      def setup
        @original_queues = Sidekiq.default_configuration[:queues]
        # Single queue at weight 1, so queue_weight_fraction is exactly 1.0 and
        # the capacity below is driven purely by the summed concurrency.
        Sidekiq.default_configuration[:queues] = ["within_1_minute"]
      end

      def teardown
        Sidekiq.default_configuration[:queues] = @original_queues
      end

      def test_calculate_capacity_tolerates_a_process_without_concurrency
        stub_process_set(Sidekiq::Process.new("concurrency" => 5), Sidekiq::Process.new({}))

        assert_in_delta 5 * 60, calculate_capacity, 0.001
      end

      def test_calculate_capacity_sums_concurrency_across_processes
        stub_process_set(Sidekiq::Process.new("concurrency" => 5), Sidekiq::Process.new("concurrency" => 3))

        assert_in_delta 8 * 60, calculate_capacity, 0.001
      end

      def test_calculate_capacity_falls_back_to_the_default_when_no_process_reports_concurrency
        stub_process_set(Sidekiq::Process.new({}))

        assert_in_delta 10 * 60, calculate_capacity, 0.001
      end

      private

        def stub_process_set(*processes)
          Sidekiq::ProcessSet.any_instance.stubs(:each).multiple_yields(*processes.map { |process| [process] })
        end

        def calculate_capacity
          RerouteJob.new.send(:calculate_capacity, "within_1_minute", 60)
        end
    end
  end
end
