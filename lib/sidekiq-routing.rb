# frozen_string_literal: true

require "sidekiq/routing/version"

# Routing core: defines Sidekiq::Routing and the manual driver (operator
# park / blackhole overrides). Loaded first so Sidekiq::Routing exists before
# the Auto sub-namespace reopens it.
#
# The Web tab (sidekiq/routing/web) is intentionally NOT required here. Host
# apps require it at the Sidekiq::Web mount site so worker processes never load
# the web framework.
require "sidekiq/routing"
require "sidekiq/routing/configuration"
require "sidekiq/routing/store"
require "sidekiq/routing/mover"
require "sidekiq/routing/sweeper"
require "sidekiq/routing/parked_processor"
require "sidekiq/routing/middleware/client"
require "sidekiq/routing/middleware/server"

# Routing::Auto: the automatic driver — latency-driven movement of jobs between
# SLA tiers. Opt-in via SIDEKIQ_ROUTING_AUTO_REROUTE_ENABLED.
require "sidekiq/routing/auto/configuration"
require "sidekiq/routing/auto/job_duration_tracker"
require "sidekiq/routing/auto/noisy_neighbor_detector"
require "sidekiq/routing/auto/batch_rerouter"
require "sidekiq/routing/auto/router"
require "sidekiq/routing/auto/reroute_job"
