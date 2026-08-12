# frozen_string_literal: true

require "faraday"
require "json"

module Cin7CoreAPI
  class Connection
    ERROR_CLASSES = {
      400 => BadRequestError,
      401 => AuthenticationError,
      403 => ForbiddenError,
      404 => NotFoundError,
      405 => MethodNotAllowedError,
      429 => RateLimitError
    }.freeze

    def initialize(account_id:, application_key:, base_url:, open_timeout:, timeout:, adapter:)
      @http = Faraday.new(url: normalize_base_url(base_url)) do |connection|
        connection.headers["Accept"] = "application/json"
        connection.headers["Content-Type"] = "application/json"
        connection.headers["User-Agent"] = "cin7_core_api/#{VERSION}"
        connection.headers["api-auth-accountid"] = account_id
        connection.headers["api-auth-applicationkey"] = application_key
        connection.options.open_timeout = open_timeout
        connection.options.timeout = timeout
        connection.adapter(*Array(adapter))
      end
    end

    def get(path, params: {})
      raw_response = @http.get(path, params)
      response = build_response(raw_response)

      raise_for_status!(response)
      raise ParseError.new("CIN7 Core returned invalid JSON", response: response) if invalid_success_json?(raw_response, response)

      response
    rescue Faraday::Error => error
      raise TransportError, "CIN7 Core request failed: #{error.message}"
    end

    private

    def normalize_base_url(base_url)
      base_url.end_with?("/") ? base_url : "#{base_url}/"
    end

    def build_response(raw_response)
      Response.new(
        status: raw_response.status,
        headers: normalized_headers(raw_response.headers),
        body: parse_body(raw_response.body)
      )
    end

    def normalized_headers(headers)
      headers.to_h.transform_keys { |key| key.to_s.downcase }
    end

    def parse_body(body)
      return nil if body.nil? || body.empty?

      JSON.parse(body)
    rescue JSON::ParserError
      body
    end

    def invalid_success_json?(raw_response, response)
      response.success? && !response.no_content? && response.body.equal?(raw_response.body)
    end

    def raise_for_status!(response)
      return if response.success?

      error_class = ERROR_CLASSES.fetch(response.status) do
        (response.status >= 500) ? ServerError : Error
      end

      raise error_class.new(error_message(response), response: response)
    end

    def error_message(response)
      detail = case response.body
      when Hash, Array
        JSON.generate(response.body)
      when nil
        "no response body"
      else
        response.body.to_s
      end

      "CIN7 Core request failed with HTTP #{response.status}: #{detail}"
    end
  end
end
