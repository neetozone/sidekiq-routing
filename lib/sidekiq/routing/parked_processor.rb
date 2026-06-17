# frozen_string_literal: true

module Sidekiq
  module Routing
    # Moves parked jobs back to their original queue by rewriting the "queue"
    # field inside the payload (read item -> set queue -> push -> delete). Because
    # the payload's queue is now the original, a processed parked job that later
    # fails retries to its original queue, NOT the parking queue.
    #
    # Stamps NO_DIVERT_KEY so the job is not bounced straight back to parked even
    # if the route is still active (recommended order is still: unpark, then
    # process_parked).
    class ParkedProcessor
      def call(klass: nil, limit: nil, batch_size: nil)
        limit ||= Routing.configuration.batch_limit
        fallback = Routing.configuration.process_parked_fallback_queue
        moved = 0

        Sidekiq::Queue.new(Routing.parked_queue).each do |job|
          break if limit && moved >= limit
          next if klass && job.display_class != klass

          target = job.item[ORIGINAL_QUEUE_KEY]
          unless target
            target = fallback
            Routing.logger.warn(
              "[Routing] #{job.display_class} #{job.jid} had no original queue; processing parked job to #{fallback}"
            )
          end

          payload = job.item.reject { |key, _| key == ORIGINAL_QUEUE_KEY }
          Mover.move(payload, target, NO_DIVERT_KEY => true)
          moved += 1 if job.delete
        end

        Routing.logger.warn("[Routing] processed #{moved} parked job(s) from #{Routing.parked_queue}")
        moved
      end
    end
  end
end
