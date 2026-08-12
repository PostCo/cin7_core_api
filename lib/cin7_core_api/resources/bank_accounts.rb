# frozen_string_literal: true

module Cin7CoreAPI
  module Resources
    class BankAccounts < Base
      PARAMETERS = {
        page: "Page",
        limit: "Limit",
        id: "ID",
        name: "Name",
        bank: "Bank"
      }.freeze

      def list(**filters)
        get("ref/account/bank", params: filters, parameter_map: PARAMETERS)
      end
    end
  end
end
