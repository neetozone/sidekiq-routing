# frozen_string_literal: true

module Sidekiq
  module Routing
    module Middleware
      # Handles the backlog: jobs already enqueued before the route was added,
      # plus scheduled/retry-set jobs that re-enter their real queue (those do not
      # pass through client middleware, so this is the only thing that catches
      # them). Park re-pushes the job to the parking queue; blackhole acks and
      # drops it (never the Dead set).
      #
      # Registered AFTER SidekiqUniqueJobs::Middleware::Server so that returning
      # without yield still lets unique-jobs release the original's lock.
      class Server
        def call(worker, job, queue)
          return yield unless Routing.enabled?
          return yield if queue.to_s == Routing.parked_queue # loop guard: run parked jobs
          return yield if job[NO_DIVERT_KEY]

          route = Routing.route_for(job["wrapped"] || worker.class)
          return yield unless route

          case route["mode"]
          when MODE_BLACKHOLE
            nil # ack & drop; NOT the Dead set
          when MODE_PARK
            Mover.move(
              job, Routing.parked_queue,
              ORIGINAL_QUEUE_KEY => job[ORIGINAL_QUEUE_KEY] || queue.to_s)
            nil # ack & remove original; the copy now lives in the parking queue
          else
            yield
          end
        end
      end
    end
  end
end
