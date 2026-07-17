# frozen_string_literal: true

require "test_helper"

module Sidekiq
  module Routing
    class StoreTest < Minitest::Test
      def setup
        Sidekiq.redis { |conn| conn.del(Store::HASH_KEY) }
      end

      def test_set_and_fetch_round_trips_mode_and_metadata
        Store.set("SomeJob", mode: "blackhole")

        entry = Store.fetch("SomeJob")
        assert_equal "blackhole", entry["mode"]
        refute_nil entry["routed_at"]
      end

      def test_fetch_returns_nil_for_unknown_class
        assert_nil Store.fetch("NeverRoutedJob")
      end

      def test_delete_removes_the_entry
        Store.set("SomeJob", mode: "blackhole")
        Store.delete("SomeJob")

        assert_nil Store.fetch("SomeJob")
      end

      def test_all_returns_parsed_entries_keyed_by_class
        Store.set("JobA", mode: "park")
        Store.set("JobB", mode: "blackhole")

        all = Store.all
        assert_equal %w[JobA JobB], all.keys.sort
        assert_equal "park", all["JobA"]["mode"]
        assert_equal "blackhole", all["JobB"]["mode"]
      end

      # A desynced Redis connection can hand HGETALL the reply of another
      # command — e.g. the RESP HELLO handshake map, whose values ("redis",
      # "7.4.0", "3", ...) are not route entries. Foreign values must be
      # skipped, never raised on (neeto-desk-web HB fault 132106676).
      def test_all_skips_values_that_are_not_json
        Store.set("JobA", mode: "park")
        Sidekiq.redis { |conn| conn.hset(Store::HASH_KEY, "server", "redis") }

        assert_equal({ "JobA" => Store.fetch("JobA") }, Store.all)
      end

      def test_all_skips_json_values_that_are_not_objects
        Store.set("JobA", mode: "park")
        Sidekiq.redis { |conn| conn.hset(Store::HASH_KEY, "proto", "3") }

        assert_equal({ "JobA" => Store.fetch("JobA") }, Store.all)
      end

      def test_fetch_returns_nil_for_a_value_that_is_not_json
        Sidekiq.redis { |conn| conn.hset(Store::HASH_KEY, "server", "redis") }

        assert_nil Store.fetch("server")
      end

      def test_fetch_returns_nil_for_a_json_value_that_is_not_an_object
        Sidekiq.redis { |conn| conn.hset(Store::HASH_KEY, "proto", "3") }

        assert_nil Store.fetch("proto")
      end
    end
  end
end
