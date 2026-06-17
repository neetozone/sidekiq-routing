# frozen_string_literal: true

require "sidekiq/routing/web_extension"

# Registers the "Routing" tab. The registration API changed across Sidekiq
# versions, so branch the way sidekiq-cron does (apps run 7.3.x; commons locks 8.x).
if defined?(Sidekiq::Web)
  if Gem::Version.new(Sidekiq::VERSION) >= Gem::Version.new("8.0.0")
    Sidekiq::Web.configure do |config|
      config.register(
        Sidekiq::Routing::WebExtension,
        name: "routing",
        tab: "Routing",
        index: "routing"
      )
    end
  elsif Gem::Version.new(Sidekiq::VERSION) >= Gem::Version.new("7.3.0")
    Sidekiq::Web.register(
      Sidekiq::Routing::WebExtension,
      name: "routing",
      tab: "Routing",
      index: "routing"
    )
  else
    Sidekiq::Web.register Sidekiq::Routing::WebExtension
    Sidekiq::Web.tabs["Routing"] = "routing"
  end
end
