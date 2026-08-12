# frozen_string_literal: true

module Cin7CoreAPI
  module Resources
    class CustomerCredits < Base
      PARAMETERS = {
        page: "Page",
        limit: "Limit",
        customer_id: "CustomerID",
        show_used_credits: "ShowUsedCredits"
      }.freeze

      def list(**filters)
        get("ref/customer/credits", params: filters, parameter_map: PARAMETERS)
      end
    end
  end
end
