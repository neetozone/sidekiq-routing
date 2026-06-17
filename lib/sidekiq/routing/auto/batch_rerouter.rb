# frozen_string_literal: true

module Sidekiq
  module Routing::Auto
    class BatchRerouter
      def reroute_jobs(from_queue, to_queue, job_classes: nil)
        limit = Routing::Auto.configuration.batch_reroute_limit
        moved_count = 0
        skipped = { already_rerouted: 0, wrong_class: 0, excluded: 0 }
        queue = Sidekiq::Queue.new(from_queue)

        Routing::Auto.logger.info(
          "[Routing::Auto] reroute_jobs: from=#{from_queue}, to=#{to_queue}, " \
          "limit=#{limit}, job_classes=#{job_classes.inspect}"
        )

        queue.each do |job|
          break if moved_count >= limit

          if job.item["auto_rerouted"]
            skipped[:already_rerouted] += 1
            next
          end

          if job_classes && !job_classes.include?(job.klass)
            skipped[:wrong_class] += 1
            next
          end

          if Routing::Auto.configuration.excluded_job_classes.include?(job.klass)
            skipped[:excluded] += 1
            next
          end

          moved_count += 1 if reroute_single_job(job, from_queue, to_queue)
        end

        Routing::Auto.logger.info(
          "[Routing::Auto] reroute_jobs: moved=#{moved_count}, skipped=#{skipped.inspect}"
        )
        log_reroute(from_queue, to_queue, moved_count, job_classes) if moved_count.positive?

        moved_count
      end

      private

        def reroute_single_job(job, from_queue, to_queue)
          new_item = job.item.merge(
            "queue" => to_queue,
            "auto_rerouted" => true,
            "original_queue" => from_queue,
            "rerouted_at" => Time.now.to_i
          )

          job.delete if Sidekiq::Client.push(new_item)
        end

        def log_reroute(from_queue, to_queue, count, job_classes)
          message = "[Routing::Auto] Moved #{count} jobs from #{from_queue} to #{to_queue}"
          message += " (noisy neighbors: #{job_classes.join(', ')})" if job_classes&.any?

          Routing::Auto.logger.warn(message)
        end
    end
  end
end
