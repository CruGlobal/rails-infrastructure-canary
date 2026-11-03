# Runtime & Dependency Infrastructure: Focus Areas

Repo-specific specialist lane (not one of the six core agents). It covers how the app is built, booted, deployed, kept patched, and observed. rails-infrastructure-canary is the Cru Rails fleet's reference app: infrastructure changes are proven here, then copied to about 17 apps. Judge each change twice: does it work in the canary, and is it safe to copy fleet-wide (no canary-only shortcut shown as the pattern)?

**Container image, boot and deploy path**

- Files: `Dockerfile` (ruby alpine from public.ecr.aws, `RUBY_VERSION` build arg), `build.sh`, `bin/docker-entrypoint`, `bin/thrust`, `.dockerignore`
- `build.sh` derives `RUBY_VERSION` from `.ruby-version` and passes `SIDEKIQ_CREDS`. The base image tag, `.ruby-version` and the Gemfile's `ruby file: ".ruby-version"` must move together; nothing else may hardcode a Ruby version
- Runtime stays non-root (`USER webapp`), jemalloc via `ENV LD_PRELOAD`, `vips` apk installed. Look for: `apk` removals of `vips` or `jemalloc`; `USER` moved above the `chown`; assets or bootsnap steps reordered so the `chown` stores a second copy of the cache
- `CMD ["./bin/thrust", "./bin/rails", "server"]` and `EXPOSE 80`: Thruster listens on 80 and proxies to Puma on 3000 (`port ENV.fetch("PORT", 3000)` in `config/puma.rb`). Changing either port, or `RAILS_MAX_THREADS` semantics, needs the cru-terraform side checked
- `ENV LOG_REQUESTS="false"` must stay. Thruster's request log is a Go slog JSON stream that would interleave with the Ougai/lograge stream, which the Datadog log pipeline is keyed on, and it would re-log the silenced health check
- `bin/docker-entrypoint` runs `db:prepare` when the last two args are `./bin/rails server`, but the Dockerfile sets no `ENTRYPOINT`, so the script runs only if the ECS task definition sets one. Look for a change that assumes the entrypoint runs, or that edits the arg matching without checking it against the real CMD
- `.dockerignore` deliberately does NOT ignore `.env` (the committed `.env` supplies `SECRET_KEY_BASE`/`RAILS_ENV` to `assets:precompile`). Look for anything that adds a real value to `.env`, or removes the comment explaining the divergence
- The contribsys credential flows through `ARG SIDEKIQ_CREDS` into `bundle config --global`. Look for a new ARG/ENV that carries a secret into a layer, or a `bundle config` written after `COPY . .`

**Gemfile pins, floors and boot guards**

- Every pin or floor needs a comment saying why and when it can be removed. Current pins: `puma "= 7.2.1"` (exact, no comment today), `ruby-vips ">= 2.2.1"` (commented), `sidekiq "~> 7.3"`, `ougai "~> 1.7"`, `dogstatsd-ruby "~> 5.3"`, `rails "~> 8.1.4"`
- A Rails security bump must ship together with any gem its boot guard needs. Rails 8.0.5.1+ refuses to boot unless ruby-vips >= 2.2.1 AND system libvips >= 8.13 (CVE-2026-66066). Look for a Rails/activestorage bump that lowers or drops the `ruby-vips` floor, or a lockfile regeneration that moves `ruby-vips` backward
- Look for: `Gemfile.lock` changes with no matching `Gemfile` reason (transitive major floats, for example minitest 6, which drops `minitest/mock`); `BUNDLED WITH` changing (the Dockerfile installs that exact bundler version via `awk`); the `PLATFORMS` list losing `x86_64-linux-musl` (the alpine image) or gaining one without need
- Private source: the `source "https://gems.contribsys.com/"` block for `sidekiq-pro` stays scoped to that block

**Rails and framework upgrades**

- `config.load_defaults 8.1` in `config/application.rb`. A version bump should not flip `load_defaults` and framework defaults in the same PR unless the PR is the upgrade itself. Look for new `config.*` overrides that exist only to silence a new default
- Deprecations are surfaced in production/staging via `config.active_support.deprecation = :notify` (`config/environments/production.rb`) plus `config/initializers/deprecation_notifications.rb` (logs each distinct message once per process through `Rails.logger.warn`). Look for: `config.active_support.report_deprecations = false` (commented out today, keep it so); the subscriber's dedupe key or log shape changing; a deprecation fixed by deleting the subscriber
- The test env prints deprecations to stderr (`:stderr`) and eager-loads when `CI` is set (`config.eager_load = ENV["CI"].present?`). Keep both, they are how upgrade breakage shows in CI

