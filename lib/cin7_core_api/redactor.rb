# frozen_string_literal: true

module Cin7CoreAPI
  # Only sanitized copies leave the transport. Never mutate a caller's payload.
  class Redactor
    FILTERED = "[FILTERED]"
    SENSITIVE_KEY = /authorization|authentication|password|passwd|secret|token|cookie|apikey|applicationkey|accountid|externalusername/i

    def initialize(secrets = [])
      @secrets = secrets.grep(String).reject(&:empty?).uniq.sort_by { |value| -value.length }.map { |value| value.dup.freeze }.freeze
    end

    def with_sensitive_values(value)
      self.class.new(@secrets + sensitive_values(value))
    end

    def filter(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, entry), result|
          result[filter_string(key.to_s)] = if sensitive_key?(key) || external_headers?(key)
            FILTERED
          else
            filter(entry)
          end
        end
      when Array
        value.map { |entry| filter(entry) }
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
      normalized = key.to_s.gsub(/[^a-z0-9]/i, "").downcase
      normalized != "externalauthorizationtype" && normalized.match?(SENSITIVE_KEY)
    end

    def external_headers?(key)
      key.to_s.gsub(/[^a-z0-9]/i, "").casecmp?("externalheaders")
    end

    def sensitive_values(value)
      case value
      when Hash
        value.flat_map do |key, entry|
          if external_headers?(key)
            Array(entry).flat_map { |header| header.is_a?(Hash) ? strings_in(header["Value"] || header[:Value] || header["value"]) : [] }
          elsif sensitive_key?(key)
            strings_in(entry)
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

    def filter_string(value)
      filtered = @secrets.reduce(value.dup) { |text, secret| text.gsub(secret, FILTERED) }
      filtered = filtered.gsub(%r{(https?://)[^\s/@]+:[^\s/@]+@}i, "\\1#{FILTERED}@")
      # Non-JSON error bodies may echo credentials as header or form text.
      filtered = filtered.gsub(/\b(Bearer|Basic)\s+[^\s,"'<>]+/i, "\\1 #{FILTERED}")
      filtered.gsub(/([\w-]*(?:password|passwd|secret|token|authorization|api[-_]?key|application[-_]?key|account[-_]?id)[\w-]*["']?\s*[:=]\s*)(?:"[^"]*"|'[^']*'|[^\s,;&<>]+)/i, "\\1#{FILTERED}")
    end
  end
end
