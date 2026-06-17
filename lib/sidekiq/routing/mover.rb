# frozen_string_literal: true

module Sidekiq
  module Routing
    # Relocates an already-enqueued job payload to another queue by rewriting the
    # "queue" field *inside* the payload and writing it straight to Redis.
    #
    # It deliberately bypasses the client middleware chain. Going through
    # Sidekiq::Client.push would (a) risk re-diverting the job via our own client
    # middleware and (b) make sidekiq-unique-jobs try to re-acquire a lock that
    # the in-flight original still holds, which can fail the push and drop the job
    # on a server-side park. Moving the raw payload sidesteps both.
    #
    # Used by the server middleware (park), the Sweeper, and the ParkedProcessor.
    module Mover
      class << self
        # item:     the existing job hash (a Sidekiq::JobRecord#item or job hash)
        # to_queue: destination queue name
        # extra:    payload keys to merge in (e.g. the original-queue stamp)
        def move(item, to_queue, extra = {})
          target = to_queue.to_s
          payload = item.merge("queue" => target).merge(extra)
          json = Sidekiq.dump_json(payload)

          Sidekiq.redis do |conn|
            conn.sadd("queues", target) # keep the queue visible in the Web UI
            conn.lpush("queue:#{target}", json)
          end
          true
        end
      end
    end
  end
end
