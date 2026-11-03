# Data Integrity — Focus Areas

Generic baseline. This is where domain-specific data invariants belong once `/agent-review:init`
appends them; keep both.

**Access scoping at the data layer**

- Every query and mutation is scoped to the authenticated user/tenant/household. New tables,
  columns, or collections need matching access policies
- Look for: policy changes that widen a `where`/`using`/`with check` clause; queries filtered only
  in application code where a shared or admin connection bypasses the policy

**Validation at external boundaries**

- Payloads from HTTP requests, webhooks, queues, and third-party APIs are parsed against an explicit
  schema before use
- Look for: external JSON consumed without validation; fields read off an untyped/`any` value; types
  that have drifted from the actual storage shape

**Cache correctness**

- Every write that changes displayed data invalidates or updates the cache entry that serves it
- Look for: mutations with no invalidation; cache keys that omit an input which changes the result
  (filter, tenant/account id, date range), which serves stale or cross-scope data; optimistic
  updates that don't match the server's response shape or don't roll back on error

**Idempotency & retries**

- Sync jobs, webhook handlers, and queue consumers must not double-apply work on retry or replay
- Look for: blind inserts where an upsert on a stable external id is needed; no dedupe key; partial
  writes with no transaction or compensating action

**Numeric precision**

- Values where exactness matters (money, quantities, percentages) must not accumulate floating-point
  drift; round at the display boundary, never mid-calculation
- Look for: repeated rounding inside a pipeline; mixing units or currencies without conversion;
  aggregate totals recomputed differently in two places

**Date & time handling**

- Look for: non-deterministic "now" inside calculations (makes behavior untestable and
  timezone-fragile); naive local-time arithmetic across DST; inconsistent serialization formats
  across boundaries

**Null, undefined, and partial writes**

- An omitted field, an explicit null, and an empty string are three different writes. Be intentional
- Look for: whole objects spread into an insert/update without an explicit field allowlist; defaults
  applied in one code path but not another

**Aggregation over partial data**

- Look for: totals summed client-side over a paginated or filtered subset, silently ignoring rows
  beyond the page — prefer a server-computed aggregate

<!-- init: extend this file with repo-specific focus areas and evidence links -->

## Repo-specific: rails-infrastructure-canary

There is no relational data to protect: SQLite (`config/database.yml`), an empty `db/schema.rb`, no migrations, only `ApplicationRecord`. The data surface here is Redis (cache, sessions, Sidekiq), Sidekiq Pro job reliability, and boot-time database preparation. The generic access-scoping, numeric and date items are mostly N/A until a model exists.

**Redis config single source: `config/redis.yml`**

- Sections `sidekiq`, `session` (anchor `&SESSION`) and `cache` (inherits `*SESSION`) read `STORAGE_REDIS_{HOST,PORT,DB_INDEX}` and `SESSION_REDIS_{HOST,PORT,DB_INDEX}`. Host and DB index use `ENV.fetch` with no default, so a missing key aborts boot in every environment including CI (`.env` supplies placeholders). Look for: a new key without a `.env` placeholder; changed anchors that make cache silently share the session DB; a new Redis consumer that reads its own ENV instead of this file
- Three files parse the YAML with the same `YAML.safe_load(ERB.new(...).result, permitted_classes: [Symbol], aliases: true)`: `config/application.rb` (cache), `config/initializers/session_store.rb`, `config/initializers/sidekiq.rb`. Keep `permitted_classes: [Symbol]` and `aliases: true`; the keys are symbols and the file uses anchors
- Cache wiring in `config/application.rb` builds `redis_conf[:url] = "redis://" + host + "/" + db` (the port is not in the URL) and sets `max_key_size = 1024`. That pin keeps cache keys stable across the Rails 8.1 default change; dropping it changes every key on a rolling deploy. Look for changes that drop the port or DB from the URL, remove the `max_key_size` pin, or add cache keys that can exceed 1024 bytes
- Test env uses `:null_store` and development `:memory_store`, so cache behavior is only exercised in deployed environments. Look for a change that depends on cache semantics with no test
- `config/cable.yml` production adapter reads `REDIS_URL` (default `redis://localhost:6379/1`), not `redis.yml`. Any real Action Cable use here would hit a different Redis than the rest; flag it if channels are added

**Sessions**

- `config/initializers/session_store.rb` uses `redis-actionpack` `:redis_store` with `expire_after: 2.days`, and `redis.yml` repeats the expiry under `:expires_in`. Look for the two diverging, and for session payloads that grow (large objects stored in session)

**Sidekiq and Sidekiq Pro reliability (`config/initializers/sidekiq.rb`)**

- Client: `Sidekiq::Client.reliable_push!` (guarded by `method_defined?`). Server: `config.super_fetch!` and `config.reliable_scheduler!`. Redis settings built from `Redis.new(redis_conf).id`. `Sidekiq.default_job_options = {backtrace: true}`
- Reliability features give at-least-once delivery. super_fetch can re-run a job after a crash, and `reliable_push!` can enqueue duplicates if the push is retried. Every job (`app/jobs/*`, subclass of `ApplicationJob`) must therefore be idempotent. `LogTestJob` is trivially safe; a new job that writes, sends mail or calls an external API needs a dedupe key, upsert, or an explicit comment on why a re-run is harmless
- Look for: removal of `super_fetch!`/`reliable_scheduler!`/`reliable_push!` (silent loss of in-flight jobs); `retry: false` or `discard_on` added without thought for lost work; `retry_on` with no backoff or attempt cap; job arguments that are full objects instead of ids/primitives (ActiveJob serializes via GlobalID; `*args` in `perform` hides the contract); `backtrace: true` stored with very large errors
- `Sidekiq::Pro.dogstatsd` is set only when `AWS_EXECUTION_ENV == "AWS_ECS_EC2"` (socket `/var/run/datadog/dsd.socket`); a metrics change must keep that gate

**Database at boot**

- `bin/docker-entrypoint` calls `./bin/rails db:prepare` when the last two arguments are `./bin/rails server`, but the Dockerfile sets no `ENTRYPOINT`, so it runs only if the ECS task definition sets one. `db:prepare` is idempotent, and with SQLite on local container disk any data is lost on redeploy (the `production` block of `database.yml` has no path, with a comment about persistent volumes). Look for: a migration or seed added that assumes data persists or assumes the entrypoint runs; the argument check changing; a new model with no persistence plan
- `db/schema.rb` is empty and marked `linguist-generated`. Adding the first migration changes boot behavior (`dump_schema_after_migration = false` in production) and needs the boot path, the test DB (`storage/test.sqlite3`) and CI checked
- Parallel tests (`parallelize(workers: :number_of_processors)` with `fixtures :all`) create per-worker SQLite databases. Look for tests that write files or Redis keys outside the test DB without per-worker isolation (test cache is `:null_store`, but a real Redis call in a test is shared)

**Input and request data**

- Request params flow into logs via lograge. See `filter_parameter_logging.rb`. There is no form or API input today; new endpoints need strong params and explicit field allowlists (no whole-hash `params` into any write)
