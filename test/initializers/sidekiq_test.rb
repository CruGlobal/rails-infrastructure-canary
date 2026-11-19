require "test_helper"

class SidekiqInitializerTest < ActiveSupport::TestCase
  test "activates Sidekiq Pro reliable push on the client" do
    assert_includes Sidekiq::Client.ancestors, Sidekiq::ReliableClient
  end
end
