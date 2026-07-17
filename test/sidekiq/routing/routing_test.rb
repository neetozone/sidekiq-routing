# frozen_string_literal: true

require "test_helper"

module Sidekiq
  module Routing
    class RoutingTest < Minitest::Test
      class ParkableJob
        include Sidekiq::Job
      end

      def setup
        Sidekiq.redis { |conn| conn.del(Store::HASH_KEY) }
        Routing.reset_cache!
        Routing.configuration.cache_ttl_seconds = 5
      end

      def teardown
        Sidekiq.redis { |conn| conn.del(Store::HASH_KEY) }
        Routing.reset_cache!
      end

      def test_park_marks_the_class_in_park_mode
        Routing.park(ParkableJob)

        assert Routing.parked?(ParkableJob)
        assert_equal "park", Routing.mode(ParkableJob)
      end

      def test_blackhole_marks_the_class_in_blackhole_mode
        Routing.blackhole("FireAndForgetJob")

        assert_equal "blackhole", Routing.mode("FireAndForgetJob")
      end

      def test_unpark_removes_the_route
        Routing.park(ParkableJob)
        Routing.unpark(ParkableJob)

        refute Routing.parked?(ParkableJob)
        refute Routing.routed?(ParkableJob)
        assert_nil Routing.mode(ParkableJob)
      end

      def test_parked_only_reports_park_mode
        Routing.blackhole(ParkableJob)

        refute Routing.parked?(ParkableJob)
        assert Routing.routed?(ParkableJob)
      end

      def test_routes_lists_all_active_routes
        Routing.park("JobA")
        Routing.blackhole("JobB")

        assert_equal %w[JobA JobB], Routing.routes.keys.sort
      end

      def test_class_name_prefers_string_then_class_name
        assert_equal "Explicit", Routing.class_name("Explicit")
        assert_equal "Sidekiq::Routing::RoutingTest::ParkableJob",
          Routing.class_name(ParkableJob)
        assert_nil Routing.class_name(nil)
      end

      def test_route_for_reflects_state_after_flip_via_api
        # The API resets the cache, so the snapshot reflects the flip immediately.
        assert_nil Routing.route_for(ParkableJob)

        Routing.park(ParkableJob)
        assert_equal "park", Routing.route_for(ParkableJob)["mode"]

        Routing.unpark(ParkableJob)
        assert_nil Routing.route_for(ParkableJob)
      end

      def test_route_for_caches_until_ttl_expires
        # Write directly to the store (bypassing the API's reset_cache!) and
        # prime the snapshot; a cached read should not see the later direct write.
        Routing.route_for("JobX") # primes an empty snapshot
        Store.set("JobX", mode: "park")

        assert_nil Routing.route_for("JobX"), "snapshot should still be cached"

        Routing.reset_cache!
        assert_equal "park", Routing.route_for("JobX")["mode"]
      end

      def test_parked_breakdown_respects_the_sample_limit
        parked = Routing.parked_queue
        Sidekiq.redis { |conn| conn.del("queue:#{parked}") }
        3.times do |i|
          Mover.move(
            { "class" => "BreakdownJob", "args" => [i], "jid" => "b#{i}" },
            parked, ORIGINAL_QUEUE_KEY => "within_1_minute")
        end

        breakdown = Routing.parked_breakdown(sample: 2)

        assert_equal 2, breakdown["BreakdownJob"]["count"], "should only scan the sampled head"
      ensure
        Sidekiq.redis { |conn| conn.del("queue:#{Routing.parked_queue}") }
      end

      def test_route_for_with_zero_ttl_always_reads_fresh
        Routing.configuration.cache_ttl_seconds = 0
        Routing.route_for("JobY")
        Store.set("JobY", mode: "blackhole")

        assert_equal "blackhole", Routing.route_for("JobY")["mode"]
      ensure
        Routing.configuration.cache_ttl_seconds = 5
      end

      # The snapshot refresh runs inside every perform_async (client
      # middleware); a Redis hiccup there must never fail the push.
      def test_route_for_returns_nil_when_the_first_refresh_fails
        Store.stubs(:all).raises(RedisClient::ConnectionError, "boom")

        assert_nil Routing.route_for(ParkableJob)
      end

      def test_route_for_keeps_serving_the_stale_snapshot_when_a_refresh_fails
        Routing.configuration.cache_ttl_seconds = 0.01
        Routing.park(ParkableJob)
        assert_equal "park", Routing.route_for(ParkableJob)["mode"] # primes the snapshot

        sleep 0.02 # let the TTL lapse so the next read refreshes
        Store.stubs(:all).raises(RedisClient::ConnectionError, "boom")

        assert_equal "park", Routing.route_for(ParkableJob)["mode"]
      ensure
        Routing.configuration.cache_ttl_seconds = 5
      end

      def test_failed_refresh_is_not_retried_until_the_next_ttl_window
        Store.expects(:all).raises(RedisClient::ConnectionError, "boom").once

        assert_nil Routing.route_for(ParkableJob)
        assert_nil Routing.route_for(ParkableJob) # within TTL: served from the cached empty snapshot
      end
    end
  end
end
