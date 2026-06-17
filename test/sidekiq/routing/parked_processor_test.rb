# frozen_string_literal: true

require "test_helper"

module Sidekiq
  module Routing
    class ParkedProcessorTest < Minitest::Test
      def setup
        clear_queues
        Routing.configuration.process_parked_fallback_queue = "default"
      end

      def teardown
        clear_queues
      end

      def clear_queues
        Sidekiq.redis do |conn|
          conn.del("queue:routing_parked", "queue:within_1_minute", "queue:within_5_seconds", "queue:default")
        end
      end

      def park_job(klass_name, original:, jid: SecureRandom.hex(6))
        Mover.move(
          { "class" => klass_name, "args" => [], "jid" => jid },
          "routing_parked", ORIGINAL_QUEUE_KEY => original)
      end

      def test_process_parked_moves_job_back_to_its_original_queue
        park_job("ReportJob", original: "within_1_minute")

        moved = ParkedProcessor.new.call

        assert_equal 1, moved
        assert_equal 0, Sidekiq::Queue.new("routing_parked").size
        assert_equal 1, Sidekiq::Queue.new("within_1_minute").size
      end

      # The whole feature's correctness property: because process_parked rewrites the
      # "queue" field inside the payload, a processed parked job that later fails retries
      # to its ORIGINAL queue, not the parking queue. Sidekiq retries re-enqueue
      # to the queue named in the payload, so asserting that field is the proof.
      def test_processed_parked_payload_targets_original_queue_so_retries_do_not_return_to_parked
        park_job("ReportJob", original: "within_1_minute")

        ParkedProcessor.new.call

        processed = Sidekiq::Queue.new("within_1_minute").first
        assert_equal "within_1_minute", processed.item["queue"]
        refute_equal "routing_parked", processed.item["queue"]
        # The parked stamp is cleaned off on the way out.
        assert_nil processed.item[ORIGINAL_QUEUE_KEY]
      end

      def test_process_parked_stamps_no_divert_so_an_active_route_does_not_bounce_it_back
        park_job("ReportJob", original: "within_1_minute")

        ParkedProcessor.new.call

        assert_equal true, Sidekiq::Queue.new("within_1_minute").first.item[NO_DIVERT_KEY]
      end

      def test_process_parked_falls_back_when_original_queue_is_missing
        Mover.move({ "class" => "ReportJob", "args" => [], "jid" => "x" }, "routing_parked")

        ParkedProcessor.new.call

        assert_equal 1, Sidekiq::Queue.new("default").size
      end

      def test_process_parked_can_filter_by_class
        park_job("ReportJob", original: "within_1_minute")
        park_job("OtherJob", original: "within_5_seconds")

        moved = ParkedProcessor.new.call(klass: "ReportJob")

        assert_equal 1, moved
        assert_equal 1, Sidekiq::Queue.new("within_1_minute").size
        assert_equal 0, Sidekiq::Queue.new("within_5_seconds").size
        assert_equal 1, Sidekiq::Queue.new("routing_parked").size
      end

      def test_process_parked_respects_the_limit
        park_job("ReportJob", original: "within_1_minute")
        park_job("ReportJob", original: "within_1_minute")

        moved = ParkedProcessor.new.call(limit: 1)

        assert_equal 1, moved
        assert_equal 1, Sidekiq::Queue.new("routing_parked").size
      end
    end
  end
end
