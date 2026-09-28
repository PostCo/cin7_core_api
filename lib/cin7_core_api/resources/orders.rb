# frozen_string_literal: true

module Cin7CoreAPI
  module Resources
    class Orders < Base
      PARAMETERS = {
        sale_id: "SaleID",
        combine_additional_charges: "CombineAdditionalCharges",
        include_product_info: "IncludeProductInfo"
      }.freeze

      def for_sale(sale_id:, **options)
        require_parameter!(:sale_id, sale_id)
        get("sale/order", params: options.merge(sale_id: sale_id), parameter_map: PARAMETERS)
      end

      def create(payload:)
        validate_payload!(payload, "SaleID")
        connection.post("sale/order", payload: payload)
      end
    end
  end
end
