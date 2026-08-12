# frozen_string_literal: true

module Cin7CoreAPI
  module Resources
    class Locations < Base
      PARAMETERS = {
        page: "Page",
        limit: "Limit",
        id: "ID",
        deprecated: "Deprecated",
        name: "Name"
      }.freeze

      def list(**filters)
        get("ref/location", params: filters, parameter_map: PARAMETERS)
      end
    end
  end
end
