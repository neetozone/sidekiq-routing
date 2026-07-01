# sidekiq-routing

Runtime, per-job-class **queue routing for Sidekiq** — park, blackhole, or
auto-reroute a job class **without a deploy**.

Background jobs often share a handful of latency-tiered queues
(`within_5_seconds`, `within_1_minute`, …). The queue name is a contract: every
job on a tier should start within that window. That sharing is efficient until
one class misbehaves — a flood, a runaway argument, a broken downstream — and
then the only built-in lever, pausing the whole queue, punishes every other
class on the tier. `sidekiq-routing` gives you a finer lever, applied at
runtime to a single job class:

| Kind | Purpose | Driver | Target |
|---|---|---|---|
| **Manual routing** | Incident response for one misbehaving class. | Operator, from a console. | `park` (reversible) or `blackhole` (drop). |
| **Auto rerouting** | Capacity management when an SLA tier is overloaded. | Background job, latency-driven, opt-in. | The next live SLA tier. Never parks or blackholes. |

Both are per-job-class. To halt a *whole* queue, use Sidekiq's own pause button.

The hot path is cheap: routing state lives in a single Redis hash, read from a
process-local snapshot refreshed at most once per `cache_ttl_seconds`, so the
per-job cost is an in-memory lookup, not a Redis round-trip.

## Installation

```ruby
gem "sidekiq-routing"
```

```sh
bundle install
```

Requires Ruby >= 3.1 and Sidekiq >= 7.0 (tested on Sidekiq 7.3.x and 8.x). The
gem depends only on `sidekiq`.

## Quick start

Add an initializer (e.g. `config/initializers/sidekiq_routing.rb`):

```ruby
require "sidekiq-routing"

Sidekiq::Routing.setup do |config|
  # All optional — these are the defaults.
  # config.parked_queue = "routing_parked"
  # config.cache_ttl_seconds = 5
end

Sidekiq::Routing.install! # registers the client + server middleware
```

`install!` prepends the client middleware (so enqueues are diverted) and adds
the server middleware (so in-flight jobs are diverted).

Then, from a console during an incident:

```ruby
Sidekiq::Routing.park("FlakyReportJob")     # divert to the parking queue (reversible)
Sidekiq::Routing.blackhole("SpamWebhookJob") # drop its jobs entirely
Sidekiq::Routing.unpark("FlakyReportJob")    # remove the route
```

## Manual routing — incident response

One job class is misbehaving and you want to disable *just that class*, at
runtime, without pausing the rest of its queue or shipping a deploy.

- **Park** (reversible) — newly enqueued and in-flight jobs for the class are
  diverted to a worker-less parking queue (`routing_parked` by default) and
  held. The work is preserved; recover it later.
- **Blackhole** (irreversible) — the class's jobs are dropped entirely (never
  added to the Dead set). Only for classes you can afford to lose.

```ruby
Sidekiq::Routing.park("RunawayImportJob")
Sidekiq::Routing.blackhole("FireAndForgetJob")
Sidekiq::Routing.unpark("RunawayImportJob")

Sidekiq::Routing.routed?("RunawayImportJob")  # => true/false
Sidekiq::Routing.parked?("RunawayImportJob")  # => true only when in park mode
Sidekiq::Routing.mode("RunawayImportJob")     # => "park" | "blackhole" | nil
Sidekiq::Routing.routes              # => { "RunawayImportJob" => { "mode" => "park", ... } }
```

A route accepts a Class or a String. ActiveJob jobs are matched by their real
("wrapped") class, not the adapter's job wrapper.

### Identifying the class flooding a live queue

During a latency alert, inspect the breached queue with a capped, read-only scan:

```ruby
report = Sidekiq::Routing.queue_composition("within_1_minute")
puts report
# RunawayImportJob                                      count=12345     oldest=380s ago
# OtherJob                                             count=12        oldest=45s ago
# scanned 12357 of 12357 (cap 250000)

report.offender["class"] # => "RunawayImportJob"
```

### Clearing an existing backlog into the parking queue

`park` only diverts jobs from the moment it's set. To move a class's jobs that
are *already enqueued* on a live queue into the parking queue, sweep them:

```ruby
Sidekiq::Routing.sweep("RunawayImportJob", queue: "within_1_minute")
Sidekiq::Routing.sweep("RunawayImportJob", queue: "within_1_minute", limit: 10_000)
```

A queue must be resolvable — pass `queue:` explicitly (the sweep deliberately
never scans every queue, which would hammer Redis during an incident).

### Recovering parked work

```ruby
# Move parked jobs back to their original queue (stamps them so an active
# route won't immediately bounce them back).
Sidekiq::Routing.process_parked
Sidekiq::Routing.process_parked(klass: "RunawayImportJob", limit: 1_000)

# Introspection
Sidekiq::Routing.parked_size       # O(1) count of the parking queue
Sidekiq::Routing.parked_breakdown  # { "RunawayImportJob" => { "count" => 12, "by_original_queue" => {...} } }
```

