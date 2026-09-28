# frozen_string_literal: true

module Cin7CoreAPI
  module Resources
    class Invoices < Base
      PARAMETERS = {
        sale_id: "SaleID",
        combine_additional_charges: "CombineAdditionalCharges",
        include_product_info: "IncludeProductInfo"
      }.freeze

      def for_sale(sale_id:, **options)
        require_parameter!(:sale_id, sale_id)
        get("sale/invoice", params: options.merge(sale_id: sale_id), parameter_map: PARAMETERS)
      end

      def create(payload:)
        validate_payload!(payload, "SaleID", "TaskID")
        connection.post("sale/invoice", payload: payload)
      end

      def update(payload:)
        validate_payload!(payload, "SaleID", "TaskID")
        connection.put("sale/invoice", payload: payload)
      end

      def undo(task_id:)
        require_parameter!(:task_id, task_id)
        connection.delete("sale/invoice", params: {"TaskID" => task_id, "Void" => false})
      end
    end
  end
end
