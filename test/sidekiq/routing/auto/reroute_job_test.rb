# frozen_string_literal: true

require "test_helper"

module Sidekiq
  module Routing::Auto
    class RerouteJobTest < Minitest::Test
      def setup
        @job = Sidekiq::Routing::Auto::RerouteJob.new
      end

      def test_calculate_capacity_sums_reported_concurrency
        stub_process_set([{ "concurrency" => 5 }, { "concurrency" => 5 }])

        capacity = @job.send(:calculate_capacity, "within_1_minute", 60)

        assert_in_delta 10 * 60 * weight_fraction, capacity, 0.001
      end

      def test_calculate_capacity_falls_back_when_no_processes
        stub_process_set([])

        capacity = @job.send(:calculate_capacity, "within_1_minute", 60)

        assert_in_delta 10 * 60 * weight_fraction, capacity, 0.001
      end

      # A process entry whose info hash is missing "concurrency" (an embedded or
      # mid-shutdown Sidekiq process) must not blow up the capacity sum.
      def test_calculate_capacity_tolerates_process_without_concurrency
        stub_process_set([{ "concurrency" => 5 }, { "hostname" => "worker-2" }])

        capacity = @job.send(:calculate_capacity, "within_1_minute", 60)

        assert_in_delta 5 * 60 * weight_fraction, capacity, 0.001
      end

      private

        def stub_process_set(processes)
          Sidekiq::ProcessSet.stubs(:new).returns(processes)
        end

        def weight_fraction
          @job.send(:queue_weight_fraction, "within_1_minute")
        end
    end
  end
end
