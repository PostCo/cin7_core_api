# frozen_string_literal: true

module Cin7CoreAPI
  module Resources
    class Me < Base
      def retrieve
        get("me")
      end
    end
  end
end
