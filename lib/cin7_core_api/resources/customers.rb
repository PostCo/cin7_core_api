# frozen_string_literal: true

module Cin7CoreAPI
  module Resources
    class Customers < Base
      PARAMETERS = {
        page: "Page",
        limit: "Limit",
        id: "ID",
        name: "Name",
        modified_since: "ModifiedSince",
        include_deprecated: "IncludeDeprecated",
        include_product_prices: "IncludeProductPrices",
        contact_filter: "ContactFilter"
      }.freeze

      def list(**filters)
        get("customer", params: filters, parameter_map: PARAMETERS)
      end
    end
  end
end
