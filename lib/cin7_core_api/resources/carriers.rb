# frozen_string_literal: true

module Cin7CoreAPI
  module Resources
    class Carriers < Base
      PARAMETERS = {page: "Page", limit: "Limit", carrier_id: "CarrierID", description: "Description"}.freeze

      def list(**filters)
        get("ref/carrier", params: filters, parameter_map: PARAMETERS)
      end
    end
  end
end
