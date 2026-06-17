# frozen_string_literal: true

require "test_helper"

# Stand-in for sidekiq-unique-jobs' server middleware. `install!` only checks
# whether SidekiqUniqueJobs::Middleware::Server is defined and already in the
# chain (so routing's middleware can be inserted *after* it). A bare class
# exercises that ordering branch without pulling the whole gem into this gem's
# test dependencies; the real integration is verified in host apps.
module SidekiqUniqueJobs
  module Middleware
    class Server
      def call(_worker, _job, _queue) = yield
    end
  end
end

module Sidekiq
  module Routing
    class InstallTest < Minitest::Test
      def setup
        @client_config = Sidekiq::Config.new
        @server_config = Sidekiq::Config.new

        Sidekiq.stubs(:configure_client).yields(@client_config)
        Sidekiq.stubs(:configure_server).yields(@server_config)
      end

      def test_install_registers_client_middleware_on_client_configuration
        Routing.install!

        assert_equal [Middleware::Client], middleware_classes(@client_config.client_middleware)
      end

      def test_install_registers_client_and_server_middleware_on_server_configuration
        Routing.install!

        assert_equal [Middleware::Client], middleware_classes(@server_config.client_middleware)
        assert_equal [Middleware::Server], middleware_classes(@server_config.server_middleware)
      end

      def test_install_places_server_middleware_after_sidekiq_unique_jobs_when_present
        @server_config.server_middleware.add SidekiqUniqueJobs::Middleware::Server

        Routing.install!

        assert_equal [SidekiqUniqueJobs::Middleware::Server, Middleware::Server],
          middleware_classes(@server_config.server_middleware)
      end

      def test_install_is_idempotent
        Routing.install!
        Routing.install!

        assert_equal [Middleware::Client], middleware_classes(@client_config.client_middleware)
        assert_equal [Middleware::Client], middleware_classes(@server_config.client_middleware)
        assert_equal [Middleware::Server], middleware_classes(@server_config.server_middleware)
      end

      private

        def middleware_classes(chain)
          chain.entries.map(&:klass)
        end
    end
  end
end
