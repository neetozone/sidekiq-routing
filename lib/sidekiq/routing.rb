# frozen_string_literal: true

require "sidekiq"
require "sidekiq/api"
require "json"

# Runtime, per-job-class parking/blackhole mechanism for Sidekiq incident response.
#
# Two modes per job class (see lib/sidekiq/CONTEXT.md and
# docs/routing-how-it-works.md):
#   - park (default, reversible): divert jobs to a worker-less parking queue.
#   - blackhole: drop jobs entirely (only for classes safe to lose).
#
# State lives in a single Redis hash; the hot path reads a whole-hash snapshot
# refreshed at most once per cache_ttl_seconds, so per-job cost is an in-memory
# lookup rather than a Redis round-trip.
module Sidekiq
  module Routing
    PARKED_QUEUE_DEFAULT = "routing_parked"

    # Keys stamped into the job payload.
    ORIGINAL_QUEUE_KEY = "routing_original_queue"
    NO_DIVERT_KEY = "routing_no_divert"

    MODE_PARK = "park"
    MODE_BLACKHOLE = "blackhole"
    MODES = [MODE_PARK, MODE_BLACKHOLE].freeze

    EMPTY_ROUTES = {}.freeze

    @snapshot = nil
    @snapshot_at = nil
    @snapshot_mutex = Mutex.new

    class << self
      def configuration
        @_configuration ||= Configuration.new
      end

      def setup
        yield configuration if block_given?
      end

      # Registers the manual routing client + server middleware on both client
      # and server configurations. This mirrors Sidekiq::Lock.install! so host
      # apps can add the gem first and opt in to routing per app.
      def install!
        require "sidekiq/routing/middleware/client"
        require "sidekiq/routing/middleware/server"

        prepend_routing = ->(chain) { chain.prepend Middleware::Client }

        Sidekiq.configure_client do |config|
          config.client_middleware(&prepend_routing)
        end

        Sidekiq.configure_server do |config|
          config.client_middleware(&prepend_routing)
          config.server_middleware { |chain| install_server_middleware(chain) }
        end
      end

      def enabled?
        configuration.enabled
      end

      def logger
        configuration.logger
      end

      def parked_queue
        configuration.parked_queue
      end

      # ---- operator API: managing manual routes ----

      def park(klass)
        write(klass, MODE_PARK)
      end

      def blackhole(klass)
        write(klass, MODE_BLACKHOLE)
      end

      def unpark(klass)
        name = class_name(klass)
        Store.delete(name)
        reset_cache!
        logger.warn("[Routing] unparked #{name}")
        name
      end

      def parked?(klass)
        mode(klass) == MODE_PARK
      end

      def routed?(klass)
        !Store.fetch(class_name(klass)).nil?
      end

      def mode(klass)
        Store.fetch(class_name(klass))&.fetch("mode", nil)
      end

      # All active manual routes, read straight from Redis (uncached) so operators
      # and the Web tab always see the truth.
      def routes
        Store.all
      end

      # ---- hot path: snapshot lookup, used by the middleware ----

      # Returns the route hash ({"mode"=>...}) for a class, or nil. Reads from a
      # process-local snapshot of all routes, refreshed at most once per
      # cache_ttl_seconds.
      def route_for(klass_or_name)
        snapshot[class_name(klass_or_name)]
      end

      def reset_cache!
        @snapshot_mutex.synchronize do
          @snapshot = nil
          @snapshot_at = nil
        end
      end

      # ---- queue introspection ----

      def queue_composition(queue_name, scan_limit: QueueComposition::DEFAULT_SCAN_LIMIT)
        QueueComposition.new(queue_name, scan_limit:).call
      end

      def parked_size
        Sidekiq::Queue.new(parked_queue).size
      end

      # { "SomeJob" => { "count" => 12, "by_original_queue" => { "within_1_minute" => 12 } } }
      #
      # Scans at most `sample` jobs (default Configuration#breakdown_sample_size), not the
      # whole queue: the parking queue can hold millions during a flood and this is called on
      # every Web tab load. The result is a distribution over the sampled head, not exact
      # totals — use parked_size (O(1) LLEN) for the true total. Pass sample: nil to scan all.
      def parked_breakdown(sample: configuration.breakdown_sample_size)
        result = Hash.new { |h, k| h[k] = { "count" => 0, "by_original_queue" => Hash.new(0) } }
        scanned = 0
        Sidekiq::Queue.new(parked_queue).each do |job|
          break if sample && scanned >= sample

          klass = job.display_class
          original = job.item[ORIGINAL_QUEUE_KEY] || "unknown"
          result[klass]["count"] += 1
          result[klass]["by_original_queue"][original] += 1
          scanned += 1
        end
        result
      end

      # ---- recovery (thin wrappers; logic in Sweeper/ParkedProcessor) ----

      def sweep(klass, queue: nil, limit: nil, batch_size: nil)
        Sweeper.new.call(class_name(klass), queue:, limit:, batch_size:)
      end

      def process_parked(klass: nil, limit: nil, batch_size: nil)
        ParkedProcessor.new.call(klass: klass && class_name(klass), limit:, batch_size:)
      end

      # Resolve the effective job-class name. Prefers the ActiveJob "wrapped"
      # class so a wrapped job is matched by its real class, not the JobWrapper
      # (mirrors Sidekiq's own display_class). Accepts a Class, String, or nil.
      def class_name(klass_or_name)
        return klass_or_name if klass_or_name.is_a?(String)

        klass_or_name&.name
      end

      private

        def install_server_middleware(chain)
          unique_jobs = defined?(SidekiqUniqueJobs::Middleware::Server) && SidekiqUniqueJobs::Middleware::Server
          if unique_jobs && chain.exists?(unique_jobs)
            chain.insert_after unique_jobs, Middleware::Server
          else
            chain.add Middleware::Server
          end
        end

        def write(klass, mode)
          name = class_name(klass)
          Store.set(name, mode:)
          reset_cache!
          logger.warn("[Routing] #{name} routed to #{mode}")
          name
        end

        def snapshot
          ttl = configuration.cache_ttl_seconds.to_f
          now = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
          current = @snapshot
          return current if current && ttl.positive? && (now - @snapshot_at) < ttl

          @snapshot_mutex.synchronize do
            current = @snapshot
            fresh = current && ttl.positive? && (now - @snapshot_at) < ttl
            unless fresh
              @snapshot = refresh_snapshot(current)
              @snapshot_at = now
              current = @snapshot
            end
          end
          current
        end

        # Fail open: the refresh runs inside every perform_async via the client
        # middleware, so a Redis hiccup here must never fail the push. Keep
        # serving the previous snapshot (or route nothing) until the next TTL
        # window instead of raising.
        def refresh_snapshot(current)
          Store.all.freeze
        rescue StandardError => error
          fallback = current ? "keeping stale snapshot" : "routing nothing this TTL window"
          logger.warn("[Routing] snapshot refresh failed, #{fallback} (#{error.class}: #{error.message})")
          current || EMPTY_ROUTES
        end
    end
  end
end
