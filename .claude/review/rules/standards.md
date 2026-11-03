# Standards — Checklist

Generic baseline. Every item here is mandatory unless the repo's own conventions override it —
`/agent-review:init` appends the repo-specific checklist, and both layers are kept.

This is an explicit checklist: report compliance for each **bold group below** in the
`### Rule Checklist Results` section of your output (✅ / ⚠️ / ❌ / N/A), and raise anything
non-compliant as a finding at the severity its impact warrants.

**Exports & Naming**

- [ ] Export style matches the repo's convention (named vs default) — don't introduce a second style
- [ ] File and directory naming follows the existing convention (casing, suffixes, special filenames
      the framework requires)
- [ ] Public identifiers are descriptive; abbreviations match ones already used in the codebase
- [ ] Imports use the repo's alias/path convention rather than deep relative traversal

**Types**

- [ ] No escape hatches that disable type checking in new code (untyped `any`-equivalents, suppression
      comments) without an inline comment explaining why
- [ ] No non-null/force-unwrap assertions on values that can legitimately be absent — check explicitly
- [ ] Types are derived from a single source of truth rather than hand-duplicated alongside it

**Input & Forms**

- [ ] User input is validated with the repo's established validation approach, not ad-hoc checks
- [ ] Every client-side validation rule has a server-side counterpart
- [ ] Submit/confirm actions are disabled or guarded while in flight so they can't double-fire

**Data**

- [ ] Writes invalidate or update the cached data they affect
- [ ] Cache/query keys are stable, descriptive, and scoped to the resource and its inputs
- [ ] Queries rely on the real authorization boundary, not on a client-side filter

**Dates & Numbers**

- [ ] Date math uses the repo's chosen date library and format conventions, not ad-hoc arithmetic
- [ ] Numeric formatting and rounding happen at the display boundary, consistently

**Testing**

- [ ] Every new function, hook, and non-trivial component has a test in the repo's conventional
      location
- [ ] Tests use the repo's runner and mocking idioms
- [ ] Test code is typed as strictly as production code

**Code Quality**

- [ ] Lint, type-check, and format commands pass
- [ ] No debug output left behind (console/print statements, debuggers, `TODO` without a tracked issue
      reference)
- [ ] No unused imports, variables, or dead parameters
- [ ] No commented-out code blocks (delete, don't comment)
- [ ] No empty catch blocks that swallow errors silently
- [ ] Package-manager usage matches the repo's lockfile (don't mix tools)

<!-- init: extend this file with repo-specific focus areas and evidence links -->

## Repo-specific: rails-infrastructure-canary

Evidence: `Gemfile`, `.github/workflows/ruby.yml`, `config/ci.rb`, `bin/*`, `test/`. The generic checklist above is written for a typed frontend; map it as below. Items about TypeScript, forms and client validation are N/A here. Report each bold group below in the Rule Checklist Results too.

**Override of the generic checklist**

- [ ] Rails generator default lines the app does not use (gems such as `bcrypt`, `solid_cache`, `kamal`, `image_processing`, `rubocop-rails-omakase`, `capybara`; skeleton config lines) stay commented out rather than deleted, so the next skeleton diff stays small. This replaces the generic "No commented-out code blocks" item for generator output only; hand-written code still follows it

**Ruby style: StandardRB, not RuboCop omakase**

- [ ] Lint is `standard` (Gemfile, default group). `rubocop-rails-omakase` is commented out in the Gemfile and must stay that way; no `.rubocop.yml` and no `.standard.yml` exist, so StandardRB defaults apply. Do not add either config file without a reason in the PR
- [ ] Double-quoted strings; hashes written `{key: value}` with no inner spaces (`{msg: "Request"}`, `{redirect: {exclude: ...}}`); `%i[]`/`%w[]` for symbol/word arrays; no trailing whitespace
- [ ] Gems in the Gemfile: alphabetical order is kept inside the trailing app block (`amazing_print`, `datadog`, `dogstatsd-ruby`, `dotenv-rails`, `lograge`, `ougai`, `rake`, `redis-actionpack`, `sidekiq`, `standard`); tool gems that should not ship go in `group :development, :test`
- [ ] Commands that must pass, quoted exactly from CI (`.github/workflows/ruby.yml`): `bundle exec rails test`; `bundle exec brakeman -A -q --no-pager`; `bundle exec standardrb --format simple`; `bin/bundler-audit check --update` (audit job, not required); `bin/importmap audit`
- [ ] `config/ci.rb` (run via `bin/ci`) runs: `bin/setup --skip-server`, `bundle exec standardrb --format simple`, `bin/bundler-audit check --update`, `bin/importmap audit`, `bin/brakeman --no-pager`, `bin/rails test`. A new check goes in both `ruby.yml` and `config/ci.rb`
- [ ] `bin/brakeman` prepends `-A -q`; a brakeman flag change updates `bin/brakeman` and the `lint` job together

**Naming and layout**

