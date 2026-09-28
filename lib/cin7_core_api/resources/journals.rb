# frozen_string_literal: true

module Cin7CoreAPI
  module Resources
    class Journals < Base
      PARAMETERS = {
        page: "Page", limit: "Limit", task_id: "TaskID", status: "Status", search: "Search"
      }.freeze

      def list(**filters)
        get("journal", params: filters, parameter_map: PARAMETERS)
      end

      def retrieve(task_id:)
        require_parameter!(:task_id, task_id)
        list(task_id: task_id)
      end

      def create(payload:)
        validate_payload!(payload)
        connection.post("journal", payload: payload)
      end

      def update(payload:)
        validate_payload!(payload, "TaskID")
        connection.put("journal", payload: payload)
      end
    end
  end
end
