# frozen_string_literal: true

require "test_helper"

module Sidekiq
  module Routing
    class SweeperTest < Minitest::Test
      def setup
        clear_queues
      end

      def teardown
        clear_queues
      end

      def clear_queues
        Sidekiq.redis do |conn|
          conn.del("queue:sweep_source", "queue:routing_parked")
        end
      end

      def seed(klass_name, queue: "sweep_source", jid: SecureRandom.hex(6))
        Mover.move({ "class" => klass_name, "args" => [], "jid" => jid }, queue)
      end

      def parked
        Sidekiq::Queue.new("routing_parked")
      end

      def test_sweep_moves_only_the_targeted_class_to_parking_queue
        seed("BadJob")
        seed("BadJob")
        seed("GoodJob")

        moved = Sweeper.new.call("BadJob", queue: "sweep_source")

        assert_equal 2, moved
        assert_equal 2, parked.size
        assert(parked.all? { |job| job.display_class == "BadJob" })
        # GoodJob stays put.
        assert_equal 1, Sidekiq::Queue.new("sweep_source").size
      end

      def test_sweep_stamps_the_original_queue
        seed("BadJob")

        Sweeper.new.call("BadJob", queue: "sweep_source")

        assert_equal "sweep_source", parked.first.item[ORIGINAL_QUEUE_KEY]
      end

      def test_sweep_raises_when_queue_cannot_be_resolved_and_none_given
        # Unloadable class name + no queue: => must not silently scan every queue.
        assert_raises(ArgumentError) do
          Sweeper.new.call("TotallyUnknownDemoJobClass")
        end
      end

      def test_sweep_respects_the_limit
        3.times { seed("BadJob") }

        moved = Sweeper.new.call("BadJob", queue: "sweep_source", limit: 2)

        assert_equal 2, moved
        assert_equal 2, parked.size
      end
    end
  end
end
