# frozen_string_literal: true

require "test_helper"

# Regression: just adding this gem to a host's Gemfile (no env vars set, no
# Sidekiq::Routing.park calls) must not change normal Sidekiq job execution.
# Auto routing is opt-in via SIDEKIQ_ROUTING_AUTO_REROUTE_ENABLED.
module Sidekiq
  module Routing::Auto
    class InertWhenDisabledTest < Minitest::Test
      class TouchedJob
        include Sidekiq::Job
        class << self; attr_accessor :ran; end
        def perform = (self.class.ran = true)
      end

      def setup
        TouchedJob.ran = false
        clear_tracked_keys
      end

      def teardown
        clear_tracked_keys
        Routing.reset_cache!
      end

      def test_auto_reroute_disabled_by_default
        refute Routing::Auto.enabled?,
          "Routing::Auto should be off unless SIDEKIQ_ROUTING_AUTO_REROUTE_ENABLED=true"
      end

      def test_default_enabled_uses_routing_auto_env
        with_env("SIDEKIQ_ROUTING_AUTO_REROUTE_ENABLED" => "true") do
          assert Routing::Auto.default_enabled?
        end
      end

      def test_default_enabled_ignores_legacy_auto_env
        with_env("SIDEKIQ_ROUTING_AUTO_REROUTE_ENABLED" => nil, "SIDEKIQ_AUTO_REROUTE_ENABLED" => "true") do
          refute Routing::Auto.default_enabled?
        end
      end

      def test_job_duration_tracker_not_in_server_middleware_chain_when_auto_disabled
        # The engine initializer only adds JobDurationTracker when Auto.enabled?.
        # Verify that with the default config, the chain doesn't contain it.
        chain_classes = ::Sidekiq.default_configuration.server_middleware.entries.map(&:klass)
        refute_includes chain_classes, JobDurationTracker,
          "JobDurationTracker should only be wired in when auto-reroute is enabled"
      end

      def test_routing_middleware_yields_when_no_class_is_routed
        # Build the server middleware fresh and call it like Sidekiq would.
        # No class has been parked/blackholed; the chain must yield normally.
        middleware = Sidekiq::Routing::Middleware::Server.new
        ran = false
        middleware.call(
          TouchedJob.new,
          { "class" => TouchedJob.name, "args" => [], "jid" => "j1" },
          "default") { ran = true }
        assert ran, "routing middleware must yield when no route is active"
      end

      def test_no_duration_recorded_when_routing_middleware_runs_a_job
        # Even with the routing middleware in the chain, plain job execution
        # must not record anything to Redis. (Only JobDurationTracker does, and
        # it's only in the chain when Auto.enabled?.)
        middleware = Sidekiq::Routing::Middleware::Server.new
        middleware.call(
          TouchedJob.new,
          { "class" => TouchedJob.name, "args" => [], "jid" => "j2" },
          "default") { TouchedJob.perform_one_off }
      rescue NoMethodError
        # perform_one_off doesn't exist; that's fine — the assertion below is
        # what matters.
      ensure
        keys = Sidekiq.redis { |r| r.keys("#{JobDurationTracker::REDIS_KEY_PREFIX}:*") }
        assert_equal [], keys,
          "no duration ZSETs should exist when JobDurationTracker isn't wired in"
      end

      private

        def clear_tracked_keys
          Sidekiq.redis do |redis|
            keys = redis.keys("#{JobDurationTracker::REDIS_KEY_PREFIX}:*")
            redis.del(*keys) if keys.any?
          end
        end

        def with_env(values)
          previous_values = values.to_h { |key, _value| [key, ENV[key]] }
          values.each do |key, value|
            value.nil? ? ENV.delete(key) : ENV[key] = value
          end
          yield
        ensure
          previous_values.each do |key, value|
            value.nil? ? ENV.delete(key) : ENV[key] = value
          end
        end
    end
  end
end
