require_relative "boot"

require "rails/all"
require_relative "../lib/log/logger"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module BaseImageRubyTest
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 7.0

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    config.active_job.queue_adapter = :sidekiq

    redis_conf = YAML.safe_load(ERB.new(File.read(Rails.root.join("config", "redis.yml"))).result, permitted_classes: [Symbol], aliases: true)["cache"]
    redis_conf[:url] = "redis://" + redis_conf[:host] + "/" + redis_conf[:db].to_s
    config.cache_store = :redis_cache_store, redis_conf

    # Send all logs to stdout, which docker reads and sends to datadog.
    config.logger = Log::Logger.new($stdout) unless Rails.env.test? # we don't need a logger in test env
  end
end
