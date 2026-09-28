# frozen_string_literal: true

RSpec.describe "CIN7 Core credential redaction" do
  it "sanitizes webhook responses and headers without changing outbound credentials or input" do
    payload = {"Type" => "Sale/Created", "ExternalAuthorizationType" => "bearerauth",
               "ExternalBearerToken" => "private-hook-token", "ExternalPassword" => "private-password",
               "ExternalUserName" => "private-user", "IsActive" => false,
               "ExternalHeaders" => [{"Key" => "X-Custom", "Value" => "custom-secret"}]}
    original = Marshal.load(Marshal.dump(payload))
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post("/ExternalApi/v2/webhooks") do |env|
        expect(JSON.parse(env.body)).to eq(original)
        expect(env.request_headers["api-auth-applicationkey"]).to eq("test-application-key")
        response = {"Webhooks" => [payload.merge("ID" => "hook-id", "Note" => "private-hook-token private-password custom-secret")]}
        json_response(response, headers: {"Authorization" => "Bearer private-hook-token", "Set-Cookie" => "session=secret",
                                          "api-auth-accountid" => "test-account-id", "X-API-Key" => "unknown-response-key", "Retry-After" => "20"})
      end
    end
    response = build_client(stubs).webhooks.create(payload: payload)
    serialized = JSON.generate([response.body, response.headers])
    %w[private-hook-token private-password private-user custom-secret session=secret test-account-id unknown-response-key].each do |secret|
      expect(serialized).not_to include(secret)
    end
    hook = response.body.fetch("Webhooks").first
    expect(hook.fetch("ID")).to eq("hook-id")
    expect(hook.fetch("ExternalAuthorizationType")).to eq("bearerauth")
    expect(hook.fetch("IsActive")).to be(false)
    expect(response.headers.fetch("retry-after")).to eq("20")
    expect(payload).to eq(original)
  end

  it "filters newly discovered response secrets even when repeated in earlier error text" do
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.get("/ExternalApi/v2/webhooks") do
        json_response({"Message" => "unexpected-token unknown-header-secret", "Webhooks" => [{"ExternalBearerToken" => "unexpected-token"}]},
          status: 400, headers: {"X-API-Key" => "unknown-header-secret"})
      end
    end
    expect { build_client(stubs).webhooks.list }.to raise_error(Cin7CoreAPI::BadRequestError) { |error|
      expect([error.message, error.inspect, error.full_message, error.body, error.headers].inspect).not_to include("unexpected-token", "unknown-header-secret")
      expect(error.body.fetch("Message")).to include("[FILTERED]")
    }
  end

  it "redacts known secrets and labeled secrets from non-JSON bodies" do
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post("/ExternalApi/v2/webhooks") do
        [503, {}, 'test-application-key test-account-id password="unknown-password" ExternalBearerToken: unknown-token Bearer unknown-bearer private-hook-token']
      end
    end
    expect do
      build_client(stubs).webhooks.create(payload: {"ExternalBearerToken" => "private-hook-token"})
    end.to raise_error(Cin7CoreAPI::ServerError) { |error|
      %w[test-application-key test-account-id unknown-password unknown-token unknown-bearer private-hook-token].each do |secret|
        expect([error.body, error.message, error.full_message].inspect).not_to include(secret)
      end
    }
  end

  it "does not retain the unsafe transport exception as a cause" do
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post("/ExternalApi/v2/webhooks") do
        raise Faraday::ConnectionFailed, "test-application-key and arbitrary-request-secret"
      end
    end
    expect { build_client(stubs).webhooks.create(payload: {}) }.to raise_error(Cin7CoreAPI::TransportError) { |error|
      expect(error.cause).to be_nil
      expect(error.full_message).not_to include("test-application-key", "arbitrary-request-secret")
      expect(error).to be_ambiguous
    }
  end

  it "does not expose credentials or response contents through inspect" do
    client = build_client(Faraday::Adapter::Test::Stubs.new)
    objects = [client, client.connection, client.webhooks, Cin7CoreAPI::Redactor.new(["inspect-secret"]),
      Cin7CoreAPI::Response.new(status: 200, headers: {}, body: {"Note" => "private response"})]
    expect(objects.map(&:inspect).join).not_to include("test-account-id", "test-application-key", "inspect-secret", "private response")
  end

  it "does not leak secrets across clients" do
    first = Cin7CoreAPI::Redactor.new(["tenant-one-secret"])
    second = Cin7CoreAPI::Redactor.new(["tenant-two-secret"])
    expect(first.filter("tenant-one-secret tenant-two-secret")).to eq("[FILTERED] tenant-two-secret")
    expect(second.filter("tenant-one-secret tenant-two-secret")).to eq("tenant-one-secret [FILTERED]")
  end

  it "recognizes sensitive keys regardless of case or separators" do
    value = {"external_headers" => [{"Key" => "X-Secret", "Value" => "custom-value"}],
             "API_AUTH_APPLICATIONKEY" => "application-value", "external_bearer_token" => "bearer-value",
             "Description" => "custom-value application-value bearer-value"}
    filtered = Cin7CoreAPI::Redactor.new.with_sensitive_values(value).filter(value)
    expect(filtered.fetch("external_headers")).to eq("[FILTERED]")
    expect(filtered.fetch("Description")).not_to include("custom-value", "application-value", "bearer-value")
  end

  it "does not treat custom header names as secrets or corrupt webhook field names" do
    value = {"ID" => "hook-id", "ExternalAuthorizationType" => "basicauth",
             "ExternalHeaders" => [{"Key" => "ID", "Value" => "private-value"}, {"Key" => "Authorization", "Value" => "custom-auth"}]}
    filtered = Cin7CoreAPI::Redactor.new.with_sensitive_values(value).filter(value)
    expect(filtered.fetch("ID")).to eq("hook-id")
    expect(filtered.fetch("ExternalAuthorizationType")).to eq("basicauth")
    expect(filtered.fetch("ExternalHeaders")).to eq("[FILTERED]")
  end

  it "redacts URL credentials and an authorization token echoed without its scheme" do
    value = {"Authorization" => "Bearer unusual-bearer-value", "Message" => "unusual-bearer-value",
             "ExternalURL" => "https://name:uri-password@example.test/hook"}
    filtered = Cin7CoreAPI::Redactor.new.with_sensitive_values(value).filter(value)
    expect(filtered.fetch("Message")).to eq("[FILTERED]")
    expect(filtered.fetch("ExternalURL")).to eq("https://[FILTERED]@example.test/hook")
  end
end
