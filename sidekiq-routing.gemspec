# frozen_string_literal: true

require_relative "lib/sidekiq/routing/version"

Gem::Specification.new do |spec|
  spec.name = "sidekiq-routing"
  spec.version = Sidekiq::Routing::VERSION
  spec.authors = ["Vishnu M"]
  spec.email = ["vishnu.m@bigbinary.com"]

  spec.summary = "Runtime, per-job-class queue routing for Sidekiq: park, blackhole, " \
                 "and auto-reroute job classes without a deploy."
  spec.description = <<~DESC
    sidekiq-routing gives you runtime control over which Sidekiq queue a
    job class lands in or runs from — without a deploy. Park a misbehaving class
    onto a worker-less parking queue (reversible), blackhole it (drop), or let
    the optional auto-rerouter move noisy classes between latency tiers. Ships a
    read-only Sidekiq Web tab. Routing state lives in a single Redis hash read
    from a process-local snapshot, so the per-job hot path stays an in-memory
    lookup rather than a Redis round-trip.
  DESC
  spec.homepage = "https://github.com/neetozone/sidekiq-routing"
  spec.license = "MIT"

  spec.required_ruby_version = ">= 3.1"

  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir["lib/**/*", "README.md", "LICENSE"]
  spec.require_paths = ["lib"]

  spec.add_dependency "sidekiq", ">= 7.0"
end
