# frozen_string_literal: true

require "time"

module Sidekiq
  module Routing
    # Source of truth for manual route state: a single Redis hash in Sidekiq's Redis,
    # field = job class name, value = JSON {mode, routed_at}.
    # These reads are uncached (used by the operator API and Web tab); the
    # middleware hot path uses Sidekiq::Routing.route_for instead.
    module Store
      HASH_KEY = "sidekiq:routing:routes"

      class << self
        def set(name, mode:)
          value = JSON.dump(
            "mode" => mode.to_s,
            "routed_at" => Time.now.utc.iso8601
          )
          Sidekiq.redis { |conn| conn.hset(HASH_KEY, name, value) }
        end

        def delete(name)
          Sidekiq.redis { |conn| conn.hdel(HASH_KEY, name) }
        end

        # -> {"mode"=>...} or nil
        def fetch(name)
          raw = Sidekiq.redis { |conn| conn.hget(HASH_KEY, name) }
          raw && JSON.parse(raw)
        end

        # -> { "ClassName" => {"mode"=>...}, ... }
        def all
          Sidekiq.redis { |conn| conn.hgetall(HASH_KEY) }
            .transform_values { |raw| JSON.parse(raw) }
        end
      end
    end
  end
end
