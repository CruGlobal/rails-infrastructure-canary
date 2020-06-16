class LogTestJob < ApplicationJob
  queue_as :default

  def perform(*args)
    Rails.logger.info("Testing Sidekiq: Successful")
  end
end
