# Run using bin/ci

CI.run do
  step "Setup", "bin/setup --skip-server"

  step "Style: Ruby", "bundle exec standardrb --format simple"

  step "Security: Gem audit", "bin/bundler-audit check --update"
  step "Security: Importmap vulnerability audit", "bin/importmap audit"
  step "Security: Brakeman code analysis", "bin/brakeman --no-pager"
  step "Tests: Rails", "bin/rails test"
end