A processed parked job has its payload rewritten to target its original queue,
so if it later fails it retries to that queue — not back to the parking queue.
Jobs with no stamped original queue go to `process_parked_fallback_queue`
(`"default"`).

## Auto rerouting — capacity management

Optionally, move *noisy-neighbor* job classes between SLA tiers automatically
when a tier is overloaded. It is **off unless you opt in**:

```sh
export SIDEKIQ_ROUTING_AUTO_REROUTE_ENABLED=true
```

Auto rerouting only ever moves jobs to the *next* live SLA tier
(`within_5_seconds` → `within_1_minute` → `within_5_minutes` → `within_1_hour`).
It never parks or blackholes.

Wire it up in your initializer:

```ruby
if Sidekiq::Routing::Auto.enabled?
  # 1. Track per-class job durations (server middleware).
  Sidekiq.configure_server do |config|
    config.server_middleware do |chain|
      chain.add Sidekiq::Routing::Auto::JobDurationTracker
    end
  end
end

Sidekiq::Routing::Auto.setup do |config|
  # config.capacity_threshold_percent = 80
  # config.sla_thresholds = { "within_5_seconds" => 5, "within_1_minute" => 60, ... }
end
```

Then schedule the driver periodically (e.g. every minute) with
[sidekiq-cron](https://github.com/sidekiq-cron/sidekiq-cron):

```yaml
# config/schedule.yml
routing_auto_reroute:
  cron: "* * * * *"
  class: "Sidekiq::Routing::Auto::RerouteJob"
```

`RerouteJob` checks each SLA queue's estimated workload against its capacity and,
for any tier over `capacity_threshold_percent`, moves the noisiest classes to
the next tier. `RerouteJob` itself is excluded from rerouting by default.

## Web tab

A read-only "Routing" tab for Sidekiq Web shows active routes and parking-queue
depth/breakdown. Every mutating action stays on the console API — the tab never
exposes park/blackhole/unpark/sweep, so destructive operations stay deliberate.

Require it only where you mount Sidekiq Web:

```ruby
require "sidekiq/web"
require "sidekiq/routing/web" # registers the "Routing" tab
mount Sidekiq::Web => "/sidekiq"
```

<img width="2964" height="1550" alt="CleanShot 2026-06-26 at 13 59 49@2x" src="https://github.com/user-attachments/assets/8da1149d-c76d-47d6-8be6-7aef921d54ea" />

## Configuration reference

`Sidekiq::Routing.setup { |config| ... }`:

| Option | Default | Purpose |
|---|---|---|
| `enabled` | `true` | Master switch for the routing middleware. |
| `parked_queue` | `"routing_parked"` | Worker-less queue parked jobs divert to. |
| `process_parked_fallback_queue` | `"default"` | Target when a parked job has no stamped original queue. |
| `cache_ttl_seconds` | `5` | Hot-path snapshot freshness. `0` reads Redis every call. |
| `batch_limit` | `nil` | Default cap on jobs moved per recovery call (`nil` = all). |
| `batch_size` | `100` | Jobs moved per pass. |
| `breakdown_sample_size` | `1_000` | Max jobs `parked_breakdown` scans. |
| `logger` | `Rails.logger` or `Sidekiq.logger` | — |

`Sidekiq::Routing::Auto.setup { |config| ... }`:

| Option | Default | Purpose |
|---|---|---|
| `enabled` | `SIDEKIQ_ROUTING_AUTO_REROUTE_ENABLED == "true"` | Opt-in switch. |
| `sla_thresholds` | the four `within_*` tiers | Queue → SLA seconds. |
| `capacity_threshold_percent` | `80` | Reroute a tier above this % capacity. |
| `noisy_neighbor_threshold_percent` | `50` | Share of workload that marks a class noisy. |
| `batch_reroute_limit` | `50` | Max jobs moved per reroute pass. |
| `duration_tracking_window` | `3600` | Seconds of duration history retained. |
| `excluded_job_classes` | `["Sidekiq::Routing::Auto::RerouteJob"]` | Never auto-rerouted. |

## How it works

Manual routes live in one Redis hash. The middleware reads a frozen,
process-local snapshot of that hash, refreshed at most once per
`cache_ttl_seconds`, so the per-job decision is an in-memory lookup. The
operator API (`park`/`blackhole`/`unpark`) writes through and resets the
snapshot, so console changes take effect immediately for the writer and within
one TTL everywhere else. Parking rewrites the `queue` field *inside the job
payload*, which is what makes recovery and retry-to-original-queue correct.

## License

Released under the [MIT License](LICENSE).
