# Testing — Focus Areas

Generic baseline. `/agent-review:init` appends this repo's test conventions (runner, layout,
mocking idioms); keep both.

**Prefer pure-function unit tests**

- Business and domain logic should be extracted out of UI/handler code into plain functions and
  tested directly, rather than asserted through a rendered surface or an HTTP round trip
- Look for: new logic that is only reachable through a component or endpoint, with no seam to test

**Use the repo's existing test framework and idioms**

- Match the repo's test runner, assertion style, mocking helpers, and import conventions. Do not
  assume a framework, rendering harness, or helper library that the repo does not already depend on
- Look for: tests introducing a second runner or harness; imports of libraries absent from the
  manifest

**Mock at module/external boundaries**

- External services (databases, third-party APIs, mail, payments, LLMs) are mocked at the module
  boundary, not by patching global network primitives ad hoc
- Look for: real network or filesystem access in unit tests; mocks that drift from the real
  signature; over-mocking that leaves the logic under test unexercised

**Determinism**

- Time-dependent logic uses the runner's fake-timer/clock control rather than real system time.
  Random values are seeded or injected
- Look for: tests that depend on the current date, timezone, ordering of a map/set, or on another
  test having run first

**Coverage of the shape of the input**

- Every new test should exercise: empty, zero / one / many, boundary values, and at least one happy
  path
- Look for: tests that only assert the happy path; parameters whose invalid values are never tested

**Error paths**

- Validation rejections, rejected promises, timeouts, and the failure branches of domain functions
  are tested, not just success
- Look for: `catch` branches with no covering test

**Test placement and naming**

- Follow the repo's convention for where tests live and how they're named
- Test names describe the behavior asserted, not the function name alone

**Quality gates**

- The repo's test, type-check, lint, and format commands must all pass
- Look for: skipped or `.only` tests left behind; loosely-typed mocks that defeat type checking;
  assertions that can never fail (e.g. asserting on the mock's own return)

<!-- init: extend this file with repo-specific focus areas and evidence links -->

## Repo-specific: rails-infrastructure-canary

**Runner and layout**

- Minitest through Rails: `bundle exec rails test` (CI `test` job, `RAILS_ENV=test`, libvips installed first) or `bin/rails test` (`config/ci.rb`). Do not add RSpec, Capybara or selenium (commented out in the Gemfile); `test/application_system_test_case.rb` is generated and unused
- Layout mirrors `app/`: `test/controllers/`, `test/jobs/`, `test/channels/application_cable/`, plus placeholder dirs `test/models`, `test/mailers`, `test/helpers`, `test/integration`, `test/fixtures` (all `.keep`). Files end in `_test.rb`
- `test/test_helper.rb`: `require "rails/test_help"`, `parallelize(workers: :number_of_processors)`, `fixtures :all`. Tests must be safe to run in parallel

**Idioms**

- Controller tests: `class MainControllerTest < ActionController::TestCase` with `get :hello` and `assert_response :success` (`test/controllers/main_controller_test.rb`). Follow that style for controller tests; use `ActionDispatch::IntegrationTest` only for routing, middleware or host/SSL behavior that `ActionController::TestCase` cannot reach
- Job tests: `ActiveJob::TestCase` (`test/jobs/log_test_job_test.rb`, currently empty). Use `assert_enqueued_with` / `perform_enqueued_jobs`, not a live Sidekiq or Redis. Test env cache is `:null_store`; mail uses the `:test` delivery method
- No mocking library is in the Gemfile beyond Minitest itself; `minitest/mock` ships with minitest 5.x (the lockfile has 5.27.0) and is gone in minitest 6. A test that needs `Minitest::Mock` or `stub` is a flag if the lockfile moves to 6

**Where coverage is thin, and what a good test looks like here**

- The suite has one real test. The generated files `connection_test.rb` and `log_test_job_test.rb` are empty shells. A diff that changes the code below with no test is a finding:
  - `MonitorsController#lb`: assert 200 and the `OK` body (it reads `public/lb.txt`), and that the route path equals `BaseImageRubyTest::HEALTHCHECK_PATH`. This pins the hand-synced route against the single-source constant
  - `Log::Logger::Formatter` (`lib/log/logger/formatter.rb`): assert the JSON keys the Datadog pipeline depends on (`name`, `host`, `level`, `time`, `env`, `dd.trace_id`, `dd.span_id`, and `network.client.ip`, `amzn_trace_id`, `request_id` when a `request` is in the data), and that `:request` never appears in the output. `FormatterReadable` must also drop `:request`
  - `config/initializers/lograge.rb`: assert `ignore_actions` contains `BaseImageRubyTest::HEALTHCHECK_ACTION` and that logged params exclude `controller action format id`
  - `bin/bundler-audit`: the CLI/yml ignore merge logic has no test; a change to it needs one
- Configuration invariants are best tested at boot: the `test` job eager-loads (`config.eager_load = ENV["CI"].present?`), so a broken autoload or initializer shows up as a CI failure. Do not weaken that setting
- Because `.env` is committed with placeholders, tests may rely on those values (`TEST_SECRET=fake`). A test that needs a different secret sets it inside the test and restores it, rather than editing `.env`

**Determinism and isolation**

- Initializers gate on ENV (`AWS_EXECUTION_ENV == "AWS_ECS_EC2"` for Datadog and Sidekiq Pro dogstatsd; `.present?` for the JSON log formatter). Tests that exercise those branches must set and restore the variable (an `ensure` block), because one worker process runs many tests
- `config/initializers/datadog.rb` makes a live HTTP call to `169.254.169.254` under the ECS gate. A test must never trip that gate; CI does not set `AWS_EXECUTION_ENV`
- Tests must not need Redis, the network, or Datadog

**Quality gates**

- Before merge: `bundle exec rails test`, `bundle exec standardrb --format simple`, `bundle exec brakeman -A -q --no-pager` must pass (the required `test` and `lint` jobs). `bin/ci` runs all of them plus the audits locally
- Look for: new `test` blocks that assert nothing (`assert true`); commented-out test bodies added to empty shells

### Mined from PR history

- `.github/workflows/ruby.yml` runs on `pull_request` only for PRs into `master`, so a PR stacked on another branch gets no `test` or `lint` run. When the PR's base is not `master`, say that CI has not run on this change and must pass after the retarget, before it merges
  <!-- evidence: PR #141, #142 -->
