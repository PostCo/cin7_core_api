# frozen_string_literal: true

require "cin7_core_api"
require "faraday/adapter/test"

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed
end

module ClientHelpers
  TEST_BASE_URL = "https://example.test/ExternalApi/v2/"

  def build_client(stubs)
    Cin7CoreAPI::Client.new(
      account_id: "test-account-id",
      application_key: "test-application-key",
      base_url: TEST_BASE_URL,
      adapter: [:test, stubs]
    )
  end

  def json_response(body, status: 200, headers: {})
    [status, {"Content-Type" => "application/json"}.merge(headers), JSON.generate(body)]
  end
end

RSpec.configure do |config|
  config.include ClientHelpers
end
