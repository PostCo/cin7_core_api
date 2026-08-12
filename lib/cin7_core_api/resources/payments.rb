# frozen_string_literal: true

module Cin7CoreAPI
  module Resources
    class Payments < Base
      PARAMETERS = {sale_id: "SaleID"}.freeze

      def for_sale(sale_id:)
        require_parameter!(:sale_id, sale_id)
        get("sale/payment", params: {sale_id: sale_id}, parameter_map: PARAMETERS)
      end
    end
  end
end
