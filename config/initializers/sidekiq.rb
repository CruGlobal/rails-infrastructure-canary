require "redis"
require "datadog/statsd"

redis_conf = YAML.safe_load(ERB.new(File.read(Rails.root.join("config", "redis.yml"))).result, [Symbol], [], true)["sidekiq"]

Redis.current = Redis.new(redis_conf)

redis_settings = {url: Redis.current.id,
                  namespace: redis_conf[:namespace],}

Sidekiq.configure_client do |config|
  config.redis = redis_settings
end

Sidekiq::Client.reliable_push! if Sidekiq::Client.method_defined? :reliable_push!

Sidekiq.configure_server do |config|
  config.super_fetch!
  config.reliable_scheduler!
  config.redis = redis_settings
end

Sidekiq.default_job_options = {backtrace: true}

Sidekiq::Pro.dogstatsd = -> { Datadog::Statsd.new(ENV["DATADOG_HOST"], ENV["DATADOG_PORT"]) } unless Rails.env.development? || Rails.env.test?
