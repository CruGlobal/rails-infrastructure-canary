# Architecture — Focus Areas

Generic baseline. `/agent-review:init` appends the repo-specific concerns; keep both.

**Layering & boundaries**

- Business logic lives in testable modules, not inline in entry points (route/page/controller/CLI
  handlers). Entry points compose and delegate
- Server-only code stays out of code paths that ship to a client or untrusted runtime
- Look for: domain math embedded in view code; a module reaching across layers it shouldn't know
  about; new circular dependencies

**Placement & structure**

- New files land where the existing convention says they belong; shared code goes to the shared
  location only when it is genuinely used by more than one feature
- Look for: one-off code dropped into a "shared"/"common"/"utils" bucket; parallel structures that
  duplicate an existing module instead of extending it; new top-level directories

**Pattern consistency**

- The change should look like the code around it. Deviating is fine when the existing pattern is
  what's being fixed — but then it should be fixed consistently, not forked
- Look for: a second way of doing something the codebase already does one way (data fetching, error
  handling, configuration, logging); framework features reimplemented by hand

**State & data flow**

- Cached/derived state has a clear owner, and writes invalidate or update what they affect
- Look for: the same state maintained in two places; refetching in an effect what a cache already
  owns; values threaded through three or more layers that would be better read closer to use

**Effects & lifecycle**

- Look for: effects whose dependency list omits referenced values (stale closures); work in an
  effect that belongs in an event handler or a derived value; subscriptions and timers without
  cleanup

**Concurrency & performance shape**

- Look for: sequential awaits on independent work that could run concurrently; N+1 query patterns;
  unbounded loops over remote calls; work done per-item that could be batched

**Error handling & resilience**

- Look for: swallowed errors (empty catch, error logged and ignored); failures that leave state
  half-written; missing error/loading boundaries on user-facing surfaces; retries without backoff or
  idempotency

**Technical debt**

- Weigh debt added against debt removed. A refactor that only moves code without improving clarity
  is neutral, not positive. When a convention is ambiguous, raise it as a question rather than a
  blocking finding

<!-- init: extend this file with repo-specific focus areas and evidence links -->

## Repo-specific: rails-infrastructure-canary

This app is the Cru Rails fleet's lab and reference app. It has no domain logic (no models beyond `ApplicationRecord`, one `MainController#hello`, one `MonitorsController#lb`, one `LogTestJob`). Almost every architectural question is about infrastructure shape, and every shape here gets copied to about 17 other apps. Judge a change twice: does it work in the canary, and is it safe to copy fleet-wide?

**Copyability is the main design constraint**

- A canary-only shortcut must not look like the recommended pattern. Examples: the committed `.env` with `TEST_SECRET=fake` and `SECRET_KEY_BASE=secret`, `config/database.yml` giving production no database path, `staging.rb` that only `require`s `production.rb`, `build-deploy-ecs.yml` building `staging` only. If a change adds one of these, it needs a comment saying it is canary-specific
- Where a pattern needs a per-app edit when copied (project name, secret names, health-check path in cru-terraform), the file must say so. `config/application.rb` does this for the health check; follow that style
- Look for: a new initializer or config that hardcodes this app's names (`BaseImageRubyTest`, `rails-canary-lab.aws.cru.org`, `base_image_ruby_test_production`) in a place the copying app will not think to rename; behavior that only works because the canary has no models, no auth, and no real traffic

**Single source of truth for cross-file constants**

- `BaseImageRubyTest::HEALTHCHECK_PATH` and `HEALTHCHECK_ACTION` (`config/application.rb`) feed `config/environments/production.rb` (`ssl_options`, `silence_healthcheck_path`), `config/initializers/lograge.rb` (`ignore_actions`) and `config/initializers/datadog.rb` (span filter). `config/routes.rb` (`get "monitors/lb"`) and the cru-terraform ALB path are deliberately hand-synced, per the comment in `application.rb`
- Look for: a new consumer that re-types `"/monitors/lb"` or `"MonitorsController#lb"` instead of reading the constant; a new place that must change on a health-check rename but is not added to that comment's list
- The same rule applies to Redis settings: `config/redis.yml` is the one config file. Today three files re-parse it with the same `YAML.safe_load(ERB.new(...).result, permitted_classes: [Symbol], aliases: true)` line (`config/application.rb`, `config/initializers/session_store.rb`, `config/initializers/sidekiq.rb`). A fourth copy is a pattern-consistency finding; prefer extracting one loader over adding one more. `config/cable.yml` is a known outlier (it reads `REDIS_URL`, not `redis.yml`)

**Boot order and layering**

- `config/application.rb` requires `lib/log/logger` before `Bundler.require`, because `config.logger = Log::Logger.new($stdout)` runs at class-body time. `lib/` is autoloaded via `config.autoload_lib(ignore: %w[assets tasks])`, but `Log::Logger` is loaded by explicit `require`. Moving logger setup, or adding another `lib/` class that `application.rb` needs at class-body time, must keep it loadable before the autoloader exists
- `config/initializers/lograge.rb` re-assigns `config.logger` (it is also set in `application.rb`). Two places set the logger; flag a third
- Environment files load after `application.rb`, so a `config.logger =` in `production.rb` would silently replace the Ougai logger (the comment in `production.rb` says so). Keep it commented out
- Environment detection is split: `config/initializers/datadog.rb` and `config/initializers/sidekiq.rb` gate on `ENV["AWS_EXECUTION_ENV"] === "AWS_ECS_EC2"`, while `Log::Logger#create_formatter` gates on `ENV["AWS_EXECUTION_ENV"].present?`. A new initializer should pick the gate that matches its job (ECS-EC2-only agent access vs. any AWS runtime) and not invent a third

**Placement**

- Jobs go in `app/jobs/` and inherit `ApplicationJob`. The queue adapter is set once, in `config/application.rb` (`config.active_job.queue_adapter = :sidekiq`). Sidekiq Pro features (`super_fetch!`, `reliable_scheduler!`, `reliable_push!`) belong in `config/initializers/sidekiq.rb` only
- Observability code (formatters, correlation) belongs under `lib/log/`; Datadog tracer config belongs in `config/initializers/datadog.rb`. Request-scoped log fields enter through lograge's `custom_payload` (`request: controller.request`) and are unpacked by `Log::Logger::Formatter`. Do not add a second path (middleware, `Current` attributes) for the same fields
- Container concerns stay in `Dockerfile`, `build.sh`, `bin/docker-entrypoint`, `bin/thrust`. App code must not assume the container fronting (Thruster on port 80, Puma on 3000)

**Resilience at boot**

- Look for: new network calls in initializers with no timeout or rescue (`datadog.rb` already does an unbounded `Net::HTTP.get` against the EC2 metadata endpoint; do not copy that shape for new calls); new required `ENV.fetch` keys in `config/redis.yml`, which make every environment (including CI) fail to boot when the key is missing
- Look for: a startup step that mutates shared state (migrations, cache warmup) in a path that runs on every container start without being idempotent
