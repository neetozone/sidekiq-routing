# frozen_string_literal: true

require "test_helper"

module Sidekiq
  module Routing
    class MoverTest < Minitest::Test
      def setup
        Sidekiq.redis { |conn| conn.del("queue:mover_target") }
      end

      def teardown
        Sidekiq.redis { |conn| conn.del("queue:mover_target") }
      end

      def test_move_rewrites_queue_inside_payload_and_pushes_to_target
        item = { "class" => "SomeJob", "args" => [1], "jid" => "j1", "queue" => "within_1_minute" }

        Mover.move(item, "mover_target")

        queue = Sidekiq::Queue.new("mover_target")
        assert_equal 1, queue.size
        moved = queue.first
        assert_equal "mover_target", moved.item["queue"]
        assert_equal "SomeJob", moved.item["class"]
      end

      def test_move_merges_extra_keys
        item = { "class" => "SomeJob", "args" => [], "jid" => "j2", "queue" => "within_1_minute" }

        Mover.move(item, "mover_target", Routing::ORIGINAL_QUEUE_KEY => "within_1_minute")

        moved = Sidekiq::Queue.new("mover_target").first
        assert_equal "within_1_minute", moved.item[Routing::ORIGINAL_QUEUE_KEY]
      end

      def test_move_registers_the_queue_for_the_web_ui
        Mover.move({ "class" => "J", "args" => [], "jid" => "j3", "queue" => "x" }, "mover_target")

        registered = Sidekiq.redis { |conn| conn.sismember("queues", "mover_target") }
        assert registered
      end
    end
  end
end
