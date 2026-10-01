# frozen_string_literal: true

module Cin7CoreAPI
  module Resources
    class Packs < Base
      PARAMETERS = {task_id: "TaskID", include_product_info: "IncludeProductInfo"}.freeze

      def for_task(task_id:, **options)
        require_parameter!(:task_id, task_id)
        get("sale/fulfilment/pack", params: options.merge(task_id: task_id), parameter_map: PARAMETERS)
      end

      def create(payload:)
        validate_payload!(payload, "TaskID")
        connection.post("sale/fulfilment/pack", payload: payload)
      end

      def update(payload:)
        validate_payload!(payload, "TaskID")
        connection.put("sale/fulfilment/pack", payload: payload)
      end
    end
  end
end
