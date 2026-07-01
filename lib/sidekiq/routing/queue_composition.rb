# frozen_string_literal: true

module Sidekiq
  module Routing
    # Read-only, capped scan of a live queue grouped by displayed job class.
    # Used during incidents to answer: "which class is flooding this SLA tier?"
    class QueueComposition
      DEFAULT_SCAN_LIMIT = 250_000

      Report = Struct.new(:queue, :rows, :scanned, :size, :scan_limit, keyword_init: true) do
        def offender
          rows.first
        end

        def to_h
          {
            "queue" => queue,
            "rows" => rows.map(&:dup),
            "scanned" => scanned,
            "size" => size,
            "scan_limit" => scan_limit
          }
        end

        def to_s
          lines = rows.map do |row|
            age = row["oldest_age_seconds"] ? "#{row["oldest_age_seconds"].round}s ago" : "n/a"
            format("%-55s count=%-9d oldest=%s", row["class"], row["count"], age)
          end
          lines << "scanned #{scanned} of #{size} (cap #{scan_limit})"
          lines.join("\n")
        end

        alias inspect to_s
      end

      def initialize(queue_name, scan_limit: DEFAULT_SCAN_LIMIT, now: Time.now)
        @queue_name = normalize_queue_name(queue_name)
        @scan_limit = normalize_scan_limit(scan_limit)
        @now = now
      end

      def call
        by_class = Hash.new { |hash, key| hash[key] = { count: 0, oldest_at: nil } }
        queue = Sidekiq::Queue.new(@queue_name)
        scanned = 0

        queue.each do |job|
          break if scanned >= @scan_limit

          scanned += 1
          row = by_class[job.display_class]
          row[:count] += 1

          enqueued_at = job.enqueued_at
          row[:oldest_at] = enqueued_at if older?(enqueued_at, row[:oldest_at])
        end

        Report.new(
          queue: @queue_name,
          rows: build_rows(by_class),
          scanned: scanned,
          size: queue.size,
          scan_limit: @scan_limit
        )
      end

      private

        def build_rows(by_class)
          by_class.sort_by { |klass, stats| [-stats[:count], klass] }.map do |klass, stats|
            oldest_at = stats[:oldest_at]
            {
              "class" => klass,
              "count" => stats[:count],
              "oldest_at" => oldest_at,
              "oldest_age_seconds" => oldest_at && (@now - oldest_at)
            }
          end
        end

        def normalize_queue_name(queue_name)
          name = queue_name.to_s
          raise ArgumentError, "queue_name must be present" if name.empty?

          name
        end

        def normalize_scan_limit(scan_limit)
          limit = begin
            Integer(scan_limit)
          rescue ArgumentError, TypeError
            raise ArgumentError, "scan_limit must be a non-negative integer"
          end
          raise ArgumentError, "scan_limit must be non-negative" if limit.negative?

          limit
        end

        def older?(candidate, current)
          candidate && (current.nil? || candidate < current)
        end
    end
  end
end
