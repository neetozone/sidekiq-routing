# frozen_string_literal: true

module Sidekiq
  module Routing
    # Eagerly clears the already-enqueued backlog of a parked class out of its
    # live queue(s) and into the parking queue. Explicit operator action — never
    # automatic on park. For a 100Ks+ backlog, prefer drain-in-place over moving
    # millions of jobs.
    class Sweeper
      def call(klass_name, queue: nil, limit: nil, batch_size: nil)
        limit ||= Routing.configuration.batch_limit
        requested_queue = queue.to_s.empty? ? nil : queue
        target_queues = Array(requested_queue || default_queues_for(klass_name))
        moved = 0

        target_queues.each do |source|
          next if source.to_s == Routing.parked_queue

          Sidekiq::Queue.new(source).each do |job|
            break if limit && moved >= limit
            next unless job.display_class == klass_name

            Mover.move(
              job.item, Routing.parked_queue,
              ORIGINAL_QUEUE_KEY => job.item[ORIGINAL_QUEUE_KEY] || source.to_s)
            moved += 1 if job.delete
          end
        end

        Routing.logger.warn(
          "[Routing] swept #{moved} #{klass_name} job(s) into #{Routing.parked_queue}"
        )
        moved
      end

      private

        # The class's configured queue if we can resolve it. We deliberately do NOT
        # fall back to scanning every queue: during an incident that would hammer
        # Redis and slow healthy queues. If the queue can't be resolved, the operator
        # must say which queue(s) to sweep.
        def default_queues_for(klass_name)
          klass = safe_constantize(klass_name)
          configured = klass.respond_to?(:get_sidekiq_options) ? klass.get_sidekiq_options["queue"] : nil
          return [configured.to_s] if configured

          raise ArgumentError,
            "Cannot resolve a queue for #{klass_name}; pass queue: explicitly so the sweep " \
            "does not scan every queue, e.g. Sidekiq::Routing.sweep(#{klass_name.inspect}, queue: \"within_1_minute\")."
        end

        # Plain-Ruby stand-in for ActiveSupport's String#safe_constantize:
        # resolve a (possibly namespaced) class name, or nil if it isn't loaded.
        def safe_constantize(name)
          Object.const_get(name)
        rescue NameError
          nil
        end
    end
  end
end
