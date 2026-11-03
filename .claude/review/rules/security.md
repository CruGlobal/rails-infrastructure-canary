# Security — Focus Areas

Generic baseline. `/agent-review:init` appends the repo-specific concerns; keep both.

**Authentication & authorization boundaries**

- Every server endpoint, background job, and privileged action independently verifies the caller's
  identity — never trusts a user id, tenant id, or role passed in from the client
- Authorization is enforced at the data layer (row/tenant scoping, ACL check), not only by hiding UI
- Look for: endpoints added without a session/permission check; ownership checks that compare
  against client-supplied identifiers; policy changes that widen who can read or write a record

**Privileged clients & credentials**

- Admin/service-level clients that bypass normal access control must stay server-only and must never
  be importable from browser or otherwise untrusted code
- Look for: privileged clients imported into client-side modules; secrets read in code that ships to
  the browser; credentials committed to the repo or baked into build artifacts

**Secrets exposure**

- Server-only environment variables must not be exposed through client-visible prefixes, build-time
  inlining, or error payloads
- Look for: new environment-variable references; API keys or tokens in logs, error messages, HTTP
  responses, or analytics events

**Input validation & injection**

- Untrusted input (request bodies, query params, headers, webhooks, third-party payloads, file
  uploads) is validated against an explicit schema before use
- Look for: raw string interpolation into SQL/shell/HTML/templates; parsers fed unvalidated JSON;
  client-side validation with no server-side counterpart; unbounded sizes and counts

**Cross-site and browser-surface risks**

- Look for: raw-HTML injection sinks; unsanitized user content rendered as markup; open redirects
  where a redirect target comes from a query parameter without an allowlist check; missing CSRF
  protection on state-changing requests; weakened CSP or security headers

**Session & cookie handling**

- Look for: session cookies missing `HttpOnly`/`Secure`/`SameSite`; tokens stored where scripts can
  read them; sessions that are not invalidated on logout, password change, or privilege change;
  long-lived or non-rotating credentials

**Webhooks & third-party integrations**

- Look for: webhook handlers that parse and act on a payload before verifying the signature against
  the raw body; missing replay protection; secrets or tokens forwarded to the client

**Supply chain & CI**

- Look for: new dependencies (who maintains them, what they pull in); CI workflow changes that widen
  permission scopes, echo secrets, or let untrusted contributors trigger privileged jobs; changes to
  the review configuration itself that weaken risk scoring or strip checks

<!-- init: extend this file with repo-specific focus areas and evidence links -->

## Repo-specific: rails-infrastructure-canary

This app has no users or authentication, but it deploys to real AWS environments and its configuration is copied fleet-wide. Treat anything that leaks a secret or opens an admin surface as a blocker even though the app is "only a canary".

**Unauthenticated admin surface**

- `config/routes.rb` mounts `Sidekiq::Web => "/sidekiq"` (Pro web UI, `require "sidekiq/pro/web"`) with no authentication constraint. In the deployed environment that UI can retry, delete and enqueue jobs. Look for: new mounts (engines, `rails/info`, `mission_control`, web console) without a constraint; any widening of what `/sidekiq` exposes; copying this mount unguarded as a pattern (flag it as "canary only, add a `constraints` or auth block when copied")
- `MonitorsController#lb` and `MainController#hello` are intentionally public. A new controller inherits `ApplicationController < ActionController::Base`, which keeps CSRF protection. Look for `skip_forgery_protection` or new state-changing routes

**Secrets: the canary's fixtures versus real ones**

- `.env` is committed on purpose (`.gitignore` ignores `/.env*`, so it was force-added; `.dockerignore` deliberately does not exclude it and `COPY . .` bakes it into the image). Only placeholders are allowed: `TEST_SECRET=fake`, `SECRET_KEY_BASE=secret`, empty `SIDEKIQ_CREDS=`, localhost Redis. A real secret, token, password or key in `.env` (or in any new `.env.*`) is a blocker
- `app/views/main/hello.html.erb` renders `ENV['TEST_SECRET']` to prove secret injection works in deployed environments. Rendering any other ENV value, or logging one, is a blocker. Look for new `ENV[...]` reads that reach a view, a log line or an error message
- `SIDEKIQ_CREDS` (the `user:password` for `gems.contribsys.com`) enters the Dockerfile as `ARG SIDEKIQ_CREDS`, then `bundle config --global gems.contribsys.com $SIDEKIQ_CREDS`, so it is stored in the image's bundler config and visible in build history. Look for: moving it to an ENV, echoing it in `build.sh`, adding it to logs; prefer a BuildKit secret mount if the Dockerfile is touched
- In CI the same credential is `BUNDLE_GEMS__CONTRIBSYS__COM` from `secrets`; for Dependabot it is the `contribsys` registry token. Look for a workflow step that echoes it, a `pull_request_target` trigger, or secrets handed to an untrusted job

