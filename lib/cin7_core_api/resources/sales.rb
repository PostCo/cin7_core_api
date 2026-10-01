# frozen_string_literal: true

module Cin7CoreAPI
  module Resources
    class Sales < Base
      LIST_PARAMETERS = {
        page: "Page",
        limit: "Limit",
        search: "Search",
        created_since: "CreatedSince",
        updated_since: "UpdatedSince",
        updated_until: "UpdatedUntil",
        ship_by: "ShipBy",
        quote_status: "QuoteStatus",
        order_status: "OrderStatus",
        combined_pick_status: "CombinedPickStatus",
        combined_pack_status: "CombinedPackStatus",
        combined_shipping_status: "CombinedShippingStatus",
        combined_invoice_status: "CombinedInvoiceStatus",
        credit_note_status: "CreditNoteStatus",
        external_id: "ExternalID",
        status: "Status",
        ready_for_shipping: "ReadyForShipping",
        order_location_id: "OrderLocationID"
      }.freeze

      RETRIEVE_PARAMETERS = {
        id: "ID",
        combine_additional_charges: "CombineAdditionalCharges",
        hide_inventory_movements: "HideInventoryMovements",
        include_transactions: "IncludeTransactions",
        country_format: "CountryFormat"
      }.freeze

      def list(**filters)
        get("saleList", params: filters, parameter_map: LIST_PARAMETERS)
      end

      def retrieve(id:, **options)
        require_parameter!(:id, id)
        get("sale", params: options.merge(id: id), parameter_map: RETRIEVE_PARAMETERS)
      end

      def create(payload:)
        validate_payload!(payload)
        connection.post("sale", payload: payload)
      end

      def update(payload:)
        validate_payload!(payload, "ID")
        connection.put("sale", payload: payload)
      end

      def undo(id:)
        require_parameter!(:id, id)
        connection.delete("sale", params: {"ID" => id, "Void" => false})
      end
    end
  end
end
