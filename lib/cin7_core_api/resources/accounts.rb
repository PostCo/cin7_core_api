# frozen_string_literal: true

module Cin7CoreAPI
  module Resources
    class Accounts < Base
      PARAMETERS = {
        page: "Page",
        limit: "Limit",
        code: "Code",
        name: "Name",
        type: "Type",
        status: "Status"
      }.freeze

      def list(**filters)
        get("ref/account", params: filters, parameter_map: PARAMETERS)
      end
    end
  end
end
