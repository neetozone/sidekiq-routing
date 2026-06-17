# frozen_string_literal: true

module Sidekiq
  module Routing::Auto
    class JobDurationTracker
      REDIS_KEY_PREFIX = "sidekiq:auto_reroute:durations"

      def self.average_duration(job_class, queue)
        key = redis_key(job_class, queue)
        cutoff = Time.now.to_i - Routing::Auto.configuration.duration_tracking_window

        entries = Sidekiq.redis do |redis|
          redis.zrangebyscore(key, cutoff, "+inf")
        end

        return nil if entries.empty?

        durations = entries.map { |entry| entry.split(":").last.to_f }
        (durations.sum / durations.size).round
      end

      def self.tracked_job_classes(queue)
        pattern = "#{REDIS_KEY_PREFIX}:*:#{queue}"
        prefix = "#{REDIS_KEY_PREFIX}:"
        suffix = ":#{queue}"

        # Class names contain "::" so split-by-colon mangles them. Strip the
        # known prefix/suffix instead — works for any namespaced class.
        Sidekiq.redis do |redis|
          redis.keys(pattern).map { |key| key.delete_prefix(prefix).delete_suffix(suffix) }
        end
      end

      def self.redis_key(job_class, queue)
        "#{REDIS_KEY_PREFIX}:#{job_class}:#{queue}"
      end

      # Match Sidekiq::JobRecord#klass so duration writes line up with the
      # name NoisyNeighborDetector queries by (job.klass already unwraps
      # ActiveJob wrappers; without this, ActiveJob jobs would record under
      # JobWrapper and never be looked up).
      def self.job_class_name(worker, job)
        job["wrapped"] || worker.class.name
      end

      def call(worker, job, queue)
        start_time = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
        yield
      ensure
        duration_ms = ((::Process.clock_gettime(::Process::CLOCK_MONOTONIC) - start_time) * 1000).round
        begin
          record_duration(self.class.job_class_name(worker, job), queue, duration_ms)
        rescue StandardError => e
          Routing::Auto.logger.warn("[JobDurationTracker] failed to record duration: #{e.message}")
        end
      end

      def record_duration(job_class, queue, duration_ms)
        key = redis_key(job_class, queue)
        timestamp = Time.now.to_i

        Sidekiq.redis do |redis|
          redis.zadd(key, timestamp, "#{timestamp}:#{duration_ms}")
          redis.expire(key, Routing::Auto.configuration.duration_tracking_window * 2)

          cutoff = timestamp - Routing::Auto.configuration.duration_tracking_window
          redis.zremrangebyscore(key, "-inf", cutoff)
        end
      end

      private

        def redis_key(job_class, queue)
          self.class.redis_key(job_class, queue)
        end
    end
  end
end
