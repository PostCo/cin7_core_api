# frozen_string_literal: true

module Cin7CoreAPI
  class Response
    attr_reader :status, :headers, :body

    def initialize(status:, headers:, body:)
      @status = status
      @headers = headers.freeze
      @body = body
      freeze
    end

    def success?
      (200..299).cover?(status)
    end

    def no_content?
      status == 204 || body.nil?
    end
  end
end
