# Log each distinct deprecation once per process (production and staging use :notify).
seen = Concurrent::Map.new
ActiveSupport::Notifications.subscribe(/\Adeprecation\./) do |event|
  payload = event.payload
  frame = Rails.backtrace_cleaner.clean(payload[:callstack].map(&:to_s)).first
  next unless seen.put_if_absent("#{payload[:message]}|#{frame}", true).nil?
  Rails.logger.warn("DEPRECATION WARNING: #{payload[:message]} [#{payload[:gem_name]} #{payload[:deprecation_horizon]}] #{frame}")
end
