# frozen_string_literal: true

module Cin7CoreAPI
  module Resources
    class Fulfilments < Base
      PARAMETERS = {sale_id: "SaleID", include_product_info: "IncludeProductInfo"}.freeze

      def for_sale(sale_id:, **options)
        require_parameter!(:sale_id, sale_id)
        get("sale/fulfilment", params: options.merge(sale_id: sale_id), parameter_map: PARAMETERS)
      end

      def create(payload:)
        validate_payload!(payload, "SaleID")
        connection.post("sale/fulfilment", payload: payload)
      end

      def undo(task_id:)
        require_parameter!(:task_id, task_id)
        connection.delete("sale/fulfilment", params: {"TaskID" => task_id, "Void" => false})
      end
    end
  end
end