- [ ] The app namespace is `BaseImageRubyTest` (`config/application.rb`), a legacy name kept on purpose; do not introduce a second module name or `RailsCanary` constants (`RailsCanary` appears only as the layout `<title>` fallback). Shared constants live on that module (`HEALTHCHECK_PATH`, `HEALTHCHECK_ACTION`)
- [ ] Classes are one per file under Rails autoload naming: `app/jobs/log_test_job.rb` -> `LogTestJob`, `app/controllers/monitors_controller.rb` -> `MonitorsController`. Observability classes are `Log::Logger`, `Log::Logger::Formatter`, `Log::Logger::FormatterReadable` under `lib/log/logger*.rb`; nested files reopen `class Logger < Ougai::Logger` with the same superclass
- [ ] Config via ENV uses the existing keys: `PROJECT_NAME`, `ENVIRONMENT`, `AWS_EXECUTION_ENV`, `STORAGE_REDIS_{HOST,PORT,DB_INDEX}`, `SESSION_REDIS_{HOST,PORT,DB_INDEX}`, `RAILS_LOG_LEVEL`, `LOG_REQUESTS`. Read with `ENV.fetch` when required (see `config/redis.yml`)
- [ ] Environment differences between prod and stage go in ENV vars, not in `config/environments/staging.rb`, which only requires `production.rb`
- [ ] Custom (non-generated) settings in env files sit under the `# --- Custom (app-specific) configuration ---` header, as in `development.rb` and `production.rb`
- [ ] Reusable workflow refs are released tags (`@v1`, `@v2`); first-party actions follow what `ruby.yml` already uses (`actions/checkout@v7`, `ruby/setup-ruby@v1`)
- [ ] Dependabot commit prefixes stay `ci(deps)` for actions and `fix(deps)` for gems (`.github/dependabot.yml`)

**Comments**

- [ ] A comment states a constraint the code cannot express (the `ruby-vips` boot-guard floor, the Dockerfile `LOG_REQUESTS` note, the health-check source-of-truth list). Pins and workarounds say why and when they can go, because the next fleet app copies the file. Prefer stating the invariant over narrating the incident that produced it
- [ ] No new debug leftovers: `amazing_print` and `debug` are loaded for development; no `puts`/`pp`/`binding.break` in `app/`, `lib/`, `config/`

**Tests (Minitest under `test/`)**

- [ ] Runner is Minitest via `bundle exec rails test`; no RSpec, no Capybara/selenium (commented out in the Gemfile; `test/application_system_test_case.rb` is generated and unused)
- [ ] Tests mirror the app tree: `test/controllers/<name>_controller_test.rb`, `test/jobs/<name>_job_test.rb`, `test/channels/...`, plus `test/integration/`, `test/models/`, `test/mailers/`, `test/helpers/` (placeholders `.keep`)
- [ ] Controller tests follow `test/controllers/main_controller_test.rb`: `require "test_helper"`, `class XControllerTest < ActionController::TestCase`, `test "should get hello" do get :hello; assert_response :success end`. Job tests use `ActiveJob::TestCase`. New code with real behavior (for example `MonitorsController#lb`, `Log::Logger::Formatter`) gets a test, not another empty generated file
- [ ] `test/test_helper.rb` keeps `parallelize(workers: :number_of_processors)` and `fixtures :all`; tests must be parallel-safe
- [ ] Test names are lowercase behavior sentences (`test "should get hello"`)

**Dependencies and package tooling**

- [ ] Bundler only (`Gemfile`/`Gemfile.lock`); there is no `package.json` and no Node. JS goes through importmap (`config/importmap.rb`, `bin/importmap`); do not add npm/yarn/webpack (`config/webpacker.yml` is unused legacy)
- [ ] `Gemfile.lock` changes come from `bundle` with the pinned `BUNDLED WITH` version (2.7.2; the Dockerfile installs exactly that version); keep platforms `ruby` and `x86_64-linux-musl`

### Mined from PR history

- Values mirrored across files change together: brakeman flags in `bin/brakeman` and the `lint` job; checks in `.github/workflows/ruby.yml` and `config/ci.rb`; the health-check path through `BaseImageRubyTest::HEALTHCHECK_PATH`/`HEALTHCHECK_ACTION`. A diff that edits one copy only is a finding
  <!-- evidence: PR #137, #163, #164 -->
- Flag comments, binstubs and config that this diff leaves describing tooling the repo does not use: a `bin/rubocop` left behind while RuboCop is commented out, a `solid_queue` plugin line in a Sidekiq app, a PR-body or comment section that no longer matches the final commits
  <!-- evidence: PR #140, #163, #164 -->
- Keep Rails generator default lines commented out instead of deleting them (see the override at the top of this section)
  <!-- evidence: PR #102, #106 -->
- AI: in AI-assisted upgrade or skeleton-sync PRs, compare the deleted and regenerated files against the scope the PR states. An unmentioned deletion (an earlier #140 commit removed `app/channels/application_cable/*.rb` and its test) or a dropped comment or pin that the PR says it keeps is a finding. Failure mode: bulk regeneration sprawling past the stated scope
  <!-- evidence: PR #140, #164 -->
