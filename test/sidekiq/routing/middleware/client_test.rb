# frozen_string_literal: true

require "test_helper"

module Sidekiq
  module Routing
    module Middleware
      class ClientTest < Minitest::Test
        class ClientJob
          include Sidekiq::Job
        end

        def setup
          Sidekiq.redis { |conn| conn.del(Store::HASH_KEY) }
          Routing.reset_cache!
          Routing.configuration.cache_ttl_seconds = 5
          @middleware = Client.new
        end

        def teardown
          Sidekiq.redis { |conn| conn.del(Store::HASH_KEY) }
          Routing.reset_cache!
        end

        def call(worker_class, job, queue)
          yielded = false
          result = @middleware.call(worker_class, job, queue, nil) { yielded = true }
          [result, yielded]
        end

        def test_park_diverts_to_parking_queue_and_yields
          Routing.park(ClientJob)
          job = { "class" => "ClientJob", "args" => [] }

          _result, yielded = call(ClientJob, job, "within_1_minute")

          assert yielded
          assert_equal "routing_parked", job["queue"]
          assert_equal "within_1_minute", job[ORIGINAL_QUEUE_KEY]
        end

        def test_park_preserves_existing_original_queue
          Routing.park(ClientJob)
          job = { "class" => "ClientJob", "args" => [], ORIGINAL_QUEUE_KEY => "within_5_seconds" }

          call(ClientJob, job, "within_1_minute")

          assert_equal "within_5_seconds", job[ORIGINAL_QUEUE_KEY]
        end

        def test_blackhole_aborts_the_push
          Routing.blackhole(ClientJob)
          job = { "class" => "ClientJob", "args" => [] }

          result, yielded = call(ClientJob, job, "within_1_minute")

          refute yielded
          assert_equal false, result
        end

        def test_not_routed_yields_unchanged
          job = { "class" => "ClientJob", "args" => [] }

          _result, yielded = call(ClientJob, job, "within_1_minute")

          assert yielded
          assert_nil job["queue"]
        end

        def test_no_divert_flag_yields_unchanged
          Routing.park(ClientJob)
          job = { "class" => "ClientJob", "args" => [], NO_DIVERT_KEY => true }

          _result, yielded = call(ClientJob, job, "within_1_minute")

          assert yielded
          assert_nil job["queue"]
        end

        def test_jobs_already_on_parking_queue_are_not_re_diverted
          Routing.park(ClientJob)
          job = { "class" => "ClientJob", "args" => [] }

          _result, yielded = call(ClientJob, job, "routing_parked")

          assert yielded
        end

        def test_disabled_routing_yields_unchanged
          Routing.park(ClientJob)
          Routing.configuration.enabled = false
          job = { "class" => "ClientJob", "args" => [] }

          _result, yielded = call(ClientJob, job, "within_1_minute")

          assert yielded
          assert_nil job["queue"]
        ensure
          Routing.configuration.enabled = true
        end

        def test_resolves_active_job_wrapped_class
          Routing.park("RealActiveJob")
          job = {
            "class" => "ActiveJob::QueueAdapters::SidekiqAdapter::JobWrapper",
            "wrapped" => "RealActiveJob", "args" => []
          }

          _result, yielded = call("ActiveJob::QueueAdapters::SidekiqAdapter::JobWrapper", job, "within_1_minute")

          assert yielded
          assert_equal "routing_parked", job["queue"]
        end
      end
    end
  end
end
