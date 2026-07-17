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
          raw && parse_entry(name, raw)
        end

        # -> { "ClassName" => {"mode"=>...}, ... }
        def all
          Sidekiq.redis { |conn| conn.hgetall(HASH_KEY) }
            .each_with_object({}) do |(name, raw), routes|
              entry = parse_entry(name, raw)
              routes[name] = entry if entry
            end
        end

        private

          # A route entry must be a JSON object; anything else is skipped with a
          # warning, never raised on. The reads feed the client-middleware hot
          # path inside every perform_async, and the raw value can be foreign
          # data — e.g. a desynced pooled connection handing HGETALL the reply
          # of a RESP HELLO handshake ({"server"=>"redis", "proto"=>"3", ...}).
          def parse_entry(name, raw)
            entry = JSON.parse(raw)
            entry.is_a?(Hash) ? entry : warn_invalid(name, raw)
          rescue JSON::ParserError
            warn_invalid(name, raw)
          end

          # -> nil
          def warn_invalid(name, raw)
            Routing.logger.warn(
              "[Routing] ignoring invalid route entry #{name.inspect} => #{raw.inspect.byteslice(0, 200)}")
            nil
          end
      end
    end
  end
end
