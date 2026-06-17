# frozen_string_literal: true

require "test_helper"

module Sidekiq
  module Routing::Auto
    class JobDurationTrackerTest < Minitest::Test
      class PlainWorker
        include Sidekiq::Job
      end

      class ActiveJobWrapper; end

      def setup
        @middleware = JobDurationTracker.new
        @queue = "within_1_minute"
        clear_tracked_keys
      end

      def teardown
        clear_tracked_keys
      end

      def test_records_under_worker_class_for_plain_sidekiq_job
        job = { "class" => PlainWorker.name, "args" => [], "jid" => "j1" }

        @middleware.call(PlainWorker.new, job, @queue) {}

        assert_recorded(PlainWorker.name)
      end

      def test_records_under_wrapped_class_for_active_job
        job = {
          "class" => "ActiveJob::QueueAdapters::SidekiqAdapter::JobWrapper",
          "wrapped" => "MyMailerJob",
          "args" => [],
          "jid" => "j2"
        }

        @middleware.call(ActiveJobWrapper.new, job, @queue) {}

        assert_recorded("MyMailerJob")
      end

      def test_records_duration_even_when_job_raises
        job = { "class" => PlainWorker.name, "args" => [], "jid" => "j3" }

        assert_raises(RuntimeError) do
          @middleware.call(PlainWorker.new, job, @queue) { raise "boom" }
        end

        assert_recorded(PlainWorker.name)
      end

      def test_swallows_redis_errors_without_shadowing_job_exception
        job = { "class" => PlainWorker.name, "args" => [], "jid" => "j4" }
        @middleware.stubs(:record_duration).raises(StandardError, "redis down")

        error = assert_raises(RuntimeError) do
          @middleware.call(PlainWorker.new, job, @queue) { raise "boom" }
        end

        assert_equal "boom", error.message
      end

      private

        def assert_recorded(job_class)
          key = JobDurationTracker.redis_key(job_class, @queue)
          count = Sidekiq.redis { |redis| redis.zcard(key) }
          assert_equal 1, count, "expected a duration recorded under #{key}"
        end

        def clear_tracked_keys
          Sidekiq.redis do |redis|
            keys = redis.keys("#{JobDurationTracker::REDIS_KEY_PREFIX}:*")
            redis.del(*keys) if keys.any?
          end
        end
    end
  end
end
