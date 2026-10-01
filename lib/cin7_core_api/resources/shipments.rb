# frozen_string_literal: true

module Cin7CoreAPI
  module Resources
    class Shipments < Base
      def for_task(task_id:)
        require_parameter!(:task_id, task_id)
        get("sale/fulfilment/ship", params: {task_id: task_id}, parameter_map: {task_id: "TaskID"})
      end

      def create(payload:)
        validate_payload!(payload, "TaskID")
        connection.post("sale/fulfilment/ship", payload: payload)
      end

      def update(payload:)
        validate_payload!(payload, "TaskID")
        connection.put("sale/fulfilment/ship", payload: payload)
      end
    end
  end
end
