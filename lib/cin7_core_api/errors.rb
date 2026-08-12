# frozen_string_literal: true

module Cin7CoreAPI
  class Error < StandardError
    attr_reader :response

    def initialize(message = nil, response: nil)
      @response = response
      super(message)
    end

    def status
      response&.status
    end

    def headers
      response&.headers
    end

    def body
      response&.body
    end

    def retry_after
      headers&.fetch("retry-after", nil)
    end
  end

  class BadRequestError < Error; end
  class AuthenticationError < Error; end
  class ForbiddenError < Error; end
  class NotFoundError < Error; end
  class MethodNotAllowedError < Error; end
  class RateLimitError < Error; end
  class ServerError < Error; end
  class TransportError < Error; end
  class ParseError < Error; end
end
