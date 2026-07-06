# frozen_string_literal: true

require_relative "earningscall_biz/version"

module EarningsCallBiz
  class Error < StandardError; end
  class InvalidApiKey < Error; end
  class InsufficientApiAccess < Error; end
  class NotFound < Error; end
  class InvalidResponse < Error; end

  class ServiceUnavailable < Error
    attr_reader :http_status, :retry_after

    def initialize(message, http_status: nil, retry_after: nil)
      super(message)
      @http_status = http_status
      @retry_after = retry_after
    end
  end
end

require_relative "earningscall_biz/api"
