# frozen_string_literal: true

require "test_helper"

module Sidekiq
  module Routing
    module Middleware
      class ServerTest < Minitest::Test
        class ServerJob
          include Sidekiq::Job
        end

        def setup
          Sidekiq.redis do |conn|
            conn.del(Store::HASH_KEY)
            conn.del("queue:routing_parked")
          end
          Routing.reset_cache!
          Routing.configuration.cache_ttl_seconds = 5
          @middleware = Server.new
        end

        def teardown
          Sidekiq.redis do |conn|
            conn.del(Store::HASH_KEY)
            conn.del("queue:routing_parked")
          end
          Routing.reset_cache!
        end

        def call(job, queue)
          ran = false
          @middleware.call(ServerJob.new, job, queue) { ran = true }
          ran
        end

        def parked
          Sidekiq::Queue.new("routing_parked")
        end

        def test_park_moves_a_copy_to_parking_queue_and_does_not_run
          Routing.park(ServerJob)
          job = { "class" => "ServerJob", "args" => [], "jid" => "j1" }

          ran = call(job, "within_1_minute")

          refute ran
          assert_equal 1, parked.size
          moved = parked.first
          assert_equal "routing_parked", moved.item["queue"]
          assert_equal "within_1_minute", moved.item[ORIGINAL_QUEUE_KEY]
        end

        def test_park_preserves_existing_original_queue
          Routing.park(ServerJob)
          job = { "class" => "ServerJob", "args" => [], "jid" => "j2", ORIGINAL_QUEUE_KEY => "within_5_seconds" }

          call(job, "within_1_minute")

          assert_equal "within_5_seconds", parked.first.item[ORIGINAL_QUEUE_KEY]
        end

        def test_blackhole_drops_without_running_and_without_dead_set
          Routing.blackhole(ServerJob)
          Sidekiq::DeadSet.any_instance.expects(:kill).never
          job = { "class" => "ServerJob", "args" => [], "jid" => "j3" }

          ran = call(job, "within_1_minute")

          refute ran
          assert_equal 0, parked.size
        end

        def test_loop_guard_runs_jobs_already_on_parking_queue
          Routing.park(ServerJob)
          job = { "class" => "ServerJob", "args" => [], "jid" => "j4" }

          ran = call(job, "routing_parked")

          assert ran, "parked-queue jobs must run, not be re-diverted"
        end

        def test_not_routed_yields
          job = { "class" => "ServerJob", "args" => [], "jid" => "j5" }

          ran = call(job, "within_1_minute")

          assert ran
          assert_equal 0, parked.size
        end

        def test_no_divert_flag_yields
          Routing.park(ServerJob)
          job = { "class" => "ServerJob", "args" => [], "jid" => "j6", NO_DIVERT_KEY => true }

          ran = call(job, "within_1_minute")

          assert ran
        end
      end
    end
  end
end
