# frozen_string_literal: true

module Sidekiq
  module Routing
    module Middleware
      # Handles inflow: new jobs at enqueue time (perform_async/perform_in,
      # push_bulk). Blackhole aborts the push; park rewrites the queue so the job
      # lands in the worker-less parking queue.
      #
      # No per-job log or metric here — during a flood that would emit millions
      # of lines. Observability is the Web tab's live aggregates + operator-action
      # logs only (see docs/routing-how-it-works.md).
      class Client
        def call(worker_class, job, queue, _redis_pool = nil)
          return yield unless Routing.enabled?
          return yield if job[NO_DIVERT_KEY] # process_parked / explicit bypass
          return yield if queue.to_s == Routing.parked_queue # never re-divert parked jobs

          route = Routing.route_for(job["wrapped"] || worker_class)
          return yield unless route

          case route["mode"]
          when MODE_BLACKHOLE
            false # abort push — never enters Redis
          when MODE_PARK
            job[ORIGINAL_QUEUE_KEY] ||= queue.to_s # preserve true origin across re-diverts
            job["queue"] = Routing.parked_queue
            yield # push, but to the parking queue
          else
            yield
          end
        end
      end
    end
  end
end
