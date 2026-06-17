# frozen_string_literal: true

module Sidekiq
  module Routing
    # Sidekiq Web "Routing" tab. Read-only: it displays routing state only
    # (active routes + parking-queue depth/breakdown). Every mutating
    # operation (park, blackhole, unpark, sweep, process_parked) is performed from the
    # Rails console via the Sidekiq::Routing API — never from the dashboard — so
    # destructive actions stay deliberate and don't ride on the shared
    # Sidekiq Web credentials. Reads aggregates live from Redis; never emits
    # per-job telemetry. Inherits the existing Sidekiq Web auth.
    module WebExtension
      VIEWS = File.expand_path("web/views", __dir__)

      def self.registered(app)
        app.get "/routing" do
          @parked_queue = Sidekiq::Routing.parked_queue
          @routes = Sidekiq::Routing.routes
          @parked_size = Sidekiq::Routing.parked_size
          @breakdown_sample = Sidekiq::Routing.configuration.breakdown_sample_size
          @parked_breakdown = Sidekiq::Routing.parked_breakdown
          erb(File.read(File.join(VIEWS, "routing.erb")))
        end
      end
    end
  end
end
