# frozen_string_literal: true

module Cin7CoreAPI
  module Resources
    class ManualJournals < Base
      def for_sale(sale_id:)
        require_parameter!(:sale_id, sale_id)
        get("sale/manualJournal", params: {sale_id: sale_id}, parameter_map: {sale_id: "SaleID"})
      end

      def create(payload:)
        validate_payload!(payload, "SaleID")
        connection.post("sale/manualJournal", payload: payload)
      end
    end
  end
end
