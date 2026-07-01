# frozen_string_literal: true

require "test_helper"

module Sidekiq
  module Routing
    class QueueCompositionTest < Minitest::Test
      def setup
        clear_queue
      end

      def teardown
        clear_queue
      end

      def clear_queue
        Sidekiq.redis { |conn| conn.del("queue:composition_source") }
      end

      def seed(klass_name, enqueued_at:, jid: SecureRandom.hex(6))
        seed_item({ "class" => klass_name, "args" => [], "jid" => jid }, enqueued_at:)
      end

      def seed_item(item, enqueued_at:)
        Mover.move(item.merge("enqueued_at" => enqueued_at.to_f), "composition_source")
      end

      def test_groups_live_queue_by_display_class_sorted_by_count
        now = Time.now
        seed("GoodJob", enqueued_at: now - 120)
        seed("BadJob", enqueued_at: now - 30)
        seed("BadJob", enqueued_at: now - 90)

        report = QueueComposition.new("composition_source", scan_limit: 10, now:).call

        assert_equal "BadJob", report.offender["class"]
        assert_equal 2, report.offender["count"]
        assert_in_delta 90, report.offender["oldest_age_seconds"], 1
      end

      def test_respects_scan_limit_and_reports_queue_size
        now = Time.now
        3.times { |index| seed("Job#{index}", enqueued_at: now - index) }

        report = QueueComposition.new("composition_source", scan_limit: 2, now:).call

        assert_equal 2, report.scanned
        assert_equal 3, report.size
        assert_equal 2, report.rows.sum { |row| row["count"] }
      end

      def test_uses_display_class_so_active_job_wrappers_are_unwrapped
        seed_item(
          {
            "class" => "ActiveJob::QueueAdapters::SidekiqAdapter::JobWrapper",
            "wrapped" => "RealActiveJob",
            "args" => [],
            "jid" => "active-job"
          },
          enqueued_at: Time.now
        )

        report = QueueComposition.new("composition_source", scan_limit: 10).call

        assert_equal "RealActiveJob", report.offender["class"]
      end

      def test_routing_queue_composition_exposes_the_public_helper
        seed("BadJob", enqueued_at: Time.now)

        report = Routing.queue_composition("composition_source", scan_limit: 10)

        assert_equal "composition_source", report.queue
        assert_equal "BadJob", report.offender["class"]
      end

      def test_report_formats_like_the_incident_console_snippet
        seed("BadJob", enqueued_at: Time.now - 60)

        output = Routing.queue_composition("composition_source", scan_limit: 10).to_s

        assert_includes output, "BadJob"
        assert_includes output, "count=1"
        assert_includes output, "scanned 1 of 1 (cap 10)"
      end

      def test_rejects_blank_queue_name
        assert_raises(ArgumentError) do
          QueueComposition.new("")
        end
      end

      def test_rejects_negative_scan_limit
        assert_raises(ArgumentError) do
          QueueComposition.new("composition_source", scan_limit: -1)
        end
      end
    end
  end
end
