# frozen_string_literal: true

module Cin7CoreAPI
  module Resources
    class Base
      attr_reader :connection

      def initialize(connection)
        @connection = connection
      end

      private

      def get(path, params: {}, parameter_map: {})
        connection.get(path, params: map_parameters(params, parameter_map))
      end

      def map_parameters(params, parameter_map)
        unknown = params.keys - parameter_map.keys
        unless unknown.empty?
          raise ArgumentError, "Unknown parameters: #{unknown.sort.join(", ")}"
        end

        params.each_with_object({}) do |(key, value), mapped|
          mapped[parameter_map.fetch(key)] = value unless value.nil?
        end
      end

      def require_parameter!(name, value)
        missing = value.nil? || (value.respond_to?(:empty?) && value.empty?)
        return unless missing

        raise ArgumentError, "#{name} is required"
      end
    end
  end
end
