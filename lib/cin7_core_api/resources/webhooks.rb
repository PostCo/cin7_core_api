# frozen_string_literal: true

module Cin7CoreAPI
  module Resources
    class Webhooks < Base
      def list
        get("webhooks")
      end

      def create(payload:)
        validate_payload!(payload)
        connection.post("webhooks", payload: payload)
      end

      def update(payload:)
        validate_payload!(payload, "ID")
        connection.put("webhooks", payload: payload)
      end

      def delete(id:)
        require_parameter!(:id, id)
        connection.delete("webhooks", params: {"ID" => id})
      end
    end
  end
end
