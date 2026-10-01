# frozen_string_literal: true

module Cin7CoreAPI
  module Resources
    class Products < Base
      PARAMETERS = {
        id: "ID", page: "Page", limit: "Limit", name: "Name", sku: "Sku", modified_since: "ModifiedSince",
        include_deprecated: "IncludeDeprecated", include_bom: "IncludeBOM", include_suppliers: "IncludeSuppliers",
        include_movements: "IncludeMovements", include_attachments: "IncludeAttachments",
        include_reorder_levels: "IncludeReorderLevels", include_custom_prices: "IncludeCustomPrices"
      }.freeze

      def list(**filters)
        get("product", params: filters, parameter_map: PARAMETERS)
      end
    end
  end
end
