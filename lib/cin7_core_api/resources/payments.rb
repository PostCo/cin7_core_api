# frozen_string_literal: true

module Cin7CoreAPI
  module Resources
    class Payments < Base
      PARAMETERS = {sale_id: "SaleID"}.freeze

      def for_sale(sale_id:)
        require_parameter!(:sale_id, sale_id)
        get("sale/payment", params: {sale_id: sale_id}, parameter_map: PARAMETERS)
      end

      def create(payload:)
        validate_payload!(payload, "TaskID")
        connection.post("sale/payment", payload: payload)
      end

      def update(payload:)
        validate_payload!(payload, "ID")
        connection.put("sale/payment", payload: payload)
      end

      def delete(id:)
        require_parameter!(:id, id)
        connection.delete("sale/payment", params: {"ID" => id})
      end
    end
  end
end
