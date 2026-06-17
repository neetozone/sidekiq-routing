# frozen_string_literal: true

require "test_helper"
require "sidekiq/web"
require "sidekiq/routing/web"

module Sidekiq
  module Routing
    class WebExtensionTest < Minitest::Test
      def test_web_extension_loads_and_is_registerable
        assert defined?(Sidekiq::Routing::WebExtension)
        assert_respond_to Sidekiq::Routing::WebExtension, :registered
      end

      def test_view_is_read_only_and_compiles
        path = File.join(WebExtension::VIEWS, "routing.erb")
        assert File.exist?(path), "expected view at #{path}"

        raw = File.read(path)
        # ERB#src raises on a template syntax error; reaching the next line means it compiled.
        ERB.new(raw, trim_mode: "-").src

        # Read-only: no action forms, no mutating routes referenced.
        refute_match(/method=["']post["']/i, raw, "Routing tab view must be read-only (no POST forms)")
        %w[routing/park routing/blackhole routing/unpark routing/sweep routing/process_parked].each do |route|
          refute_includes raw, route, "Routing tab view must not link the mutating route #{route}"
        end

        # Still renders state.
        assert_includes raw, "Active routes"
      end

      def test_web_extension_registers_no_mutating_routes
        source = File.read(WebExtension.method(:registered).source_location.first)
        refute_match(/app\.post/, source, "Routing tab must register no POST routes")
      end
    end
  end
end
