# frozen_string_literal: true

require "uri"

module Cin7CoreAPI
  # Only sanitized copies leave the transport. Never mutate a caller's payload.
  class Redactor
    FILTERED = "[FILTERED]"
    SENSITIVE_KEY = /authorization|authentication|password|passwd|secret|token|cookie|apikey|applicationkey|apiauthaccountid|externalusername/i
    GUID = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i
    HTTP_URL = %r{\A(https?://)([^/?#]*)([^?#]*)(?:\?([^#]*))?(?:\#(.*))?\z}i

    def initialize(secrets = [])
      @secrets = secrets.grep(String).reject(&:empty?).uniq.sort_by { |value| -value.length }.map { |value| value.dup.freeze }.freeze
    end

    def with_sensitive_values(value)
      self.class.new(@secrets + sensitive_values(value))
    end

    def filter(value, callback_redactor: self)
      case value
      when Hash
        value.each_with_object({}) do |(key, entry), result|
          # Field names are schema, even when a credential happens to match one.
          result[key.to_s] = if sensitive_key?(key) || external_headers?(key)
            FILTERED
          elsif callback_url?(key) && entry.is_a?(String)
            # Another subscription's credentials may equal this callback's
            # integration ID or host label. Scope URL filtering to this record.
            callback_redactor.with_sensitive_values(value).filter_url(entry)
          elsif structured_identifier?(key, entry)
            # Short header values must not corrupt identifiers or schema enums.
            @secrets.include?(entry) ? FILTERED : entry.dup
          else
            filter(entry, callback_redactor: callback_redactor)
          end
        end
      when Array
        value.map { |entry| filter(entry, callback_redactor: callback_redactor) }
      when String
        filter_string(value)
      else
        value
      end
    end

    def inspect
      "#<#{self.class}>"
    end

    private

    def sensitive_key?(key)
      normalized = normalized_key(key)
      # AccountID and BankAccountId identify business records, not API access.
      # The authentication header is api-auth-accountid; known credential values
      # are still filtered wherever they occur, including business ID fields.
      normalized != "externalauthorizationtype" && normalized.match?(SENSITIVE_KEY)
    end

    def normalized_key(key)
      key.to_s.gsub(/[^a-z0-9]/i, "").downcase
    end

    def external_headers?(key)
      normalized_key(key) == "externalheaders"
    end

    def callback_url?(key)
      normalized_key(key) == "externalurl"
    end

    def structured_identifier?(key, value)
      value.is_a?(String) && ((normalized_key(key).end_with?("id") && GUID.match?(value)) ||
        %w[type externalauthorizationtype].include?(normalized_key(key)))
    end

    def sensitive_values(value)
      case value
      when Hash
        value.flat_map do |key, entry|
          if external_headers?(key)
            Array(entry).flat_map { |header| header.is_a?(Hash) ? strings_in(header["Value"] || header[:Value] || header["value"]) : [] }
          elsif sensitive_key?(key)
            strings_in(entry)
          elsif callback_url?(key) && entry.is_a?(String)
            url_credentials(entry)
          else
            sensitive_values(entry)
          end
        end
      when Array
        value.flat_map { |entry| sensitive_values(entry) }
      else
        []
      end
    end

    def strings_in(value)
      case value
      when Hash then value.values.flat_map { |entry| strings_in(entry) }
      when Array then value.flat_map { |entry| strings_in(entry) }
      when String then [value, value.sub(/\A(?:Bearer|Basic)\s+/i, "")]
      else []
      end
    end

    def sensitive_query_key?(key)
      sensitive_key?(key) || %w[accountid username user auth key signature sig].include?(normalized_key(key))
    end

    def url_credentials(value)
      url = URI.parse(value)
      return [] unless url.is_a?(URI::HTTP) && url.host

      credentials = url.userinfo.to_s.split(":", 2).flat_map { |part| [part, URI::DEFAULT_PARSER.unescape(part)] }
      [url.query, url.fragment].compact.each do |query|
        query.split(/[&;]/).each do |part|
          key, separator, entry = part.partition("=")
          if !separator.empty? && sensitive_query_key?(URI.decode_www_form_component(key))
            credentials.concat([entry, URI.decode_www_form_component(entry)])
          end
        end
      end
      strings_in(credentials)
    rescue URI::InvalidURIError, ArgumentError
      []
    end

    protected

    def filter_url(value)
      return FILTERED if @secrets.include?(value)

      url = URI.parse(value)
      return FILTERED unless url.is_a?(URI::HTTP) && url.host

      # Keep spelling, escaping, parameter order and delimiters intact. Rebuilding
      # a URI or substring-filtering it can change callback ownership comparisons.
      scheme, authority, path, query, fragment = HTTP_URL.match(value).captures
      authority = filter_authority(authority, url.host)
      path = path.split("/", -1).map { |part| filter_url_component(part) }.join("/")
      result = "#{scheme}#{authority}#{path}"
      result += "?#{filter_query(query)}" unless query.nil?
      result += "##{filter_query(fragment)}" unless fragment.nil?
      result
    rescue URI::InvalidURIError, ArgumentError
      FILTERED
    end

    private

    def filter_authority(authority, host)
      _, separator, host_port = authority.rpartition("@")
      filtered_host = filter_url_component(host)
      if filtered_host != FILTERED
        filtered_host = host.split(".", -1).map { |part| filter_url_component(part) }.join(".")
      end
      filtered = host_port.sub(host) { filtered_host }
      separator.empty? ? filtered : "#{FILTERED}@#{filtered}"
    end

    def filter_query(query)
      query.split(/([&;])/, -1).map do |part|
        key, separator, entry = part.partition("=")
        if separator.empty?
          filter_url_component(key, form: true)
        else
          filtered = sensitive_query_key?(URI.decode_www_form_component(key)) ? FILTERED : filter_url_component(entry, form: true)
          "#{filter_url_component(key, form: true)}=#{filtered}"
        end
      end.join
    end

    def filter_url_component(value, form: false)
      decoded = form ? URI.decode_www_form_component(value) : URI::DEFAULT_PARSER.unescape(value)
      (@secrets.include?(value) || @secrets.include?(decoded)) ? FILTERED : value
    end

    def filter_string(value)
      filtered = @secrets.reduce(value.dup) { |text, secret| text.gsub(secret, FILTERED) }
      filtered = filtered.gsub(%r{(https?://)[^\s/@]+:[^\s/@]+@}i, "\\1#{FILTERED}@")
      # Non-JSON error bodies may echo credentials as header or form text.
      filtered = filtered.gsub(/\b(Bearer|Basic)\s+[^\s,"'<>]+/i, "\\1 #{FILTERED}")
      filtered.gsub(/([\w-]*(?:password|passwd|secret|token|authorization|api[-_]?key|application[-_]?key|account[-_]?id)[\w-]*["']?\s*[:=]\s*)(?:"[^"]*"|'[^']*'|[^\s,;&<>]+)/i, "\\1#{FILTERED}")
    end
  end
end