**CI parity**

- `.github/workflows/ruby.yml` jobs: `test` (`bundle exec rails test`), `lint` (`bundle exec brakeman -A -q --no-pager`, `bundle exec standardrb --format simple`), `audit` (not a required check: `bin/bundler-audit check --update`, `bin/importmap audit`). The master ruleset requires `test` and `lint`
- Any job that boots Rails (runs `bin/rails`, `rake`, loads `config/environment`) needs the `Install libvips` step (`sudo apt-get update && sudo apt-get install -y libvips`). Without it the Rails boot guard trips on the missing system library and hides the gem version actually under test. `lint` boots no app, so it has none; adding a Rails-booting step there needs the install
- `bin/brakeman` prepends `-A -q`; the lint job spells the same flags. Keep both in sync (the comment in `bin/brakeman` says so). `config/ci.rb` calls `bin/brakeman --no-pager` and `bin/bundler-audit check --update`, so a flag change goes in all three places
- `bin/bundler-audit` merges CLI `--ignore` values with the `ignore:` list in `config/bundler-audit.yml` (today `ignore: []`). Look for: ignore entries without a reason; edits that make CLI ignores replace instead of merge; `vars.CVE_IGNORES` handling changing in `ruby.yml`
- `--ensure-latest` was deliberately dropped from brakeman (no proposer under security-only). Do not re-add
- `concurrency.group` uses `github.head_ref || github.run_id` so push runs never cancel each other. Keep it

**Reusable workflow refs and workflow permissions**

- House style: `CruGlobal/.github/...` reusable workflows and actions are pinned to released tags (`build-ecs.yml@v1`, `actions/trigger-deploy@v1`, `dependabot-auto-merge-security-patch.yml@v2`), never a branch, and the comment on the v2 ref explains that it rides patch releases. Look for a new ref pinned to a branch or an unreleased SHA. Known exception: `.github/workflows/agent-review-approve.yml` keeps the agent-review template's `CruGlobal/agent-review/...@main` ref
- `dependabot-auto-merge.yml` holds `contents: write` and `pull-requests: write`, and passes `AUTOMERGE_APP_ID`/`AUTOMERGE_APP_PRIVATE_KEY`. Look for broader permissions or extra secrets
- `build-deploy-ecs.yml` builds only `staging` (`master` is commented out on purpose: the canary has no production infrastructure). A fleet app copying this file needs `master` enabled; keep the comment explaining why it is off here

**Dependency-update automation**

