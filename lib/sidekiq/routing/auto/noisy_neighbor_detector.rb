# frozen_string_literal: true

module Sidekiq
  module Routing::Auto
    class NoisyNeighborDetector
      MIN_WORKLOAD_SECONDS = 10

      def initialize(queue_name)
        @queue_name = queue_name
        @queue = Sidekiq::Queue.new(queue_name)
        @duration_cache = {}
      end

      def identify_noisy_neighbors
        workload = calculate_workload_by_class
        total_workload = workload.values.sum
        return [] if total_workload < MIN_WORKLOAD_SECONDS

        threshold = Routing::Auto.configuration.noisy_neighbor_threshold_percent

        workload.select do |_job_class, workload_seconds|
          ((workload_seconds / total_workload.to_f) * 100) > threshold
        end.keys
      end

      def calculate_workload_by_class
        result = Hash.new(0.0)

        @queue.each do |job|
          duration_ms = get_duration_for_class(job.klass)
          next unless duration_ms

          result[job.klass] += duration_ms / 1000.0
        end

        result
      end

      def total_estimated_workload
        calculate_workload_by_class.values.sum
      end

      private

        def get_duration_for_class(job_class)
          return @duration_cache[job_class] if @duration_cache.key?(job_class)

          @duration_cache[job_class] = JobDurationTracker.average_duration(job_class, @queue_name)
        end
    end
  end
end
