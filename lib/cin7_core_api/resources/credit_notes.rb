# frozen_string_literal: true

module Cin7CoreAPI
  module Resources
    class CreditNotes < Base
      LIST_PARAMETERS = {
        page: "Page",
        limit: "Limit",
        search: "Search",
        created_since: "CreatedSince",
        updated_since: "UpdatedSince",
        updated_until: "UpdatedUntil",
        credit_note_status: "CreditNoteStatus",
        status: "Status"
      }.freeze

      FOR_SALE_PARAMETERS = {
        sale_id: "SaleID",
        combine_additional_charges: "CombineAdditionalCharges",
        include_product_info: "IncludeProductInfo",
        include_payment_info: "IncludePaymentInfo"
      }.freeze

      def list(**filters)
        get("saleCreditNoteList", params: filters, parameter_map: LIST_PARAMETERS)
      end

      def for_sale(sale_id:, **options)
        require_parameter!(:sale_id, sale_id)
        get("sale/creditnote", params: options.merge(sale_id: sale_id), parameter_map: FOR_SALE_PARAMETERS)
      end

      def create(payload:)
        validate_payload!(payload, "SaleID", "TaskID")
        connection.post("sale/creditnote", payload: payload)
      end

      def undo(task_id:)
        require_parameter!(:task_id, task_id)
        connection.delete("sale/creditnote", params: {"TaskID" => task_id, "Void" => false})
      end
    end
  end
end
