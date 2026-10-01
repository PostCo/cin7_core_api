# frozen_string_literal: true

module Cin7CoreAPI
  module Resources
    class TaxRules < Base
      PARAMETERS = {
        page: "Page", limit: "Limit", id: "ID", name: "Name", is_active: "IsActive",
        is_tax_for_sale: "IsTaxForSale", is_tax_for_purchase: "IsTaxForPurchase", account: "Account"
      }.freeze

      def list(**filters)
        get("ref/tax", params: filters, parameter_map: PARAMETERS)
      end
    end
  end
end