- `.github/dependabot.yml`: github-actions daily (limit 10, prefix `ci(deps)`); bundler is security-only via `open-pull-requests-limit: 0`, the `security-patches` group (patch only, `applies-to: security-updates`), `contribsys` registry, prefix `fix(deps)`
- Invariants: do not set `target-branch` on the bundler entry (security updates only follow the entry's settings when none is set); keep the `contribsys` registry on the bundler entry with its org-level token; do not raise the PR limit above 0 for gems
- `.github/renovate.json` extends `local>CruGlobal/groundcru` and sets `automerge` for patch updates. Look for any change that makes Renovate and Dependabot both open routine gem bumps, or widens automerge beyond patch

**Observability invariants the fleet copies**

- The Datadog pipeline is keyed on the JSON shape built in `lib/log/logger/formatter.rb`: top-level `name`, `host`, `level`, `time`, `env`, `"dd.trace_id"`, `"dd.span_id"`, plus `network.client.ip`, `amzn_trace_id`, `request_id` unpacked from the lograge `request` payload. Renaming or nesting a key is a breaking change for every fleet app that copies it
- `config/initializers/lograge.rb` passes the whole `request` through `custom_payload`; both formatters must `data.delete(:request)` so the request object is never serialized. Logged params are `event.payload[:params]` minus `controller action format id`, and rely on `config/initializers/filter_parameter_logging.rb` to be filtered first
- The health check is single-sourced in `BaseImageRubyTest::HEALTHCHECK_PATH`/`HEALTHCHECK_ACTION` (`config/application.rb`); production.rb (`ssl_options`, `silence_healthcheck_path`), lograge `ignore_actions` and the Datadog `SpanFilter` read it. `config/routes.rb` and cru-terraform's ALB path are hand-synced. Look for a re-typed `"/monitors/lb"`
- `config/initializers/datadog.rb` only configures when `AWS_EXECUTION_ENV == "AWS_ECS_EC2"` and reads the agent host from the EC2 metadata endpoint. Service/env come from `PROJECT_NAME`/`ENVIRONMENT` (`production` -> `prod`, `staging` -> `stage`). Sidekiq Pro dogstatsd uses the socket `/var/run/datadog/dsd.socket` under the same gate

**Checklist**

- [ ] Every new or changed pin or floor in `Gemfile` has a why-and-when-to-remove comment
- [ ] A Rails bump keeps `ruby-vips >= 2.2.1` and the CI libvips step in every Rails-booting job
- [ ] `bin/brakeman`, the `ruby.yml` lint job and `config/ci.rb` agree on brakeman flags
- [ ] Reusable workflow refs are released tags
- [ ] The `dependabot.yml` bundler entry still has no `target-branch`, limit 0, contribsys registry
- [ ] Log JSON keys and `LOG_REQUESTS="false"` unchanged, or the change is called out as fleet-breaking
- [ ] The health-check path is referenced only through the constants (plus the two documented hand-synced spots)

### Mined from PR history

- A Rails or activestorage bump keeps `gem "ruby-vips", ">= 2.2.1"` in the same PR, and every place that boots Rails or compiles native gems has the system packages it needs: the `Install libvips` step in each `ruby.yml` job that boots Rails, `vips` in the Dockerfile runtime `apk add`, and build deps (`build-base sqlite-dev yaml-dev`) for any new or bumped native gem. Flag a bump that changes one side only
  <!-- evidence: PR #98, #100, #104, #105, #106, #140, #145, #160, #164 -->
- Every new or changed pin, floor or exact version in `Gemfile` (including a deliberate below-floor or vulnerable fixture or demo pin) has an adjacent comment naming the constraint and the condition for removing it. A PR that meets that condition (for example, it moves past the Rails version a pin was for) removes the pin in the same PR
  <!-- evidence: PR #104, #105, #106, #129, #139, #145, #160, #164, #165 -->
- A security bump is a conservative, lock-only update: the `Gemfile.lock` diff moves only the named gem and what it requires, with no loosened `Gemfile` constraint, no unrelated gem churn, and no hand-written extra commits riding along. An Actions bump touches only the `uses:` ref. Flag any other gem whose version moved
  <!-- evidence: PR #81, #82, #87, #90, #91, #93, #111, #122, #129, #130, #133, #134, #136, #159, #160, #161, #162, #166 -->
- A Ruby, Rails or Sidekiq upgrade carries its whole fallout in the same PR: `config.load_defaults` and any `new_framework_defaults_*` file, initializer APIs the new version removed (Sidekiq 7 dropped the redis `namespace` option; `default_worker_options` became `default_job_options`), and the deprecation fixes it surfaces. When the PR applies `rails app:update` output, check that fleet-specific settings survived (the `filter_parameter_logging.rb` list, the `ssl_options` health-check exclude, development `config.hosts` and `web_console.permissions`, the `max_key_size = 1024` cache pin) and that every remaining divergence from the target skeleton is deliberate
  <!-- evidence: PR #84, #106, #108, #109, #110, #140, #141, #164 -->
- Runtime settings must take effect in the installed versions and the alpine base image: `ENV`, not `RUN export`, for runtime variables such as `LD_PRELOAD`; `EXPOSE`, Thruster's port, Puma's `PORT` and `USER` agree; `LOG_REQUESTS=false` stays; and `config/initializers/datadog.rb` uses only options the installed `datadog` 2.x gem reads (1.x options such as `controller_service` or `cache_service` on `instrument :rails` are silently ignored), behind the ECS-only gate
  <!-- evidence: PR #86, #106, #110, #142, #164, #165 -->
- AI: when an AI-assisted change removes a setting because "the new library doesn't need it", or keeps one the new version changed, check the claim against the version in `Gemfile.lock`. Failure mode: assumed API surface without reading the installed gem (#141 dropped `config.assets.quiet` though Propshaft supports it; #164 left out the `max_key_size` pin that the 8.1 default change made necessary, until review caught it)
  <!-- evidence: PR #141, #164 -->
