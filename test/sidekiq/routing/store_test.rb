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
    end
  end
end