**Logging as a data-exposure path**

- `config/initializers/lograge.rb` logs `event.payload[:params]` minus controller/action/format/id, and passes the full `request` object in `custom_payload`. The only filter for logged params is `config/initializers/filter_parameter_logging.rb` (`:passw, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn, :cvv, :cvc`). Look for: removing entries; new sensitive param names not covered; headers or the cookie/session added to the Datadog JSON in `lib/log/logger/formatter.rb`; the `:request` key not deleted before serialization (the formatter must `data.delete(:request)`)
- `config.log_level` defaults to `info`; the production comment warns that `debug` can log PII. Look for a default raised to `debug`

**Transport and host protections**

- `production.rb` sets `assume_ssl = true`, `force_ssl = true`, and excludes only `BaseImageRubyTest::HEALTHCHECK_PATH` from the SSL redirect. Look for: broader redirect exclusions; `force_ssl` or `assume_ssl` removed; `config.hosts`/`host_authorization` changes (production relies on the defaults; development whitelists `rails-canary-lab.aws.cru.org`, and `web_console.permissions` is `10.0.0.0/8`)
- `config/initializers/content_security_policy.rb` is entirely commented out, so no CSP header is sent today. A change that adds inline scripts or third-party assets should not rely on a CSP that does not exist
- Session store is Redis (`redis_store`), expiring after 2 days; cookie flags come from Rails defaults plus `force_ssl`. Look for `secure: false` or SameSite changes

**Supply chain and CI**

- Look for new gems (`Gemfile` is small; every addition is a new surface), new gem sources, and a changed `ruby-vips` floor (boot guard for CVE-2026-66066)
- `bin/bundler-audit` + `config/bundler-audit.yml` (`ignore: []`) is the CVE ignore mechanism. An added ignore needs a stated reason; `vars.CVE_IGNORES` is an org-level knob and must not be hardcoded into the workflow
- `.github/workflows/dependabot-auto-merge.yml` grants `contents: write` and `pull-requests: write` and calls `dependabot-auto-merge-security-patch.yml@v2` with GitHub App secrets. Look for permission widening, a change from a released tag to a branch, or auto-merge scope beyond security patches
- `.github/dependabot.yml` bundler entry sets `insecure-external-code-execution: allow` (needed for the private source). Look for that setting spreading to other entries
- `brakeman -A -q` runs in CI; look for brakeman ignore files or flag changes that reduce coverage

### Mined from PR history

- A suppression of a vulnerability or scanner finding (an `ignore:` entry in `config/bundler-audit.yml`, a `--ignore` in a workflow, a `config/brakeman.ignore` entry, a lower brakeman `-w` confidence flag) names the advisory and the reason, and the PR that fixes the advisory removes it. Never silence brakeman's Rails EOL warning; fix it by bumping brakeman or Rails
  <!-- evidence: PR #83, #84, #87, #91, #93, #100, #101, #105, #108, #109, #163, #164, #165 -->
- `uses:` refs to `CruGlobal/.github` reusable workflows and actions point at a released tag (`@v1`, `@v2`). A raw SHA needs an adjacent comment with the reason and the re-pin condition; a branch ref is a finding
  <!-- evidence: PR #154, #156 -->
- `.github/dependabot.yml` keeps the security-only gem shape: bundler `open-pull-requests-limit: 0`, the `security-patches` group (`applies-to: security-updates`, patch only), the `contribsys` registry, no `target-branch`, commit prefixes `fix(deps)` for gems and `ci(deps)` for actions. The auto-merge caller only arms for patch-level security updates. Flag any widening
  <!-- evidence: PR #137, #138, #148, #154 -->
