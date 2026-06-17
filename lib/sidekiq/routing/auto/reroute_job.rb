# frozen_string_literal: true

require "sidekiq"

module Sidekiq
  module Routing::Auto
    # Periodic worker that drives latency-based rerouting: for each SLA queue
    # breaching its capacity threshold, move (noisy-neighbor) jobs to the next
    # tier. Schedule it via sidekiq-cron in the host app's scheduled_jobs.yml.
    #
    # Plain Sidekiq::Job (no app base class) so the gem carries no dependency on
    # the host's job hierarchy.
    class RerouteJob
      include Sidekiq::Job

      sidekiq_options queue: "within_1_minute", retry: false

      def perform
        return unless Sidekiq::Routing::Auto.enabled?

        Sidekiq::Routing::Auto::Router.sla_queues.each do |queue_name|
          process_queue(queue_name)
        end
      end

      private

        def process_queue(queue_name)
          return unless should_reroute?(queue_name)

          target_queue = Sidekiq::Routing::Auto::Router.next_queue_for(queue_name)
          return unless target_queue

          detector = Sidekiq::Routing::Auto::NoisyNeighborDetector.new(queue_name)
          noisy_neighbors = detector.identify_noisy_neighbors
          rerouter = Sidekiq::Routing::Auto::BatchRerouter.new

          if noisy_neighbors.any?
            rerouter.reroute_jobs(queue_name, target_queue, job_classes: noisy_neighbors)
          else
            rerouter.reroute_jobs(queue_name, target_queue)
          end
        end

        def should_reroute?(queue_name)
          sla_seconds = Sidekiq::Routing::Auto.configuration.sla_thresholds[queue_name]
          return false unless sla_seconds

          detector = Sidekiq::Routing::Auto::NoisyNeighborDetector.new(queue_name)
          estimated_workload = detector.total_estimated_workload
          capacity = calculate_capacity(queue_name, sla_seconds)
          capacity_used_percent = (estimated_workload / capacity.to_f) * 100
          threshold = Sidekiq::Routing::Auto.configuration.capacity_threshold_percent
          queue_size = Sidekiq::Queue.new(queue_name).size
          should_reroute = capacity_used_percent > threshold

          Sidekiq::Routing::Auto.logger.info(
            "[Routing::Auto] #{queue_name}: size=#{queue_size}, " \
            "workload=#{estimated_workload.round(1)}s, capacity=#{capacity.round(1)}s, " \
            "used=#{capacity_used_percent.round(1)}%, threshold=#{threshold}%, reroute=#{should_reroute}"
          )

          should_reroute
        end

        def calculate_capacity(queue_name, sla_seconds)
          total_concurrency = Sidekiq::ProcessSet.new.sum { |process| process["concurrency"] }.nonzero? || 10
          weight_fraction = queue_weight_fraction(queue_name)

          total_concurrency * weight_fraction * sla_seconds
        end

        def queue_weight_fraction(queue_name)
          queues = Sidekiq.default_configuration[:queues] || []
          total_weight = 0
          queue_weight = 1

          queues.each do |queue|
            if queue.is_a?(Array)
              name, weight = queue
              total_weight += weight
              queue_weight = weight if name == queue_name
            else
              total_weight += 1
              queue_weight = 1 if queue == queue_name
            end
          end

          total_weight.zero? ? 1.0 : queue_weight.to_f / total_weight
        end
    end
  end
end
