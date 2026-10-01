# frozen_string_literal: true

module Cin7CoreAPI
  module Resources
    class ProductAvailability < Base
      PARAMETERS = {
        page: "Page", limit: "Limit", id: "ID", name: "Name", sku: "Sku",
        location: "Location", batch: "Batch", category: "Category"
      }.freeze

      def list(**filters)
        get("ref/productavailability", params: filters, parameter_map: PARAMETERS)
      end
    end
  end
end
