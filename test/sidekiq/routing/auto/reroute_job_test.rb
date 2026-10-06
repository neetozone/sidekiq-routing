# frozen_string_literal: true

require "test_helper"

module Sidekiq
  module Routing::Auto
    class RerouteJobTest < Minitest::Test
      # A heartbeat whose `info` JSON carries no "concurrency" key. On Sidekiq 7
      # `ProcessSet#each` yields the parsed `info` hash as-is, so the key is
      # simply absent rather than coerced to an Integer.
      def test_calculate_capacity_tolerates_a_process_without_concurrency
        with_process_hashes([{ "hostname" => "host-a", "queues" => ["within_1_minute"] }]) do
          capacity = RerouteJob.new.send(:calculate_capacity, "within_1_minute", 60)

          assert_operator capacity, :>, 0
        end
      end

      def test_calculate_capacity_sums_reported_concurrency
        processes = [
          { "hostname" => "host-a", "concurrency" => 5 },
          { "hostname" => "host-b", "concurrency" => 7 }
        ]

        with_process_hashes(processes) do
          capacity = RerouteJob.new.send(:calculate_capacity, "within_1_minute", 60)

          assert_in_delta 12 * queue_weight_fraction * 60, capacity, 0.001
        end
      end

      def test_calculate_capacity_skips_processes_missing_concurrency
        processes = [
          { "hostname" => "host-a", "concurrency" => 4 },
          { "hostname" => "host-b" }
        ]

        with_process_hashes(processes) do
          capacity = RerouteJob.new.send(:calculate_capacity, "within_1_minute", 60)

          assert_in_delta 4 * queue_weight_fraction * 60, capacity, 0.001
        end
      end

      def test_calculate_capacity_falls_back_to_ten_threads_when_no_processes
        with_process_hashes([]) do
          capacity = RerouteJob.new.send(:calculate_capacity, "within_1_minute", 60)

          assert_in_delta 10 * queue_weight_fraction * 60, capacity, 0.001
        end
      end

      private

        def queue_weight_fraction
          RerouteJob.new.send(:queue_weight_fraction, "within_1_minute")
        end

        def with_process_hashes(hashes)
          set = Sidekiq::ProcessSet.allocate
          set.define_singleton_method(:each) do |&block|
            return to_enum(:each) unless block

            hashes.each { |hash| block.call(Sidekiq::Process.new(hash)) }
          end
          Sidekiq::ProcessSet.stubs(:new).returns(set)

          yield
        end
    end
  end
end
