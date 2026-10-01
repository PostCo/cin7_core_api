# frozen_string_literal: true

require "faraday"
require "json"
require "zlib"

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
      @redactor = Redactor.new([account_id, application_key])
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
      request(:get, path, params: params)
    end

    def post(path, payload:)
      request(:post, path, payload: payload)
    end

    def put(path, payload:)
      request(:put, path, payload: payload)
    end

    def delete(path, params: {})
      request(:delete, path, params: params)
    end

    def inspect
      "#<#{self.class}>"
    end

    private

    def normalize_base_url(base_url)
      base_url.end_with?("/") ? base_url : "#{base_url}/"
    end

    def request(method, path, params: {}, payload: nil)
      # Serialize before dispatch: invalid input is not an ambiguous remote write.
      body = JSON.generate(payload) unless payload.nil?
      redactor = @redactor.with_sensitive_values(payload)
      context = {request_method: method, request_path: redactor.filter(path.split("?").first)}
      write = method != :get

      raw_response = dispatch(method, path, body, params, context, write: write)
      parsed_body, valid_json = parse_body(raw_response.body)
      values = {"headers" => normalized_headers(raw_response.headers), "body" => parsed_body}
      sanitized = redactor.with_sensitive_values(values).filter(values, callback_redactor: redactor)
      response = Response.new(status: raw_response.status, headers: sanitized.fetch("headers"), body: sanitized.fetch("body"))

      raise_for_status!(response, context, write: write)
      if response.status != 204 && (!valid_json || (write && parsed_body.nil?))
        raise ParseError.new("CIN7 Core returned invalid or empty JSON", response: response, ambiguous: write, **context)
      end

      response
    end

    def dispatch(method, path, body, params, context, write:)
      @http.run_request(method, path, body, nil) do |request|
        request.params.update(params)
      end
    rescue Faraday::Error, Zlib::Error => error
      # Faraday exceptions can retain the entire authenticated request in their cause.
      raise TransportError.new("CIN7 Core transport failed (#{error.class})", ambiguous: write, **context), cause: nil
    end

    def normalized_headers(headers)
      headers.to_h.transform_keys { |key| key.to_s.downcase }
    end

    def parse_body(body)
      return [nil, true] if body.nil? || body.empty?

      # JSON is UTF-8 even when the adapter labels its bytes as binary. Reject
      # malformed success bodies, but keep rejection details safe to redact.
      body = body.dup.force_encoding(Encoding::UTF_8)
      return [body.scrub, false] unless body.valid_encoding?

      parsed = JSON.parse(body)
      # Some JSON parsers accept lone low-surrogate escapes and produce invalid
      # strings. Do not expose or regex-filter partially decoded credentials.
      valid_utf8?(parsed) ? [parsed, true] : [Redactor::FILTERED, false]
    rescue JSON::ParserError
      [body, false]
    end

    def valid_utf8?(value)
      case value
      when Hash
        value.all? { |key, entry| valid_utf8?(key) && valid_utf8?(entry) }
      when Array
        value.all? { |entry| valid_utf8?(entry) }
      when String
        value.valid_encoding?
      else
        true
      end
    end

    def raise_for_status!(response, context, write:)
      return if response.success?

      error_class = ERROR_CLASSES.fetch(response.status) do
        (response.status >= 500) ? ServerError : Error
      end

      # Details remain available in the sanitized body, never in log-friendly messages.
      raise error_class.new("CIN7 Core request failed with HTTP #{response.status}",
        response: response, ambiguous: write && response.status >= 500, **context)
    end
  end
end
